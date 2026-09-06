"""Генерация студийного изображения машины по мастер-промпту.

Цель — кадр в стиле ассета главной: белый автомобиль в три четверти,
морда вправо, чистый чёрный фон. Контракт держат три вещи: мастер-промпт,
негативный промпт и валидатор краёв (периметр кадра обязан быть чёрным —
иначе при анимации выезда видно «летящий прямоугольник», а не машину).

Провайдеры:
  kandinsky   — FusionBrain API (Кандинский 3.x). Нужны бесплатные ключи
                с fusionbrain.ai: env FUSIONBRAIN_KEY и FUSIONBRAIN_SECRET.
  hf          — Hugging Face Inference (SD3-medium): единственный из трёх
                провайдер, который читает негативный промпт. Токен —
                env HF_TOKEN (лежит в ~/Desktop/motion-studio/.env).
  pollinations — публичный Flux без ключей; для быстрой проверки промпта.

Запуск:
    python3 tools/car_image_gen.py --provider pollinations \
        --car "2016 Lexus RX 350" --out /tmp/rx.png
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import time
import urllib.parse
import urllib.request

# Мастер-промпт. Подстановка {car} — «{год} {марка} {модель}».
# Вторая итерация: «studio photograph» уводил модель в серый бокс с полом,
# а негативный промпт Flux не читает — чёрный фон и ракурс сказаны прямо
# в позитивной части («black void», «low-key», «front pointing right»).
# Третья итерация: сторона ракурса у модели нестабильна — берём её
# стабильное «влево» и зеркалим программно; дымку и асфальт глушим прямо
# в тексте, остаток фона прижимает к нулю постобработка (--floor).
# Четвёртая итерация — под ключевой референс пользователя: камера ближе и
# чуть выше капота, широкоугольная перспектива, машина занимает почти весь
# кадр; «каталожный» дальний план с полями по центру убран.
MASTER_PROMPT = (
    "advertising photo of a {car}, glossy white paint, dramatic front "
    "three-quarter view from a slightly elevated camera looking down at "
    "the car, wide-angle perspective, the car is large and fills most of "
    "the frame, entire car still fully visible with tight margins, "
    "headlights visible, no license plate, car floating in complete "
    "darkness, pure black empty background, image corners pure black, "
    "no fog, no haze, no spotlight glow, no road, no floor, no ground "
    "reflections, low-key automotive photography, subtle rim lighting on "
    "body lines, dark alloy wheels, photorealistic, sharp focus"
)

NEGATIVE_PROMPT = (
    "text, watermark, logo overlay, people, driver, background objects, "
    "road, street, showroom floor, gradient background, vignette, frame, "
    "border, reflection on ground, shadow on floor, cartoon, illustration, "
    "painting, low quality, blurry, cropped car"
)


def build_prompt(car: str) -> str:
    return MASTER_PROMPT.format(car=car)


# ------------------------------------------------------------------ Кандинский

FB = "https://api-key.fusionbrain.ai/key/api/v1"


def _fb_request(path: str, data: bytes | None = None, headers: dict | None = None):
    request = urllib.request.Request(FB + path, data=data)
    key = os.environ.get("FUSIONBRAIN_KEY", "")
    secret = os.environ.get("FUSIONBRAIN_SECRET", "")
    request.add_header("X-Key", f"Key {key}")
    request.add_header("X-Secret", f"Secret {secret}")
    for name, value in (headers or {}).items():
        request.add_header(name, value)
    with urllib.request.urlopen(request, timeout=60) as reply:
        return json.loads(reply.read())


def generate_kandinsky(car: str) -> bytes:
    if not os.environ.get("FUSIONBRAIN_KEY"):
        raise SystemExit("Нужны ключи: env FUSIONBRAIN_KEY и FUSIONBRAIN_SECRET "
                         "(бесплатно на fusionbrain.ai после регистрации)")
    pipelines = _fb_request("/pipelines")
    pipeline_id = pipelines[0]["id"]

    params = {
        "type": "GENERATE",
        "numImages": 1,
        "width": 1024,
        "height": 1024,
        "negativePromptDecoder": NEGATIVE_PROMPT,
        "generateParams": {"query": build_prompt(car)},
    }
    boundary = "carimg"
    body = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="pipeline_id"\r\n\r\n'
        f"{pipeline_id}\r\n"
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="params"\r\n'
        "Content-Type: application/json\r\n\r\n"
        f"{json.dumps(params)}\r\n"
        f"--{boundary}--\r\n"
    ).encode()
    started = _fb_request("/pipeline/run", data=body, headers={
        "Content-Type": f"multipart/form-data; boundary={boundary}"})
    uuid = started["uuid"]

    for _ in range(60):
        time.sleep(5)
        status = _fb_request(f"/pipeline/status/{uuid}")
        if status.get("status") == "DONE":
            return base64.b64decode(status["result"]["files"][0])
        if status.get("status") == "FAIL":
            raise SystemExit(f"Кандинский отказал: {status}")
    raise SystemExit("Кандинский не ответил за 5 минут")


# ------------------------------------------------------------- Hugging Face

HF_MODEL = "stabilityai/stable-diffusion-3-medium-diffusers"


def generate_hf(car: str, seed: int) -> bytes:
    """Серверлесс-инференс Hugging Face (провайдер hf-inference). Кандинский
    там не развёрнут (веса без хостинга), зато SD3 принимает negative_prompt
    по-настоящему — Flux его игнорирует. Фон стабильно чёрный: обе тестовые
    генерации прошли валидатор краёв без ретраев."""
    token = os.environ.get("HF_TOKEN", "")
    if not token:
        raise SystemExit("Нужен env HF_TOKEN (huggingface.co → Settings → "
                         "Access Tokens; старый лежит в motion-studio/.env)")
    body = json.dumps({
        "inputs": build_prompt(car),
        "parameters": {"negative_prompt": NEGATIVE_PROMPT, "width": 1024,
                       "height": 1024, "seed": seed, "guidance_scale": 7.0},
    }).encode()
    request = urllib.request.Request(
        f"https://router.huggingface.co/hf-inference/models/{HF_MODEL}",
        data=body, headers={"Authorization": f"Bearer {token}",
                            "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=180) as reply:
        return reply.read()


# --------------------------------------------------------------- Pollinations

def generate_pollinations(car: str, seed: int) -> bytes:
    prompt = urllib.parse.quote(build_prompt(car))
    url = (f"https://image.pollinations.ai/prompt/{prompt}"
           f"?width=1024&height=1024&nologo=true&seed={seed}"
           f"&negative={urllib.parse.quote(NEGATIVE_PROMPT)}")
    request = urllib.request.Request(url, headers={
        # голый питоний UA сервис отбивает 403
        "User-Agent": "Mozilla/5.0 (Macintosh)"})
    with urllib.request.urlopen(request, timeout=300) as reply:
        return reply.read()


# ------------------------------------------------------------------- Валидатор

def finalize(path: str, flip: bool, floor: int) -> None:
    """Постобработка: зеркалирование (морда вправо — модель стабильно рисует
    влево) и прижатие почти-чёрного фона к нулю мягкой кривой уровней —
    белой машине порог в четверть сотни уровней не вредит, а фон становится
    бесшовным с чёрным экраном."""
    from PIL import Image, ImageOps
    image = Image.open(path).convert("RGB")
    if flip:
        image = ImageOps.mirror(image)
    if floor > 0:
        scale = 255.0 / (255 - floor)
        table = [max(0, round((v - floor) * scale)) for v in range(256)]
        image = image.point(table * 3)
    image.save(path)


def recompose(path: str, size: int = 1024, margin: float = 0.08,
              threshold: int = 14) -> None:
    """Кадрирует машину по её реальным границам и вписывает в квадрат с
    полями: масштаб выравнивается между генерациями, края гарантированно
    чёрные. Запускать после вырезания фона."""
    from PIL import Image
    im = Image.open(path).convert("RGB")
    box = im.convert("L").point(lambda v: 255 if v > threshold else 0).getbbox()
    if not box:
        return
    car = im.crop(box)
    inner = int(size * (1 - 2 * margin))
    scale = min(inner / car.width, inner / car.height)
    car = car.resize((max(1, int(car.width * scale)), max(1, int(car.height * scale))))
    out = Image.new("RGB", (size, size), (0, 0, 0))
    out.paste(car, ((size - car.width) // 2, (size - car.height) // 2))
    out.save(path)


def compose_hero(path: str, size: tuple[int, int] = (1536, 1024),
                 width_share: float = 0.86, bottom: float = 0.81,
                 glow: float = 0.09, blur: int = 40) -> None:
    """Собирает кадр в формате ассета главной (`CarPhoto`, 3:2): машина 86%
    ширины, низ на 0.81 высоты, вокруг корпуса мягкий ореол — размытая копия
    силуэта (на ассете его пик ~17-20 в 25-40 px от борта, к краям ноль).
    Без ореола вырезанная машина на чёрном теряет глубину и «висит».
    Запускать после вырезания фона."""
    from PIL import Image, ImageChops, ImageFilter
    im = Image.open(path).convert("RGB")
    box = im.convert("L").point(lambda v: 255 if v > 14 else 0).getbbox()
    if not box:
        return
    car = im.crop(box)

    canvas_w, canvas_h = size
    scale = min(canvas_w * width_share / car.width,
                canvas_h * 0.78 / car.height)
    car = car.resize((max(1, round(car.width * scale)),
                      max(1, round(car.height * scale))))
    x = (canvas_w - car.width) // 2
    y = round(canvas_h * bottom) - car.height

    layer = Image.new("RGB", size, (0, 0, 0))
    layer.paste(car, (x, y))
    halo = layer.convert("L").point(lambda v: 255 if v > 10 else 0)
    halo = halo.filter(ImageFilter.GaussianBlur(blur))
    halo = halo.point(lambda v: round(v * glow))
    out = ImageChops.lighter(layer, Image.merge("RGB", (halo, halo, halo)))
    out.save(path)


def edges_are_black(png_path: str, threshold: int = 26) -> tuple[bool, int]:
    """Периметр кадра обязан быть чёрным — это условие бесшовности на чёрном
    экране. Возвращает (прошёл ли, максимальную яркость на периметре)."""
    from PIL import Image
    image = Image.open(png_path).convert("RGB")
    w, h = image.size
    peak = 0
    for x in range(0, w, 8):
        for y in (0, 1, h - 2, h - 1):
            peak = max(peak, sum(image.getpixel((x, y))) // 3)
    for y in range(0, h, 8):
        for x in (0, 1, w - 2, w - 1):
            peak = max(peak, sum(image.getpixel((x, y))) // 3)
    return peak <= threshold, peak


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--car", required=True, help="например: 2016 Lexus RX 350")
    ap.add_argument("--provider", choices=["kandinsky", "hf", "pollinations"],
                    default="kandinsky")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--flip", action="store_true",
                    help="отзеркалить по горизонтали (морду вправо)")
    ap.add_argument("--floor", type=int, default=24,
                    help="порог прижатия фона к чёрному, 0 — выключить")
    args = ap.parse_args()

    if args.provider == "kandinsky":
        data = generate_kandinsky(args.car)
    elif args.provider == "hf":
        data = generate_hf(args.car, args.seed)
    else:
        data = generate_pollinations(args.car, args.seed)
    with open(args.out, "wb") as f:
        f.write(data)

    finalize(args.out, flip=args.flip, floor=args.floor)

    ok, peak = edges_are_black(args.out)
    verdict = "ок" if ok else f"НЕ ЧЁРНЫЕ (пик {peak}/255) — нужен ретрай"
    print(f"{args.car} → {args.out} | края: {verdict}")


if __name__ == "__main__":
    main()
