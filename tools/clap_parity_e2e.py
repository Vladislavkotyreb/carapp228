"""Сквозная сверка локального разбора с серверным на одном файле.

Серверный путь — ровно тот код, что крутится в diagnosis_server.py:
`Clap().score` для привратника и `Classifier.diagnose` для голов. Наш путь —
то, что будет на телефоне: repeat-pad → Core ML энкодер → гейт softmax по
текстовым эмбеддингам из DiagnosisSupport.json → головы оттуда же.

Сегментацию `clean()` наш путь берёт питоновскую: её порт в Swift — отдельный
шаг, а здесь проверяются энкодер, гейт и головы на одинаковых кусках.

Запуск (в venv car-diagnosis):
    cd ~/Desktop/car-diagnosis && ./.venv/bin/python \
        ~/Desktop/ios-app/tools/clap_parity_e2e.py --export /tmp/clap-export \
        [--wav путь/к/записи.wav]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

SR = 48_000
N_SAMPLES = 480_000


def repeatpad(y: np.ndarray) -> np.ndarray:
    """padding="repeatpad" из ClapFeatureExtractor: tile + нули справа.
    Так сервер готовит куски для голов (`Clap.embed` — процессор без padding)."""
    if len(y) >= N_SAMPLES:
        return y[:N_SAMPLES]
    n = int(N_SAMPLES / len(y))
    y = np.tile(y, n)
    return np.pad(y, (0, N_SAMPLES - len(y)))


def zeropad(y: np.ndarray) -> np.ndarray:
    """`padding=True` из `Clap.score`: просто нули справа — именно с таким
    паддингом сняты все замеры привратника (мотор 0.86, тишина 0.38…).
    Запись длиннее 10 с сервер режет случайным кропом; локально берём первые
    10 с — детерминированное подмножество того же поведения."""
    if len(y) >= N_SAMPLES:
        return y[:N_SAMPLES]
    return np.pad(y, (0, N_SAMPLES - len(y)))


def head_probs(entry: dict, X: np.ndarray) -> dict[str, float]:
    """Повтор `_proba` из cardiag: скалирование, логиты, температура, пулинг."""
    mean = np.asarray(entry.get("scaler_mean", np.zeros(X.shape[1])))
    scale = np.asarray(entry.get("scaler_scale", np.ones(X.shape[1])))
    coef = np.asarray(entry["coef"])
    intercept = np.asarray(entry["intercept"])
    T = entry.get("temperature", 1.0) or 1.0

    Z = (X - mean) / scale
    d = Z @ coef.T + intercept                    # (n, k) или (n, 1)
    if d.shape[1] == 1:                           # бинарная: сигмоида логита
        p1 = 1.0 / (1.0 + np.exp(-d[:, 0] / T))
        P = np.column_stack([1.0 - p1, p1])
    else:
        e = np.exp((d - d.max(1, keepdims=True)) / T)
        P = e / e.sum(1, keepdims=True)
    return dict(zip(entry["classes"], P.mean(0)))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--export", default="/tmp/clap-export")
    ap.add_argument("--wav", default=str(Path.home() /
                    "Desktop/car-diagnosis/src/cardiag/_fixtures/demo.wav"))
    args = ap.parse_args()

    import coremltools as ct
    import librosa

    from cardiag import config
    from cardiag.audio.clap import Clap
    from cardiag.audio.embed import model_vectors, window_spans
    from cardiag.inference.classifier import Classifier, _proba

    support = json.loads((Path(args.export) / "DiagnosisSupport.json").read_text())
    mlmodel = ct.models.MLModel(str(Path(args.export) / "ClapAudioEncoder.mlpackage"))
    text = np.asarray(support["text_embeddings"])          # (4, 512)
    scale = support["logit_scale_a"]

    mel_ml = ct.models.MLModel(str(Path(args.export) / "ClapMelFrontend.mlpackage"))

    def coreml_embed(y: np.ndarray) -> np.ndarray:
        mel = mel_ml.predict({"waveform": y[None, :].astype(np.float32)})["mel"]
        v = mlmodel.predict({"mel": mel.astype(np.float32)})["embedding"][0]
        return v / (np.linalg.norm(v) + 1e-9)

    audio, _ = librosa.load(args.wav, sr=SR, mono=True)
    print(f"файл: {args.wav} ({len(audio) / SR:.1f} с)")

    # --- привратник ---
    clap = Clap()
    server_scores = clap.score([audio], support["prompts"], sr=SR)[0]
    ours = coreml_embed(zeropad(audio))
    logits = scale * (text @ ours)
    local_scores = np.exp(logits - logits.max())
    local_scores /= local_scores.sum()
    print("\nпривратник (music/engine/speech/silence):")
    print("  сервер :", " ".join(f"{s:.3f}" for s in server_scores))
    print("  локально:", " ".join(f"{s:.3f}" for s in local_scores))
    gate_diff = float(np.abs(server_scores - local_scores).max())
    print(f"  |Δ|max = {gate_diff:.4f}")

    # --- головы на одинаковых кусках ---
    from cardiag.audio.clean import clean
    ev = model_vectors(args.wav, clean_audio=True)
    res = ev.clean_result
    if res is not None and res.isolated:
        spans = [w for span in res.isolated for w in window_spans(span, res.sr)]
    else:
        spans = [audio]     # тот же фолбэк «окна всего файла» для короткой записи
    print(f"\nсегментов после clean(): {ev.n} векторов, источник {ev.source}")

    clf = Classifier.load()
    X_local = np.stack([coreml_embed(repeatpad(s)) for s in spans])
    X_server = ev.vectors if len(ev.vectors) else clap.embed([audio], sr=SR)

    emb_cos = [float(a @ b) for a, b in zip(X_server, X_local)] \
        if X_server.shape == X_local.shape else ["формы разошлись", X_server.shape, X_local.shape]
    print("cos(сервер, локально) по кускам:", emb_cos)

    print("\nголовы:")
    for name in ("kind", "knock", "cause"):
        T = clf.temps.get(name, 1.0)
        server = _proba(clf.heads[name], X_server, T)
        local = head_probs(support["heads"][name], X_local)
        keys = sorted(server, key=server.get, reverse=True)[:3]
        print(f"  {name}:")
        for k in keys:
            print(f"    {k:22s} сервер {server[k]:.4f} | локально {local.get(str(k), float('nan')):.4f}")


if __name__ == "__main__":
    main()
