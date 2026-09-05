"""Конверсия аудио-башни CLAP в Core ML для локального разбора звука на iPhone.

Что делает, по шагам:
  1. Повторяет фронтенд `ClapFeatureExtractor` (ветка rand_trunc: мел-фильтры
     slaney, hann 1024, hop 480, power 2, dB) в чистом torch и сверяет с
     оригиналом численно.
  2. Оборачивает фронтенд + HTSAT + проекцию в один модуль:
     вход — 480000 сэмплов (10 с при 48 кГц), выход — L2-нормированный
     512-мерный вектор. Repeat-pad коротких клипов остаётся на вызывающем:
     он тривиален и делается в Swift.
  3. Трассирует и конвертирует в mlprogram fp16 (iOS 17).
  4. Сверяет Core ML с torch на эталонных сигналах (тишина, синус,
     синтетический мотор, шум) — теми же, какими замерялся привратник.
  5. Экспортирует всё, что нужно Swift помимо энкодера, в один JSON:
     текстовые эмбеддинги промптов привратника, logit_scale, головы
     kind/knock/cause из joblib (scaler + логрег + температуры).

Запуск (venv проекта car-diagnosis, там уже есть torch и transformers):
    cd ~/Desktop/car-diagnosis && ./.venv/bin/python \
        ~/Desktop/ios-app/tools/clap_to_coreml.py --out /tmp/clap-export
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

CLAP_ID = "laion/clap-htsat-unfused"
SR = 48_000
N_SAMPLES = 480_000          # 10 с — вход энкодера фиксированный
N_FFT = 1024
HOP = 480
PROMPTS = [                  # порядок как в diagnosis_server.py: индекс 1 — мотор
    "music or a song with a beat",
    "a mechanical car noise or engine sound",
    "a person talking",
    "silence or ambient room noise",
]


class MelFrontend(torch.nn.Module):
    """Ветка rand_trunc из ClapFeatureExtractor, в torch и без numpy.

    STFT собран как conv1d с DFT-ядрами (окно вшито в ядра), а не torch.stft
    или unfold: ни того, ни другого конвертер Core ML не умеет, а свёртка
    с шагом hop — это ровно тот же фрейминг+DFT одним оператором.
    """

    def __init__(self, mel_slaney: np.ndarray):
        super().__init__()
        window = torch.hann_window(N_FFT, periodic=True)
        k = torch.arange(N_FFT // 2 + 1).unsqueeze(1) * torch.arange(N_FFT).unsqueeze(0)
        angle = 2 * torch.pi * k / N_FFT
        self.register_buffer("cos_k", (torch.cos(angle) * window).unsqueeze(1))   # (513, 1, 1024)
        self.register_buffer("sin_k", (-torch.sin(angle) * window).unsqueeze(1))  # (513, 1, 1024)
        self.register_buffer("mel", torch.from_numpy(mel_slaney).float())         # (513, 64)

    def forward(self, wave: torch.Tensor) -> torch.Tensor:  # (1, 480000)
        y = F.pad(wave.unsqueeze(1), (N_FFT // 2, N_FFT // 2), mode="reflect")
        re = F.conv1d(y, self.cos_k, stride=HOP)             # (1, 513, 1001)
        im = F.conv1d(y, self.sin_k, stride=HOP)
        power = re * re + im * im
        mel = power.transpose(1, 2) @ self.mel               # (1, 1001, 64)
        return 10.0 * torch.log10(torch.clamp(mel, min=1e-10))


class EncoderOnly(torch.nn.Module):
    """Мел (1, 1001, 64) → L2-нормированный вектор 512. Отдельно от фронтенда:
    трансформер терпит fp16, а у power-спектра динамический диапазон ~200 дБ —
    fp16 жмёт его с обеих сторон (сверху переполнение на громком, снизу
    денормалы на тихом), поэтому мел считается своей fp32-моделью."""

    def __init__(self, clap):
        super().__init__()
        self.audio_model = clap.audio_model
        self.projection = clap.audio_projection

    def forward(self, mel: torch.Tensor) -> torch.Tensor:
        pooled = self.audio_model(input_features=mel.unsqueeze(1)).pooler_output
        v = self.projection(pooled)
        return v / (v.norm(dim=-1, keepdim=True) + 1e-9)


class AudioTower(torch.nn.Module):
    """Волна 480000 → вектор 512: torch-эталон полной цепочки для сверки."""

    def __init__(self, clap, mel_slaney: np.ndarray):
        super().__init__()
        self.frontend = MelFrontend(mel_slaney)
        self.encoder = EncoderOnly(clap)

    def forward(self, wave: torch.Tensor) -> torch.Tensor:
        return self.encoder(self.frontend(wave))


def patch_bicubic(encoder) -> None:
    """Подменяет `reshape_mel2img`: та же бикубическая интерполяция времени
    1001 → 1024 (align_corners=True), но постоянной матрицей — оператор
    `upsample_bicubic2d` конвертер Core ML не умеет, а матмул с константой
    при фиксированном входе численно эквивалентен. Матрица получается
    прогоном единичной матрицы через сам interpolate: по второй оси размер
    не меняется, и с align_corners=True это тождество.
    """
    import types

    time_in = N_SAMPLES // HOP + 1                       # 1001
    spec_width = encoder.spec_size * encoder.freq_ratio  # 1024
    eye = torch.eye(time_in).unsqueeze(0).unsqueeze(0)
    weight = F.interpolate(eye, size=(spec_width, time_in),
                           mode="bicubic", align_corners=True)[0, 0]  # (1024, 1001)
    ratio = encoder.freq_ratio

    def reshape(self, x):
        x = torch.matmul(weight.to(x.dtype), x)          # (B, 1, 1024, 64)
        batch, channels, time, freq = x.shape
        x = x.reshape(batch, channels * ratio, time // ratio, freq)
        x = x.permute(0, 1, 3, 2).contiguous()
        return x.reshape(batch, channels, freq * ratio, time // ratio)

    encoder.reshape_mel2img = types.MethodType(reshape, encoder)


def reference_signals() -> dict[str, np.ndarray]:
    """Эталоны из замеров привратника: тишина, синус, «мотор», шум комнаты."""
    t = np.arange(N_SAMPLES) / SR
    rng = np.random.default_rng(7)
    engine = sum(np.sin(2 * np.pi * f * t + p) * a for f, p, a in
                 [(55, 0.0, 0.55), (110, 1.0, 0.35), (165, 2.1, 0.22),
                  (220, 0.4, 0.14), (330, 1.7, 0.08)])
    engine += rng.normal(0, 0.12, N_SAMPLES)
    engine *= 1 + 0.35 * np.sin(2 * np.pi * 4.5 * t)         # неровный холостой
    return {
        "silence": np.zeros(N_SAMPLES, dtype=np.float32),
        # Чистый цифровой синус — краш-тест: его шумовой пол −100 dB, и там
        # видны ошибки fp32 против numpy-шного fp64. Записей с таким полом
        # у микрофона не бывает, поэтому у него отдельный, мягкий порог.
        "sine440": (0.4 * np.sin(2 * np.pi * 440 * t)).astype(np.float32),
        # А это реалистичный тональный сигнал: тот же синус поверх пола
        # комнаты — он обязан сходиться так же строго, как мотор и шум.
        "sine_mic": (0.4 * np.sin(2 * np.pi * 440 * t)
                     + rng.normal(0, 0.003, N_SAMPLES)).astype(np.float32),
        "engine": (engine / np.abs(engine).max() * 0.6).astype(np.float32),
        "room": rng.normal(0, 0.01, N_SAMPLES).astype(np.float32),
    } | demo_signal()


def demo_signal() -> dict[str, np.ndarray]:
    """demo.wav из cardiag — настоящая громкая запись: ровно на ней ловилось
    fp16-переполнение power-спектра. Нули справа — паддинг привратника
    (`Clap.score` зовёт процессор с padding=True), поэтому гейт-числа внизу
    сравнимы с замерами из DIAGNOSIS.md."""
    demo = Path.home() / "Desktop/car-diagnosis/src/cardiag/_fixtures/demo.wav"
    if not demo.exists():
        return {}
    import librosa
    y, _ = librosa.load(str(demo), sr=SR, mono=True)
    return {"demo": np.pad(y, (0, max(0, N_SAMPLES - len(y))))[:N_SAMPLES].astype(np.float32)}


def export_heads(art: dict) -> dict:
    """Головы sklearn → голые массивы: scaler, коэффициенты, классы, T."""
    out = {}
    for name, head in art["heads"].items():
        scaler = getattr(head, "named_steps", {}).get("scaler") or getattr(head, "steps", [[None, None]])[0][1]
        clf = getattr(head, "named_steps", {}).get("clf") or getattr(head, "steps", [[None, None]])[-1][1]
        entry = {
            "classes": [str(c) for c in clf.classes_],
            "coef": np.asarray(clf.coef_).tolist(),
            "intercept": np.asarray(clf.intercept_).tolist(),
            "temperature": float(art.get("temps", {}).get(name, 1.0)),
        }
        if scaler is not None and hasattr(scaler, "mean_"):
            entry["scaler_mean"] = np.asarray(scaler.mean_).tolist()
            entry["scaler_scale"] = np.asarray(scaler.scale_).tolist()
        out[name] = entry
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/clap-export")
    ap.add_argument("--model", default=str(Path.home() / "Desktop/car-diagnosis/models/best_model_clap.joblib"))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    from transformers import ClapModel, ClapProcessor
    print("[1/5] загрузка CLAP…", flush=True)
    # Две копии: эталон остаётся нетронутым, а у конвертируемой подменяется
    # bicubic-интерполяция — иначе сверка проверяла бы подмену саму собой.
    model = ClapModel.from_pretrained(CLAP_ID).eval()
    conv_model = ClapModel.from_pretrained(CLAP_ID).eval()
    proc = ClapProcessor.from_pretrained(CLAP_ID)
    fe = proc.feature_extractor

    patch_bicubic(conv_model.audio_model.audio_encoder)
    tower = AudioTower(conv_model, np.asarray(fe.mel_filters_slaney)).eval()
    signals = reference_signals()

    print("[2/5] сверка фронтенда и эмбеддинга с оригиналом…", flush=True)
    report = {}
    for name, y in signals.items():
        ref_mel = fe(y, sampling_rate=SR, return_tensors="np")["input_features"][0, 0]
        with torch.no_grad():
            our_mel = tower.frontend(torch.from_numpy(y).unsqueeze(0))[0].numpy()
        mel_diff = float(np.abs(ref_mel - our_mel).max())

        inp = proc(audio=y, sampling_rate=SR, return_tensors="pt")
        with torch.no_grad():
            feats = model.get_audio_features(**inp)
            # transformers 5.x возвращает ModelOutput; спроецированный вектор —
            # в pooler_output (тот же путь берёт и cardiag.audio.clap)
            ref = feats if torch.is_tensor(feats) else getattr(feats, "audio_embeds", feats.pooler_output)
            ref = ref[0]
            ref = (ref / ref.norm()).numpy()
            ours = tower(torch.from_numpy(y).unsqueeze(0))[0].numpy()
        cos = float(np.dot(ref, ours))
        report[name] = {"mel_max_diff": mel_diff, "torch_cosine": cos}
        print(f"    {name:8s} мел |Δ|max={mel_diff:.5f}  cos(torch)={cos:.6f}", flush=True)
    for name, r in report.items():
        floor = 0.98 if name == "sine440" else 0.999
        assert r["torch_cosine"] > floor, f"фронтенд разошёлся на {name}: {r}"

    print("[3/5] экспорт графов и конверсия в Core ML…", flush=True)
    import coremltools as ct
    # torch.export вместо jit.trace: в трассированном графе HTSAT остаются
    # узлы `aten::Int` над массивами, на которых конвертер падает; экспорт
    # со статическими размерами таких узлов не порождает.
    n_frames = N_SAMPLES // HOP + 1
    mel_exported = torch.export.export(tower.frontend, (torch.zeros(1, N_SAMPLES),)) \
        .run_decompositions({})
    mel_ml = ct.convert(
        mel_exported,
        inputs=[ct.TensorType(name="waveform", shape=(1, N_SAMPLES), dtype=np.float32)],
        outputs=[ct.TensorType(name="mel", dtype=np.float32)],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT32,
        convert_to="mlprogram",
    )
    mel_pkg = out / "ClapMelFrontend.mlpackage"
    mel_ml.save(str(mel_pkg))

    enc_exported = torch.export.export(tower.encoder, (torch.zeros(1, n_frames, 64),)) \
        .run_decompositions({})
    enc_ml = ct.convert(
        enc_exported,
        inputs=[ct.TensorType(name="mel", shape=(1, n_frames, 64), dtype=np.float32)],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )
    enc_pkg = out / "ClapAudioEncoder.mlpackage"
    enc_ml.save(str(enc_pkg))
    print(f"    сохранено: {mel_pkg}\n    и {enc_pkg}", flush=True)

    print("[4/5] паритет Core ML против torch (цепочка мел → энкодер)…", flush=True)
    for name, y in signals.items():
        mel_out = mel_ml.predict({"waveform": y[None, :].astype(np.float32)})["mel"]
        pred = enc_ml.predict({"mel": mel_out.astype(np.float32)})["embedding"][0]
        pred = pred / (np.linalg.norm(pred) + 1e-9)
        with torch.no_grad():
            ref = tower(torch.from_numpy(y).unsqueeze(0))[0].numpy()
        cos = float(np.dot(ref, pred))
        report[name]["coreml_cosine"] = cos
        print(f"    {name:8s} cos(coreml)={cos:.6f}", flush=True)
    for name, r in report.items():
        floor = 0.97 if name in ("sine440", "silence") else 0.999
        assert r["coreml_cosine"] > floor, f"Core ML разошёлся на {name}: {r}"

    print("[5/5] экспорт текстовых промптов и голов…", flush=True)
    t_inp = proc(text=PROMPTS, return_tensors="pt", padding=True)
    with torch.no_grad():
        t = model.get_text_features(**t_inp)
        if not torch.is_tensor(t):
            t = getattr(t, "text_embeds", t.pooler_output)
        t = t / t.norm(dim=-1, keepdim=True)
    logit_scale_a = float(model.logit_scale_a.exp())

    import joblib
    art = joblib.load(args.model)

    sidecar = {
        "prompts": PROMPTS,
        "prompt_codes": ["music", "engine", "speech", "silence"],
        "engine_index": 1,
        "engine_threshold": 0.5,
        # Паддинги сервера РАЗНЫЕ, и это его фактическое поведение, с которого
        # сняты все пороги: привратник (`Clap.score`, padding=True) дополняет
        # запись нулями, эмбеддинги для голов (`Clap.embed`, дефолт
        # repeatpad) — повтором записи. Swift обязан повторить оба.
        "gate_padding": "zeros",
        "embed_padding": "repeatpad",
        "logit_scale_a": logit_scale_a,
        "text_embeddings": t.numpy().tolist(),
        "heads": export_heads(art),
        "fault_hi": 0.6,
        "fault_lo": 0.4,
        "parity": report,
    }
    (out / "DiagnosisSupport.json").write_text(json.dumps(sidecar))
    kb = (out / "DiagnosisSupport.json").stat().st_size // 1024
    print(f"    DiagnosisSupport.json: {kb} КБ, logit_scale_a={logit_scale_a:.3f}")

    # Гейт-скоры «как на сервере» — прямо здесь, для сверки со Swift позже
    print("\nгейт (softmax logit_scale·cos), доля «мотор»:")
    for name, y in signals.items():
        with torch.no_grad():
            a = tower(torch.from_numpy(y).unsqueeze(0))
            logits = logit_scale_a * (a @ t.T)
            probs = logits.softmax(-1)[0].numpy()
        print(f"    {name:8s} engine={probs[1]:.2f}  " +
              " ".join(f"{c}={p:.2f}" for c, p in zip(["music", "engine", "speech", "silence"], probs)))


if __name__ == "__main__":
    main()
