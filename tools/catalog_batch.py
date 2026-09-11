"""Ночная генерация каталога машин Кандинским 5.0 на MPS.

Читает tools/catalog_cars.json, пишет ~/canary-catalog/raw/{slug}.png.
Отличие от kandinsky5_local.py — модель грузится один раз на весь батч:
сначала энкодеры кодируют все промпты (эмбеддинги маленькие, живут на CPU),
затем DiT+VAE генерят подряд. Кадр с нечёрными краями ретраится другими
сидами, из попыток остаётся лучшая по пику яркости периметра.

Уже готовые файлы пропускаются — батч можно прерывать и дозапускать.

Запуск (переживает закрытие терминала, не даёт маку уснуть):
    nohup caffeinate -is ~/Library/Caches/kandinsky5-venv/bin/python \
        tools/catalog_batch.py > ~/canary-catalog/gen.log 2>&1 & disown
"""
from __future__ import annotations

import gc
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from car_image_gen import NEGATIVE_PROMPT, build_prompt, edges_are_black, finalize

MODEL = "kandinskylab/Kandinsky-5.0-T2I-Lite-sft-Diffusers"
CATALOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "catalog_cars.json")
OUT_DIR = os.path.expanduser("~/canary-catalog/raw")
SEEDS = (7, 11, 23)
STEPS = 30


def log(message: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {message}", flush=True)


def main() -> None:
    import torch
    from diffusers import Kandinsky5T2IPipeline

    os.makedirs(OUT_DIR, exist_ok=True)
    cars = json.load(open(CATALOG))
    todo = [c for c in cars
            if not os.path.exists(os.path.join(OUT_DIR, c["slug"] + ".png"))]
    log(f"каталог: {len(cars)} машин, к генерации: {len(todo)}")
    if not todo:
        return

    started = time.time()
    pipe = Kandinsky5T2IPipeline.from_pretrained(
        MODEL, transformer=None, vae=None, torch_dtype=torch.bfloat16)
    pipe.to("mps")
    log(f"энкодеры загружены за {time.time() - started:.0f} с")

    embeds: dict[str, list] = {}
    with torch.no_grad():
        negative = [t.cpu() for t in pipe.encode_prompt(
            NEGATIVE_PROMPT, device=torch.device("mps"), dtype=torch.bfloat16)]
        for car in todo:
            positive = pipe.encode_prompt(build_prompt(car["prompt"]),
                                          device=torch.device("mps"),
                                          dtype=torch.bfloat16)
            embeds[car["slug"]] = [t.cpu() for t in positive]
    log(f"промпты закодированы: {len(embeds)}")

    del pipe
    gc.collect()
    torch.mps.empty_cache()

    started = time.time()
    pipe = Kandinsky5T2IPipeline.from_pretrained(
        MODEL, text_encoder=None, tokenizer=None,
        text_encoder_2=None, tokenizer_2=None, torch_dtype=torch.bfloat16)
    pipe.to("mps")
    log(f"DiT+VAE загружены за {time.time() - started:.0f} с")

    neg_qwen, neg_clip, neg_cu = [t.to("mps") for t in negative]
    done = 0
    for car in todo:
        out_path = os.path.join(OUT_DIR, car["slug"] + ".png")
        pos_qwen, pos_clip, pos_cu = [t.to("mps") for t in embeds[car["slug"]]]
        best_peak = 256
        for attempt, seed in enumerate(SEEDS):
            started = time.time()
            image = pipe(
                prompt=None,
                prompt_embeds_qwen=pos_qwen, prompt_embeds_clip=pos_clip,
                prompt_cu_seqlens=pos_cu,
                negative_prompt_embeds_qwen=neg_qwen,
                negative_prompt_embeds_clip=neg_clip,
                negative_prompt_cu_seqlens=neg_cu,
                height=1024, width=1024,
                num_inference_steps=STEPS,
                guidance_scale=3.5,
                generator=torch.Generator("cpu").manual_seed(seed),
            ).image[0]
            # .try.png, а не .try: PIL выводит формат из расширения и на
            # незнакомом падает — причём и здесь, и внутри finalize.
            candidate = out_path + ".try.png"
            image.save(candidate)
            finalize(candidate, flip=True, floor=24)
            ok, peak = edges_are_black(candidate)
            if peak < best_peak:
                best_peak = peak
                os.replace(candidate, out_path)
            elif os.path.exists(candidate):
                os.remove(candidate)
            log(f"{car['slug']} seed {seed}: {time.time() - started:.0f} с, "
                f"пик {peak}{' — ок' if ok else ''}")
            if ok:
                break
        done += 1
        status = "ок" if best_peak <= 26 else f"ЛУЧШИЙ ПИК {best_peak} — проверить глазами"
        log(f"[{done}/{len(todo)}] {car['slug']}: {status}")

    log("ГОТОВО")


if __name__ == "__main__":
    main()
