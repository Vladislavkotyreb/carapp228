#!/usr/bin/env python3
"""Догенерация каталога машин через OpenRouter, с оглядкой на деньги.

Зачем ещё один генератор. `catalog_batch.py` гоняет Кандинского локально
на MPS — бесплатно, но час на машину и только на маке с этой моделью.
Здесь платный хостинг: минуты вместо часов, зато каждый кадр стоит денег,
поэтому бюджет задаётся в долларах и проверяется по тому, что сказал сам
OpenRouter, а не по нашей оценке цены.

**Мастер-промпт не переписывается.** `MASTER_PROMPT`, `NEGATIVE_PROMPT` и
проверка чёрных краёв берутся импортом из `car_image_gen.py` — того же
файла, которым сделаны 76 кадров в проде. Новый кадр обязан попасть в тот
же стиль, иначе карусель на главной поедет: часть машин в одном свете,
часть в другом.

**Плюс кадр из прода как образец.** Модель получает вместе с промптом
готовый ассет той же кузовной формы (`AppMVP/Resources/CarCatalog/*.heic`)
и просьбу держать тот же свет, фон и ракурс. Это и есть разница с
текстовой генерацией: стиль не описывается словами заново, а показывается.

Что делает прогон:

1. Спрашивает у OpenRouter остаток на ключе.
2. Идёт по списку машин сверху вниз, пропуская уже готовые файлы.
3. На каждую — до `--attempts` попыток; кадр с нечёрным периметром
   бракуется (`edges_are_black`), из попыток остаётся лучшая по пику
   яркости краёв.
4. Постобработка та же, что у прода: прижатие фона к нулю (`finalize`)
   и сборка кадра 3:2 с единой синтетической землёй (`compose_hero`) —
   те самые 86 % ширины и низ на 0.81, под которые сверяли масштаб.

   **Оговорка.** В исходном конвейере между ними стоял Vision cutout
   (вырезка машины средствами macOS), и журнал за 07.09 прямо говорит,
   что без него кадр иногда собирался неверно. Скрипта вырезки в
   репозитории нет — он жил во временном каталоге сессии. Здесь его
   место занимает `finalize`: фон от Nano Banana с образцом и так почти
   чёрный. Прошло это или нет, видно только глазами — поэтому сначала
   `--limit 2`, сверка с любым кадром из прода, и лишь потом весь бюджет.
5. После каждого ответа складывает фактическую стоимость. Кончился
   бюджет — останавливается и печатает, докуда дошёл.

Ключ — в переменной окружения, не в файле: репозиторий публичный.

    export OPENROUTER_API_KEY=...
    python3 tools/catalog_openrouter.py --budget 4.00

Проверить, как называется модель на сегодня (имена там меняются):

    python3 tools/catalog_openrouter.py --list-models

Сухой прогон без единого запроса к платному API:

    python3 tools/catalog_openrouter.py --dry-run

Что дальше, когда кадры устроят. Картинка сама по себе в приложении не
появится — нужны два шага руками:

1. В каталог проекта, тем же `sips`, что и остальные 76:

       sips -s format heic -s formatOptions 80 ~/canary-catalog/raw/<slug>.png \
            --out AppMVP/Resources/CarCatalog/<slug>.heic

   Папка подключена одной folder reference, так что в `project.pbxproj`
   лезть не надо — файл просто оказывается в бандле.

2. Правило подбора в `AppMVP/Core/Pure/CarCatalog.swift`: без него слаг
   не найдётся ни по какому названию, и кадр останется мёртвым грузом.
   Там же рядом — проверки в `tools/pure-checks/main.swift`.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from car_image_gen import build_prompt, compose_hero, edges_are_black, finalize

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
CARS_NEXT = os.path.join(HERE, "catalog_cars_next.json")
CARS_DONE = os.path.join(HERE, "catalog_cars.json")
ASSETS = os.path.join(REPO, "AppMVP", "Resources", "CarCatalog")
RAW = os.path.expanduser("~/canary-catalog/raw")
API = "https://openrouter.ai/api/v1"

# Nano Banana — ею сделан эталонный ассет, под неё подгонялась пятая
# итерация мастер-промпта (см. комментарий в car_image_gen.py). Имена
# моделей на OpenRouter меняются: не нашлась — `--list-models` покажет,
# что там сейчас с картинками на выходе.
MODEL = "google/gemini-2.5-flash-image"

# Что просим сделать с образцом. Стиль показывается картинкой, а не
# описывается словами заново: слова уже сказаны в мастер-промпте.
REFERENCE_NOTE = (
    "The attached image is the reference for style, not for the car model. "
    "Match its lighting, black background, camera angle and framing exactly. "
    "Draw a different car: "
)


def log(message: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {message}", flush=True)


# --------------------------------------------------------------- сеть

def request(path: str, payload: dict | None = None, key: str = "",
            timeout: int = 300) -> dict:
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data)
    req.add_header("Authorization", f"Bearer {key}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as reply:
            return json.loads(reply.read())
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")[:500]
        raise SystemExit(f"OpenRouter ответил {error.code}: {body}")


def credits(key: str) -> tuple[float, float | None]:
    """(потрачено, лимит) по ключу. Лимит None — ключ без потолка."""
    data = request("/key", key=key).get("data", {})
    return float(data.get("usage") or 0), data.get("limit")


def list_models(key: str) -> None:
    for model in request("/models", key=key).get("data", []):
        modality = (model.get("architecture") or {}).get("output_modalities") or []
        if "image" in modality:
            price = (model.get("pricing") or {}).get("image", "?")
            print(f"{model['id']}\n    картинка: {price} $/шт")


# ------------------------------------------------------------- образец

def body_of(prompt: str) -> str:
    """Кузов из строки промпта: по нему подбирается образец."""
    for body in ("station wagon", "offroad SUV", "SUV", "crossover",
                 "liftback", "hatchback", "sedan"):
        if body.lower() in prompt.lower():
            return body
    return "sedan"


def reference_png(slug: str) -> bytes | None:
    """PNG готового ассета. Сначала исходник генерации, если он ещё лежит
    на этой машине; иначе HEIC из проекта — через `sips` (есть в любой
    macOS, ставить нечего) или через `pillow-heif`, если он поставлен.
    Два пути, потому что скрипт полезно гонять и не на маке."""
    raw = os.path.join(RAW, slug + ".png")
    if os.path.exists(raw):
        return open(raw, "rb").read()
    heic = os.path.join(ASSETS, slug + ".heic")
    if not os.path.exists(heic):
        return None
    out = os.path.join("/tmp", f"canary-ref-{slug}.png")
    try:
        subprocess.run(["sips", "-s", "format", "png", heic, "--out", out],
                       check=True, capture_output=True)
        return open(out, "rb").read()
    except (OSError, subprocess.CalledProcessError):
        pass
    try:
        import pillow_heif
        from PIL import Image
        pillow_heif.register_heif_opener()
        Image.open(heic).convert("RGB").save(out)
        return open(out, "rb").read()
    except Exception:
        return None


def pick_reference(slug: str, prompt: str) -> tuple[str, bytes] | None:
    """Готовая машина в образец. Порядок предпочтений:

    1. Та же марка и тот же кузов — лучший случай: для «mercedes-e-w211»
       образцом станет «mercedes-e-w212», то есть та же машина поколением
       позже. Меньше всего шансов, что от образца утекут пропорции.
    2. Тот же кузов у любой марки — стиль везде один, свет и фон возьмутся
       правильно.
    3. Хоть что-нибудь — лучше чужой кузов, чем генерация без образца.
    """
    want = body_of(prompt)
    brand = slug.split("-", 1)[0]
    done = json.load(open(CARS_DONE))
    same_body = [c for c in done if body_of(c["prompt"]) == want]
    order = ([c for c in same_body if c["slug"].split("-", 1)[0] == brand]
             + same_body + done)
    seen: set[str] = set()
    for car in order:
        if car["slug"] in seen:
            continue
        seen.add(car["slug"])
        png = reference_png(car["slug"])
        if png:
            return car["slug"], png
    return None


# ---------------------------------------------------------- генерация

def generate(car: dict, key: str, model: str,
             reference: tuple[str, bytes] | None) -> tuple[bytes, float]:
    """Один кадр и его цена по версии самого OpenRouter."""
    text = build_prompt(car["prompt"])
    content: list[dict] = []
    if reference:
        _, png = reference
        text = REFERENCE_NOTE + text
        content.append({"type": "image_url", "image_url": {
            "url": "data:image/png;base64," + base64.b64encode(png).decode()}})
    content.insert(0, {"type": "text", "text": text})

    answer = request("/chat/completions", {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "modalities": ["image", "text"],
        "usage": {"include": True},
    }, key=key)

    cost = float((answer.get("usage") or {}).get("cost") or 0)
    images = ((answer.get("choices") or [{}])[0].get("message") or {}).get("images") or []
    if not images:
        dump = os.path.join("/tmp", f"canary-openrouter-{car['slug']}.json")
        with open(dump, "w", encoding="utf-8") as f:
            json.dump(answer, f, ensure_ascii=False, indent=2)
        raise SystemExit(
            "В ответе нет картинки — возможно, модель не умеет их отдавать "
            f"или поменялся формат. Ответ целиком: {dump}\n"
            "Посмотреть, что сейчас умеет отдавать картинки: --list-models")
    url = images[0].get("image_url", {}).get("url", "")
    return base64.b64decode(url.split(",", 1)[1]), cost


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--budget", type=float, default=4.0,
                    help="потолок трат в долларах за этот прогон")
    ap.add_argument("--model", default=MODEL)
    ap.add_argument("--cars", default=CARS_NEXT)
    ap.add_argument("--out", default=RAW)
    ap.add_argument("--attempts", type=int, default=2,
                    help="попыток на машину, пока края не станут чёрными")
    ap.add_argument("--floor", type=int, default=24,
                    help="порог прижатия фона к чёрному, 0 — выключить")
    ap.add_argument("--no-reference", action="store_true",
                    help="без образца из прода, только мастер-промпт")
    ap.add_argument("--reference", default="",
                    help="слаг из прода как образец для всех машин прогона")
    ap.add_argument("--raw", action="store_true",
                    help="без сборки кадра 3:2 — только сырой квадрат")
    ap.add_argument("--limit", type=int, default=0,
                    help="взять не больше N машин: пробный прогон на пару"
                         " кадров перед тем, как тратить весь бюджет")
    ap.add_argument("--list-models", action="store_true")
    ap.add_argument("--dry-run", action="store_true",
                    help="показать план, не тратя ни цента")
    args = ap.parse_args()

    if args.reference:
        forced = reference_png(args.reference)
        if not forced:
            raise SystemExit(f"Нет ассета для образца: {args.reference}")

    # Pillow нужен постобработке, но зовётся она уже после генерации —
    # то есть после того, как деньги списаны. Поэтому проверка здесь,
    # до первого запроса: упасть на импорте с полным кошельком дешевле,
    # чем с пустым.
    try:
        import PIL  # noqa: F401
    except ImportError:
        raise SystemExit(
            "Нет Pillow, а без него не соберётся ни один кадр.\n"
            "    python3 -m pip install --user pillow\n"
            "Если генерация каталога уже стояла в венве, проще им же:\n"
            "    ~/Library/Caches/kandinsky5-venv/bin/python "
            "tools/catalog_openrouter.py ...")

    key = os.environ.get("OPENROUTER_API_KEY", "")
    if not key and not args.dry_run:
        raise SystemExit("Нет OPENROUTER_API_KEY в окружении.")
    if key and not key.startswith("sk-or-"):
        raise SystemExit(
            "OPENROUTER_API_KEY не похож на ключ OpenRouter: они начинаются\n"
            "с «sk-or-v1-». Скопируйте ключ целиком со страницы ключей."
            )

    if args.list_models:
        list_models(key)
        return 0

    os.makedirs(args.out, exist_ok=True)
    cars = json.load(open(args.cars))
    todo = [c for c in cars
            if not os.path.exists(os.path.join(args.out, c["slug"] + ".png"))]
    if args.limit:
        todo = todo[:args.limit]
    log(f"список: {len(cars)}, к генерации: {len(todo)}, бюджет: ${args.budget:.2f}")

    if args.dry_run:
        for car in todo:
            reference = None if args.no_reference else (
                (args.reference, b"") if args.reference
                else pick_reference(car["slug"], car["prompt"]))
            mark = reference[0] if reference else "образца нет"
            print(f"  {car['slug']:<26} {car['prompt']:<44} ← {mark}")
        return 0

    used, limit = credits(key)
    if limit is not None:
        left = limit - used
        log(f"на ключе осталось ${left:.2f}")
        if left < args.budget:
            args.budget = max(0.0, left - 0.05)   # пятак на округления
            log(f"бюджет урезан до остатка: ${args.budget:.2f}")

    spent, made, failed, prices = 0.0, [], [], []

    def affordable() -> bool:
        """Хватит ли на ещё один кадр. Сравнивать `spent < budget` мало:
        при остатке в цент прогон всё равно шёл бы за кадром и вылезал за
        бюджет на его полную цену. Цену берём по факту предыдущих, до
        первого ответа — уступаем, иначе прогон не начнётся вовсе."""
        next_cost = max(prices) if prices else 0.0
        return spent + next_cost <= args.budget

    for car in todo:
        if not affordable():
            log(f"бюджет исчерпан — осталось несделанных: "
                f"{len(todo) - len(made) - len(failed)}")
            break
        reference = None if args.no_reference else (
            (args.reference, forced) if args.reference
            else pick_reference(car["slug"], car["prompt"]))
        dest = os.path.join(args.out, car["slug"] + ".png")
        best: tuple[int, bytes] | None = None

        for attempt in range(1, args.attempts + 1):
            if attempt > 1 and not affordable():
                break
            png, cost = generate(car, key, args.model, reference)
            spent += cost
            prices.append(cost)
            tmp = dest + f".try{attempt}"
            open(tmp, "wb").write(png)
            ok, peak = edges_are_black(tmp)
            os.remove(tmp)
            if best is None or peak < best[0]:
                best = (peak, png)
            log(f"{car['slug']}: попытка {attempt}, края {peak}, "
                f"{'ок' if ok else 'светлые'}, ${cost:.4f} (всего ${spent:.4f})")
            if ok:
                break

        if best is None:
            failed.append(car["slug"])
            continue
        open(dest, "wb").write(best[1])
        # Зеркалить не нужно: направление морды задаёт образец, а не текст.
        finalize(dest, flip=False, floor=args.floor)
        if not args.raw:
            compose_hero(dest)
        ok, peak = edges_are_black(dest)
        (made if ok else failed).append(car["slug"])
        log(f"{car['slug']}: готово, края после обработки {peak}"
            + ("" if ok else " — светлые, проверить глазами"))

    log(f"сделано: {len(made)}, брак: {len(failed)}, потрачено ${spent:.4f}")
    if failed:
        log("проверить глазами: " + ", ".join(failed))
    log(f"кадры: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
