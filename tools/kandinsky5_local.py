"""Кандинский 5.0 T2I Lite локально на Mac (MPS) — четвёртый путь генерации.

Единственный из проверенных генераторов, который знает русский автопарк:
Lada Vesta выходит настоящей (ладья, X-выштамповки), тогда как Flux и SD3
рисуют выдуманный «VESSA». API у Кандинского 5.0 нет нигде: серверлесс на
Hugging Face его не хостит (inference: None), живых Spaces нет — только
локальный запуск через diffusers.

Требования (однажды настроено, см. JOURNAL 2026-09-05):
  - веса ~31 GB в ~/.cache/huggingface (скачаются при первом запуске);
  - venv ~/Library/Caches/kandinsky5-venv:
      python3 -m venv ~/Library/Caches/kandinsky5-venv
      .../bin/pip install "diffusers>=0.40" torch torchvision transformers \
          accelerate safetensors sentencepiece protobuf Pillow qwen-vl-utils
  - замер на M4 Max 36 GB: загрузка ~21 с, генерация 30 шагов ~5.7 мин.

Загрузка двухфазная: полный стек ~30 GB рядом с системой в 36 GB не живёт
(процесс убивали по памяти). Сначала только текст-энкодеры (Qwen2.5-VL +
CLIP, ~19 GB), эмбеддинги снимаются на CPU, энкодеры выгружаются, и лишь
потом DiT + VAE (~13 GB).

Запуск:
    ~/Library/Caches/kandinsky5-venv/bin/python tools/kandinsky5_local.py \
        --car "2020 Lada Vesta sedan" --flip --out /tmp/vesta.png
"""
from __future__ import annotations

import argparse
import gc
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from car_image_gen import NEGATIVE_PROMPT, build_prompt, edges_are_black, finalize

MODEL = "kandinskylab/Kandinsky-5.0-T2I-Lite-sft-Diffusers"


def generate(car: str, out: str, seed: int, steps: int) -> None:
    import torch
    from diffusers import Kandinsky5T2IPipeline

    started = time.time()
    pipe = Kandinsky5T2IPipeline.from_pretrained(
        MODEL, transformer=None, vae=None, torch_dtype=torch.bfloat16)
    pipe.to("mps")
    print(f"энкодеры загружены: {time.time() - started:.0f} с", flush=True)

    with torch.no_grad():
        pos = pipe.encode_prompt(build_prompt(car),
                                 device=torch.device("mps"), dtype=torch.bfloat16)
        neg = pipe.encode_prompt(NEGATIVE_PROMPT,
                                 device=torch.device("mps"), dtype=torch.bfloat16)
    embeds = [tensor.cpu() for tensor in (*pos, *neg)]

    del pipe, pos, neg
    gc.collect()
    torch.mps.empty_cache()

    started = time.time()
    pipe = Kandinsky5T2IPipeline.from_pretrained(
        MODEL, text_encoder=None, tokenizer=None,
        text_encoder_2=None, tokenizer_2=None, torch_dtype=torch.bfloat16)
    pipe.to("mps")
    print(f"DiT+VAE загружены: {time.time() - started:.0f} с", flush=True)

    pos_qwen, pos_clip, pos_cu, neg_qwen, neg_clip, neg_cu = [
        tensor.to("mps") for tensor in embeds]

    started = time.time()
    image = pipe(
        prompt=None,
        prompt_embeds_qwen=pos_qwen, prompt_embeds_clip=pos_clip,
        prompt_cu_seqlens=pos_cu,
        negative_prompt_embeds_qwen=neg_qwen,
        negative_prompt_embeds_clip=neg_clip,
        negative_prompt_cu_seqlens=neg_cu,
        height=1024, width=1024,
        num_inference_steps=steps,
        guidance_scale=3.5,
        generator=torch.Generator("cpu").manual_seed(seed),
    ).image[0]
    image.save(out)
    print(f"генерация: {time.time() - started:.0f} с", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--car", required=True, help="например: 2020 Lada Vesta sedan")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--steps", type=int, default=30)
    ap.add_argument("--flip", action="store_true",
                    help="отзеркалить по горизонтали (морду вправо)")
    ap.add_argument("--floor", type=int, default=24,
                    help="порог прижатия фона к чёрному, 0 — выключить")
    args = ap.parse_args()

    generate(args.car, args.out, args.seed, args.steps)
    finalize(args.out, flip=args.flip, floor=args.floor)
    ok, peak = edges_are_black(args.out)
    verdict = "ок" if ok else f"НЕ ЧЁРНЫЕ (пик {peak}/255) — нужен ретрай"
    print(f"{args.car} → {args.out} | края: {verdict}")


if __name__ == "__main__":
    main()
