"""Сервер разбора звука двигателя для приложения Beepy.

Зачем свой, а не `cardiag serve`. У модели cardiag открытая проблема множества:
её головы обучены отличать неисправный двигатель от исправного и **не знают
варианта «это вообще не машина»**. Голова причин обязана разложить свои 100 %
по 21 детали при любом входе. Замерено на записях без мотора:

    тишина              -> «неисправность 73 %», выхлоп 100 %
    чистый синус        -> «неисправность 92 %», ШРУС 38 %
    фон комнаты         -> «неисправность 85 %», тормоза 82 %
    тишина с шорохами   -> «норма 32 %»,          выхлоп 86 %

То есть в тихой комнате приложение уверенно называло деталь. Ни один
предохранитель внутри самого ответа этого не ловит.

Привратник здесь — сам CLAP, который в пайплайне уже используется, но только
чтобы отсеять музыку. Он текстово-звуковой, поэтому умеет отвечать на вопрос
«это мотор или комната» напрямую. Замер тем же набором записей:

    мотор  0.86  |  тишина 0.38, холодильник 0.38, синус 0.29,
                    фон комнаты 0.11, шорохи 0.10

Порог 0.5 разделяет их с запасом.

Запуск:
    cd ~/Desktop/car-diagnosis && source .venv/bin/activate
    PYTHONPATH=~/Desktop/car-diagnosis/src \\
      uvicorn diagnosis_server:app --host 0.0.0.0 --port 8077 \\
      --app-dir ~/Desktop/ios-app/tools
"""
from __future__ import annotations

import os
import tempfile
import threading
from pathlib import Path

import librosa
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse

from cardiag import Classifier, config
from cardiag.audio.clap import Clap

app = FastAPI(title="beepy-diagnosis")

# Порядок промптов важен: индекс 1 — это и есть искомый «мотор». Формулировки
# взяты из `audio/clean.py`, чтобы не разойтись с тем, на чём гейт замерялся.
PROMPTS = [
    "music or a song with a beat",
    "a mechanical car noise or engine sound",
    "a person talking",
    "silence or ambient room noise",
]
# Короткие подписи тех же промптов — только для лога. Брать первое слово
# нельзя: два промпта начинаются с «a», и строка выходит нечитаемой.
PROMPT_LABELS = ["музыка", "МОТОР", "речь", "тишина"]
# Короткий код того, что услышали. Отдаём его приложению, чтобы оно не хранило
# у себя копию формулировок промптов: разойдутся — и экран начнёт врать.
PROMPT_CODES = ["music", "engine", "speech", "silence"]
ENGINE = 1
ENGINE_THRESHOLD = 0.5

MAX_BYTES = 50 * 1024 * 1024
OK_SUFFIX = {".wav", ".mp3", ".m4a", ".ogg", ".flac", ".aac", ".webm", ".mp4"}

# torch на MPS не потокобезопасен — ровно та же оговорка, что в самом cardiag.
_LOCK = threading.Lock()
_MODEL = os.environ.get("CARDIAG_MODEL",
                        str(Path.home() / "Desktop/car-diagnosis/models/best_model_clap.joblib"))

_clap: Clap | None = None
_classifier = None


def _lazy():
    """Модели поднимаются первым запросом, а не при импорте: иначе сервер
    полминуты не отвечает на /health и выглядит повисшим."""
    global _clap, _classifier
    if _clap is None:
        _clap = Clap()
    if _classifier is None:
        _classifier = Classifier.load(_MODEL)
    return _clap, _classifier


def _safe_suffix(name: str | None) -> str:
    suffix = Path(name or "").suffix.lower()
    return suffix if suffix in OK_SUFFIX else ".wav"


def _log(name, size, engine_p, scores, result) -> None:
    """Строка на запрос — иначе неудачный тест не диагностируется.

    Записи не сохраняются, переспросить «а что там было» после теста нельзя,
    поэтому всё существенное печатается сразу: прошёл ли привратник и с какой
    оценкой, сколько чистых кусков выделил каскад, что решили головы.
    """
    parts = [
        f"[разбор] {name or 'без имени'} {size / 1024:.0f} КБ",
        f"мотор {engine_p:.2f}" + (" ПРОШЁЛ" if engine_p >= ENGINE_THRESHOLD else " отклонён"),
        " ".join(f"{label}={s:.2f}" for label, s in zip(PROMPT_LABELS, scores)),
    ]
    if result is not None:
        d = result.to_dict()
        causes = d.get("causes") or []
        top = f"{causes[0]['part']} {causes[0]['p']:.2f}" if causes else "нет версий"
        parts += [
            f"сегментов {len(d.get('segments') or [])}",
            f"вердикт {d.get('verdict')} {d.get('fault_probability')}",
            f"версия {top}",
        ]
    print(" | ".join(parts), flush=True)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "gate": "clap", "threshold": ENGINE_THRESHOLD}


@app.post("/diagnose")
async def diagnose(file: UploadFile = File(...)) -> JSONResponse:
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=_safe_suffix(file.filename),
                                         delete=False) as tmp:
            tmp_path = tmp.name
            total = 0
            while chunk := await file.read(1 << 20):
                total += len(chunk)
                if total > MAX_BYTES:
                    return JSONResponse({"error": "файл слишком большой"}, status_code=413)
                tmp.write(chunk)
        if total == 0:
            return JSONResponse({"error": "пустая загрузка"}, status_code=400)

        with _LOCK:
            clap, clf = _lazy()

            # Привратник считается по всей записи целиком, а не по кускам,
            # которые выделил каскад: смысл как раз в том, чтобы поймать
            # запись, где выделять нечего.
            audio, _ = librosa.load(tmp_path, sr=config.SR_CLAP, mono=True)
            if audio.size == 0:
                return JSONResponse({"error": "не удалось прочитать звук"}, status_code=400)
            scores = clap.score([audio], PROMPTS, sr=config.SR_CLAP)[0]
            engine_p = float(scores[ENGINE])

            heard = PROMPT_CODES[int(max(range(len(scores)), key=lambda i: scores[i]))]
            payload = {
                "engine_probability": round(engine_p, 3),
                "engine_scores": {p: round(float(s), 3) for p, s in zip(PROMPTS, scores)},
                # Что прозвучало громче всего. Приложению нужен именно этот
                # код: по нему оно объясняет человеку, что помешало.
                "heard": heard,
            }

            # Не мотор — дальше не считаем вовсе. Возвращать разбор «на всякий
            # случай» нельзя: именно он и выглядел убедительной выдумкой.
            if engine_p < ENGINE_THRESHOLD:
                payload["model_loaded"] = True
                payload["is_engine"] = False
                _log(file.filename, total, engine_p, scores, None)
                return JSONResponse(payload)

            result = clf.diagnose(tmp_path)

        payload.update(result.to_dict())
        payload["is_engine"] = True
        payload["model_loaded"] = True
        _log(file.filename, total, engine_p, scores, result)
        return JSONResponse(payload)
    except (ValueError, FileNotFoundError, OSError):
        return JSONResponse({"error": "не удалось обработать запись"}, status_code=400)
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)
