#!/usr/bin/env python3
"""Догенерация каталога машин через OpenRouter, с оглядкой на деньги.

Зачем ещё один генератор. `catalog_batch.py` гоняет Кандинского локально
на MPS — бесплатно, но час на машину и только на маке с этой моделью.
Здесь платный хостинг: минуты вместо часов, зато каждый кадр стоит денег,
поэтому бюджет задаётся в долларах и проверяется по тому, что сказал сам
OpenRouter, а не по нашей оценке цены.

**Два рецепта, и по умолчанию — тот, которым сделан прод.**

`--recipe v3` (по умолчанию) — так сделаны все 75 кадров в приложении
(журнал 2026-09-06 «каталог v3, финальный», коммит `47c85a0`):
`google/gemini-3.1-flash-image`, референс — Lexus RX на чёрном, промпт
«Recreate the reference EXACTLY… only the car itself changes», кадр как
есть: ни вырезки, ни синтетического пола. Тень и отражение под машиной
рисует сама модель, поэтому они и похожи на прод.

`--recipe batch2` — то, что ниже описано про образец `CarPhoto`,
`MASTER_PROMPT` и `compose_hero`. Им сделаны 12 кадров партии 2
(2026-09-15), и они заметно другие: камера ниже, машина мельче, пол
плоский. Причина в образце: `CarPhoto` с 2026-09-07 — машина под
покрывалом, а не RX. Рецепт оставлен для пересборки сырья партии 2.

**Мастер-промпт не переписывается.** `MASTER_PROMPT`, `NEGATIVE_PROMPT` и
проверка чёрных краёв берутся импортом из `car_image_gen.py` — того же
файла, которым сделаны 76 кадров в проде. Новый кадр обязан попасть в тот
же стиль, иначе карусель на главной поедет: часть машин в одном свете,
часть в другом.

**batch2: образец — ассет главной `CarPhoto`, один на все машины.** Так
сделаны 64 кадра v2 (журнал 2026-09-06), которые v3 в тот же вечер
заменил целиком; с 2026-09-07 `CarPhoto` — машина под покрывалом, и
стиль с неё переносится уже не тот. Первая партия 2026-09-15 шла с образцом «та же марка и кузов»
(`--reference-by-brand`) и получила под именем Camry XV40 семидесятую,
под Pajero — УАЗ, под Outback — Весту SW: чем ближе образец, тем
увереннее модель его перерисовывает. Флаг оставлен как памятник.

Что делает прогон:

1. Спрашивает у OpenRouter остаток на ключе.
2. Идёт по списку машин сверху вниз, пропуская уже готовые файлы.
3. На каждую — до `--attempts` попыток; кадр с нечёрным периметром
   бракуется (`edges_are_black`), из попыток остаётся лучшая по пику
   яркости краёв.
4. Сырьё сохраняется как `<slug>.raw.png`. У v3 кадр дальше только
   обрезается в 1264×841. У batch2 — сборка: машина вырезается Vision (`tools/cutout.swift`, бинарник собирается
   сам при первом запуске), `compose_hero` кладёт под неё единый пол и
   тень, 1264×841. Вырезка не украшение: без неё отражение из сырья
   считается машиной и ложится чёрной полосой поверх синтетического
   пола — колёса тонут. Так вышла вся первая партия 2026-09-15, и её
   можно пересобрать бесплатно: `--recompose`.
5. После каждого ответа складывает фактическую стоимость. Кончился
   бюджет — останавливается и печатает, докуда дошёл.

Ключ — в переменной окружения, не в файле: репозиторий публичный.

    export OPENROUTER_API_KEY=...
    python3 tools/catalog_openrouter.py --dry-run          # план и промпт
    python3 tools/catalog_openrouter.py --limit 2          # два кадра, глазами
    python3 tools/catalog_openrouter.py --budget 4.60      # остальные

Кадры v3 ложатся в `~/beepy-catalog/v3` (`<slug>.raw.png` — ответ модели,
`<slug>.png` — он же в 1264×841). Морда влево — бесплатно:
`--recompose --flip --only a,b`.

Проверить, как называется модель на сегодня (имена там меняются):

    python3 tools/catalog_openrouter.py --list-models

Сухой прогон без единого запроса к платному API:

    python3 tools/catalog_openrouter.py --dry-run

Что дальше, когда кадры устроят. Картинка сама по себе в приложении не
появится — нужны два шага руками:

1. В каталог проекта, тем же `sips`, что и остальные 76:

       sips -s format heic -s formatOptions 80 ~/beepy-catalog/raw/<slug>.png \
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
# Рабочая папка кадров. Приложение переименовано в Beepy 2026-09-22, но
# сырьё партии 2 уже лежит в `~/canary-catalog` — молча «не найти» его
# значило бы потерять кадры, за которые заплачено. Поэтому новая папка,
# а если её ещё нет и есть старая, берётся старая.
def _catalog_home() -> str:
    new = os.path.expanduser("~/beepy-catalog")
    old = os.path.expanduser("~/canary-catalog")
    return old if not os.path.isdir(new) and os.path.isdir(old) else new


CATALOG_HOME = _catalog_home()
RAW = os.path.join(CATALOG_HOME, "raw")
API = "https://openrouter.ai/api/v1"
CUTOUT_SRC = os.path.join(HERE, "cutout.swift")
CUTOUT_BIN = os.path.join(CATALOG_HOME, "cutout")
# Образец по умолчанию — ассет главной. Им же, одним на всех, сделаны
# 64 банановых кадра прода (журнал 2026-09-06): стиль переносится, а
# машина в нём чужая для любого слага, копировать нечего.
HERO = os.path.join(REPO, "AppMVP", "Resources", "Assets.xcassets",
                    "CarPhoto.imageset", "car.png")

# Nano Banana — ею сделан эталонный ассет, под неё подгонялась пятая
# итерация мастер-промпта (см. комментарий в car_image_gen.py). Имена
# моделей на OpenRouter меняются: не нашлась — `--list-models` покажет,
# что там сейчас с картинками на выходе.
MODEL = "google/gemini-2.5-flash-image"

# ------------------------------------------------------ рецепт прода, v3
#
# Записан по журналу 2026-09-06 («каталог v3, финальный»): сам батч
# `or_batch.py` жил в скретчпаде той сессии и в репозиторий не попал.
# Модель и референс названы в журнале прямо. Промпт — нет: в журнале
# только «Recreate the reference EXACTLY… only the car itself changes»,
# многоточие — его. PROD_PROMPT ниже держит обе фразы дословно, а
# середина восстановлена; найдётся оригинал — заменить целиком.
# Транскрипт той сессии лежит на маке, оригинал достаётся так:
#
# (grep на маке не берёт повтор длиннее 255, поэтому perl):
#
#   grep -rl --null 'Recreate the reference' ~/.claude/projects | xargs -0 perl -ne 'print "$1\n" while /(Recreate the reference.{0,1500})/g' | sort -u
PROD_MODEL = "google/gemini-3.1-flash-image"
PROD_PROMPT = (
    "Recreate the reference EXACTLY: the same camera angle and height, the "
    "same framing and size of the car in the frame, the same black "
    "background, the same lighting, the same glossy white paint, the same "
    "shadow and reflection under the car. Only the car itself changes: {car}."
)
# Референс v3 — «канонический ~/beepy-catalog/reference.png (RX 1251×832
# из экспорта пользователя)». Он есть только на маке; где его нет, берётся
# кадр `lexus-rx` из каталога — это RX, перерисованный тем же рецептом.
PROD_REFERENCE_FILES = ("~/beepy-catalog/reference.png",
                        "~/canary-catalog/reference.png")
PROD_REFERENCE_SLUG = "lexus-rx"
# Все 75 кадров v3 — 1264×841, как ассет главной. Модель отдаёт 3:2 шире
# на несколько строк; лишнее срезается поровну сверху и снизу.
PROD_SIZE = (1264, 841)
# Цена кадра v3 по факту: $5.09 за 75 кадров (журнал 2026-09-06).
PROD_PRICE = 0.068
# Кадры v3 — в своей папке. В `raw` на маке лежат старые PNG первой
# партии (чужие машины): по ним прогон счёл бы машину готовой и пропустил.
PROD_OUT = os.path.join(CATALOG_HOME, "v3")

# Что просим сделать с образцом. Стиль показывается картинкой, а не
# описывается словами заново: слова уже сказаны в мастер-промпте.
# Про ориентацию отдельно: в партии 2 половина машин вышла мордой влево
# при образце мордой вправо. Просьба текстом помогает не всегда — потому
# в порядке работы стоит проверка по листу и бесплатное зеркало
# (`--recompose --flip --only …`): сырьё лежит рядом.
REFERENCE_NOTE = (
    "The attached image is the reference for style, not for the car model. "
    "Match its lighting, black background, camera angle and framing exactly, "
    "including orientation: the front of the car points to the right side "
    "of the frame, exactly like in the reference. Draw a different car: "
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


class Disconnected(Exception):
    """Ответ не дошёл. Генерация на сервере могла пройти и списаться."""


def post_curl(path: str, payload: dict, key: str, timeout: int = 900) -> dict:
    """POST за картинкой — curl'ом, не urllib. Журнал 2026-09-07: на
    длинных ответах urllib дважды падал (timeout, RemoteDisconnected),
    а генерация на сервере проходила и списывалась; curl дотягивал.
    Повторов здесь нет намеренно: повтор после обрыва — второй платный
    кадр. Ключ уходит заголовком через stdin, не аргументом: аргументы
    видны любому в `ps`."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        body = os.path.join(tmp, "body.json")
        out = os.path.join(tmp, "out.json")
        with open(body, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        result = subprocess.run(
            ["curl", "-sS", "--max-time", str(timeout), "-o", out,
             "-w", "%{http_code}", "-H", "@-",
             "-H", "Content-Type: application/json",
             "--data-binary", "@" + body, API + path],
            input=f"Authorization: Bearer {key}\n",
            capture_output=True, text=True)
        if result.returncode != 0:
            raise Disconnected(result.stderr.strip()[-300:])
        code = result.stdout.strip()
        text = open(out, encoding="utf-8", errors="replace").read() \
            if os.path.exists(out) else ""
        if code != "200":
            raise SystemExit(f"OpenRouter ответил {code}: {text[:500]}")
        return json.loads(text)


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
    out = os.path.join("/tmp", f"beepy-ref-{slug}.png")
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


# ------------------------------------------------------- сборка кадра

def cutout_binary(explicit: str = "") -> str | None:
    """Путь к бинарнику вырезки. Нет — собрать из `cutout.swift`, если есть
    `swiftc`; иначе None, и сборка кадра пойдёт без вырезки (с чёрной
    полосой под колёсами — см. `assemble`)."""
    path = explicit or CUTOUT_BIN
    if os.path.exists(path):
        return path
    try:
        subprocess.run(["swiftc", "-O", CUTOUT_SRC, "-o", path],
                       check=True, capture_output=True, text=True)
        log(f"вырезка собрана: {path}")
        return path
    except FileNotFoundError:
        return None
    except subprocess.CalledProcessError as error:
        log("вырезка не собралась:\n" + (error.stderr or "")[-800:])
        return None


def prod_reference() -> tuple[str, bytes]:
    """Референс v3: исходный RX с мака, иначе `lexus-rx` из каталога."""
    for candidate in PROD_REFERENCE_FILES:
        path = os.path.expanduser(candidate)
        if os.path.exists(path):
            return path, open(path, "rb").read()
    png = reference_png(PROD_REFERENCE_SLUG)
    if not png:
        raise SystemExit(
            "Нет референса v3: ни ~/beepy-catalog/reference.png, ни "
            f"{PROD_REFERENCE_SLUG}.heic в PNG (нужен sips или pillow-heif).")
    return PROD_REFERENCE_SLUG + ".heic", png


def fit_prod(source: str, dest: str, flip: bool) -> tuple[int, int]:
    """Кадр v3 как есть, только в размер прода 1264×841: масштаб, если
    модель отдала другой, и обрезка лишних строк поровну. Возвращает
    размер, который отдала модель, — не 3:2 значит, что кадр обрезан
    заметно и смотреть его надо глазами."""
    from PIL import Image, ImageOps
    image = Image.open(source).convert("RGB")
    given = image.size
    if flip:
        image = ImageOps.mirror(image)
    width, height = PROD_SIZE
    scale = max(width / image.width, height / image.height)
    if abs(scale - 1) > 1e-9:
        image = image.resize((max(width, round(image.width * scale)),
                              max(height, round(image.height * scale))),
                             Image.LANCZOS)
    left = (image.width - width) // 2
    top = (image.height - height) // 2
    image.crop((left, top, left + width, top + height)).save(dest)
    return given


def assemble(slug: str, source: str, dest: str, cutout: str | None,
             flip: bool, floor: int, reflection: float = 0.0,
             contact: float = 0.08, shadow: int = 45) -> None:
    """Сырой кадр → кадр каталога, как у 76 в проде: вырезка машины →
    `compose_hero` с единым полом и тенью, 1264×841.

    Вырезка обязательна по смыслу, а не для красоты. В сырье под машиной
    её собственное отражение; без вырезки оно попадает в «машину», после
    прижатия к чёрному становится чёрной полосой и ложится поверх
    синтетического пола — колёса тонут. Первая партия 2026-09-15 вся
    такая. Нет бинарника — идём прежним путём и честно пишем об этом."""
    work = dest + ".work.png"
    from PIL import Image
    Image.open(source).convert("RGB").save(work)
    # Зеркало — до вырезки, чтобы маска считалась с итогового кадра.
    if flip:
        finalize(work, flip=True, floor=0)
    if cutout:
        result = subprocess.run([cutout, work, work], capture_output=True, text=True)
        if result.returncode != 0:
            log(f"{slug}: вырезка не удалась — {result.stdout.strip()[-200:]}")
            finalize(work, flip=False, floor=floor)
    else:
        finalize(work, flip=False, floor=floor)
    # Размер как у 76 кадров прода (1264×841, те же 3:2), а не 1536×1024
    # по умолчанию: первая партия ушла крупнее без пользы для экрана.
    compose_hero(work, size=(1264, 841), reflection=reflection,
                 contact=contact, shadow_fill=shadow)
    os.replace(work, dest)


# ---------------------------------------------------------- генерация

def prompt_for(car: dict, recipe: str, reference: tuple[str, bytes] | None) -> str:
    """Текст запроса ровно в том виде, в каком он уйдёт в модель."""
    if recipe == "v3":
        return PROD_PROMPT.format(car=car["prompt"])
    text = build_prompt(car["prompt"])
    return REFERENCE_NOTE + text if reference else text


def generate(car: dict, key: str, model: str,
             reference: tuple[str, bytes] | None,
             recipe: str = "batch2") -> tuple[bytes, float]:
    """Один кадр и его цена по версии самого OpenRouter."""
    content: list[dict] = [{"type": "text", "text": prompt_for(car, recipe, reference)}]
    if reference:
        _, png = reference
        content.append({"type": "image_url", "image_url": {
            "url": "data:image/png;base64," + base64.b64encode(png).decode()}})

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "modalities": ["image", "text"],
        "usage": {"include": True},
    }
    if recipe == "v3":
        # Кадры v3 шириной 1264, как у 3:2 на выходе модели; квадрат
        # пришлось бы обрезать до половины машины.
        payload["image_config"] = {"aspect_ratio": "3:2"}
    answer = post_curl("/chat/completions", payload, key=key)

    cost = float((answer.get("usage") or {}).get("cost") or 0)
    images = ((answer.get("choices") or [{}])[0].get("message") or {}).get("images") or []
    if not images:
        dump = os.path.join("/tmp", f"beepy-openrouter-{car['slug']}.json")
        with open(dump, "w", encoding="utf-8") as f:
            json.dump(answer, f, ensure_ascii=False, indent=2)
        raise SystemExit(
            "В ответе нет картинки — возможно, модель не умеет их отдавать "
            f"или поменялся формат. Ответ целиком: {dump}\n"
            "Посмотреть, что сейчас умеет отдавать картинки: --list-models")
    url = images[0].get("image_url", {}).get("url", "")
    return base64.b64decode(url.split(",", 1)[1]), cost


def recompose(args, cutout: str | None) -> int:
    """Пересобрать кадры из сырья `<slug>.raw.png`, без единого запроса.
    Кадры без сырья пропускаются и не трогаются."""
    cars = json.load(open(args.cars))
    if args.only:
        wanted = {s.strip() for s in args.only.split(",") if s.strip()}
        cars = [c for c in cars if c["slug"] in wanted]
    if args.limit:
        cars = cars[:args.limit]
    done, skipped = [], []
    for car in cars:
        dest = os.path.join(args.out, car["slug"] + ".png")
        raw_path = os.path.join(args.out, car["slug"] + ".raw.png")
        # Только настоящее сырьё. Раньше при его отсутствии брался готовый
        # `<slug>.png` — и 2026-09-17 `--recompose` без `--only` молча
        # пересобрал 53 кадра первой партии (чужие машины, срезанные шины)
        # из их старых сборок, а импорт вернул их в репозиторий. Кадр без
        # `.raw.png` пересобирать не из чего: только генерировать заново.
        source = raw_path
        if not os.path.exists(source):
            skipped.append(car["slug"]); continue
        if args.recipe == "v3":
            fit_prod(source, dest, args.flip)
        else:
            assemble(car["slug"], source, dest, cutout, args.flip, args.floor,
                     args.reflection, args.contact, args.shadow)
        ok, peak = edges_are_black(dest)
        done.append(car["slug"])
        log(f"{car['slug']}: пересобран, края {peak}" + ("" if ok else " — светлые"))
    log(f"пересобрано: {len(done)}, без сырья (не тронуты): {len(skipped)}")
    if skipped:
        log("  " + ", ".join(skipped))
        log("  у этих нет <slug>.raw.png — их можно только сгенерировать заново")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--budget", type=float, default=4.0,
                    help="потолок трат в долларах за этот прогон")
    ap.add_argument("--recipe", choices=("v3", "batch2"), default="v3",
                    help="v3 — как 75 кадров прода (по умолчанию); batch2 — "
                         "CarPhoto + MASTER_PROMPT + compose_hero, как партия 2")
    ap.add_argument("--model", default=None,
                    help=f"по умолчанию {PROD_MODEL} для v3, {MODEL} для batch2")
    ap.add_argument("--cars", default=CARS_NEXT)
    ap.add_argument("--out", default=None,
                    help=f"по умолчанию {PROD_OUT} для v3, {RAW} для batch2")
    # У v3 одна попытка: кадр со светлыми краями (белый фон, как было
    # с renault-kaptur) уходит в список «проверить глазами», и решение о
    # повторе за деньги принимает человек по листу, а не скрипт.
    ap.add_argument("--attempts", type=int, default=None,
                    help="попыток на машину, пока края не станут чёрными; "
                         "по умолчанию 1 для v3, 2 для batch2")
    # Ноль, и это не мелочь. Прижатие к чёрному съедает у банановых
    # кадров низ шин и отражение под машиной (яркость 8-17) — первая партия
    # 2026-09-15 вся с плоско срезанными колёсами над чёрной полосой.
    # Журнал 2026-09-06 про это уже писал: «floor для банана отключён».
    # Светлые края сырья (27-51) гасит виньетка в compose_hero, не floor.
    ap.add_argument("--floor", type=int, default=0,
                    help="порог прижатия фона к чёрному; по умолчанию 0 — "
                         "иначе пропадают шины и отражение")
    # Образец по умолчанию выключен. Первая партия (2026-09-15) показала:
    # Nano Banana берёт из приложенного кадра не свет и ракурс, а саму
    # машину — Camry XV40 вышла семидесятой, Pajero стал УАЗом, у половины
    # партии под чужим именем нарисован образец. Мастер-промпт стиль
    # держит и без картинки: под него и подгонялась пятая итерация.
    ap.add_argument("--no-reference", action="store_true",
                    help="без образца вовсе, только мастер-промпт")
    ap.add_argument("--reference-by-brand", action="store_true",
                    help="образец — кадр той же марки и кузова из прода "
                         "(так первая партия получила чужие машины)")
    ap.add_argument("--reference", default="",
                    help="слаг из прода как образец для всех машин прогона")
    ap.add_argument("--raw", action="store_true",
                    help="без сборки кадра 3:2 — только сырой квадрат")
    ap.add_argument("--only", default="",
                    help="слаги через запятую: перегенерить только их")
    ap.add_argument("--force", action="store_true",
                    help="перезаписать уже готовый PNG в raw")
    ap.add_argument("--flip", action="store_true",
                    help="отзеркалить: морда должна смотреть вправо, как в проде")
    ap.add_argument("--limit", type=int, default=0,
                    help="взять не больше N машин: пробный прогон на пару"
                         " кадров перед тем, как тратить весь бюджет")
    ap.add_argument("--list-models", action="store_true")
    ap.add_argument("--dry-run", action="store_true",
                    help="показать план, не тратя ни цента")
    ap.add_argument("--cutout", default="",
                    help=f"бинарник вырезки (по умолчанию {CUTOUT_BIN}, "
                         "собирается из tools/cutout.swift сам)")
    ap.add_argument("--no-cutout", action="store_true",
                    help="собрать без вырезки: под колёсами будет чёрная полоса")
    # Сборка откалибрована по эталону lexus-rx численно: вертикальный
    # профиль яркости под машиной у эталона [13,11,8,7,6,8,10,11,9,8,6,5,3,
    # 2,1,0] (шаг 10 px вниз от низа машины), и перебор glow × shadow ×
    # contact на трёх кадрах партии 2 ближе всего лёг при glow 0.20 (как у
    # прода), тени 45 вместо 110 и контактном свечении 0.08. Зеркальное
    # отражение (--reflection) к эталону не приближает: светит под
    # порогами, а эталон светит под колёсами. Выключено.
    ap.add_argument("--reflection", type=float, default=0.0,
                    help="зеркальное отражение под машиной, доля яркости "
                         "кузова; по умолчанию выключено")
    ap.add_argument("--contact", type=float, default=0.08,
                    help="контактное свечение под шинами, как у lexus-rx")
    ap.add_argument("--shadow", type=int, default=45,
                    help="сила тени под днищем (у прода из сырья ~110, "
                         "для синтетики 45 — иначе под машиной ноль)")
    ap.add_argument("--recompose", action="store_true",
                    help="без сети: пересобрать кадры из <slug>.raw.png "
                         "(v3 — обрезка в 1264×841 и --flip, batch2 — вырезка "
                         "и compose_hero)")
    args = ap.parse_args()

    v3 = args.recipe == "v3"
    args.model = args.model or (PROD_MODEL if v3 else MODEL)
    args.out = args.out or (PROD_OUT if v3 else RAW)
    if args.attempts is None:
        args.attempts = 1 if v3 else 2

    forced: tuple[str, bytes] | None = None
    if v3 and not args.reference and not args.no_reference:
        forced = prod_reference()
    elif args.reference:
        png = reference_png(args.reference)
        if not png:
            raise SystemExit(f"Нет ассета для образца: {args.reference}")
        forced = (args.reference, png)
    elif not args.no_reference and not args.reference_by_brand:
        if not os.path.exists(HERO):
            raise SystemExit(f"Нет ассета главной для образца: {HERO}")
        forced = ("CarPhoto", open(HERO, "rb").read())

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

    # У v3 вырезки нет: кадр идёт как есть, иначе пропадёт отражение.
    cutout = None if (args.no_cutout or v3) else cutout_binary(args.cutout)
    if not v3 and not cutout and not args.no_cutout and not args.dry_run:
        log(f"ВНИМАНИЕ: вырезки нет (нет {CUTOUT_BIN} и не собрался "
            "swiftc) — кадры соберутся с чёрной полосой под колёсами. "
            "Осознанно — добавьте --no-cutout.")
        if not args.recompose:
            raise SystemExit(1)

    if args.recompose:
        return recompose(args, cutout)

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
    if args.only:
        wanted = {s.strip() for s in args.only.split(",") if s.strip()}
        unknown = wanted - {c["slug"] for c in cars}
        if unknown:
            raise SystemExit(f"Нет в списке: {', '.join(sorted(unknown))}")
        cars = [c for c in cars if c["slug"] in wanted]
    todo = [c for c in cars
            if args.force or not os.path.exists(os.path.join(args.out, c["slug"] + ".png"))]
    if args.limit:
        todo = todo[:args.limit]
    log(f"список: {len(cars)}, к генерации: {len(todo)}, бюджет: ${args.budget:.2f}")

    if args.dry_run:
        log(f"рецепт {args.recipe}, модель {args.model}, "
            f"образец {forced[0] if forced else 'нет'}, кадры в {args.out}")
        if todo:
            log("промпт первой машины целиком:\n    "
                + prompt_for(todo[0], args.recipe, forced))
        if v3:
            log(f"оценка по цене v3 (${PROD_PRICE}/кадр): "
                f"${PROD_PRICE * len(todo):.2f} за {len(todo)}")
        for car in todo:
            reference = forced
            if args.reference_by_brand:
                reference = pick_reference(car["slug"], car["prompt"])
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
        reference = forced
        if args.reference_by_brand:
            reference = pick_reference(car["slug"], car["prompt"])
        dest = os.path.join(args.out, car["slug"] + ".png")
        best: tuple[int, bytes, str] | None = None

        # Края проверяются у СОБРАННОГО кадра, не у сырья: у сырья batch2
        # они светлые всегда (27-51), их гасит виньетка сборки. Проверка по
        # сырью браковала бы каждый кадр и удваивала счёт. У v3 собранный
        # кадр и есть сырьё в размере прода — все 75 прошли так же.
        for attempt in range(1, args.attempts + 1):
            if attempt > 1 and not affordable():
                break
            try:
                png, cost = generate(car, key, args.model, reference, args.recipe)
            except Disconnected as error:
                # Без повтора: обрыв не значит, что денег не списали.
                log(f"{car['slug']}: ответ оборвался ({error}). Генерация могла "
                    "пройти и списаться — сверить с Activity на openrouter.ai.")
                log(f"остановлено. сделано: {len(made)}, потрачено ${spent:.4f}; "
                    "тот же запуск продолжит с этой машины")
                return 1
            except SystemExit:
                log(f"{car['slug']}: остановлено на ошибке ниже. сделано: "
                    f"{len(made)}, потрачено ${spent:.4f}")
                raise
            spent += cost
            prices.append(cost)
            tmp_raw = dest + f".try{attempt}.raw.png"
            tmp_out = dest + f".try{attempt}.png"
            open(tmp_raw, "wb").write(png)
            if v3:
                given = fit_prod(tmp_raw, tmp_out, args.flip)
                if abs(given[0] / given[1] - 1.5) > 0.02:
                    log(f"{car['slug']}: модель отдала {given[0]}×{given[1]}, "
                        "не 3:2 — кадр обрезан сильно, смотреть глазами")
            elif args.raw:
                open(tmp_out, "wb").write(png)
                finalize(tmp_out, flip=args.flip, floor=args.floor)
            else:
                assemble(car["slug"], tmp_raw, tmp_out, cutout, args.flip, args.floor,
                         args.reflection, args.contact, args.shadow)
            os.remove(tmp_raw)
            ok, peak = edges_are_black(tmp_out)
            if best is None or peak < best[0]:
                if best is not None:
                    os.remove(best[2])
                best = (peak, png, tmp_out)
            else:
                os.remove(tmp_out)
            log(f"{car['slug']}: попытка {attempt}, края {peak}, "
                f"{'ок' if ok else 'светлые'}, ${cost:.4f} (всего ${spent:.4f})")
            if ok:
                break

        if best is None:
            failed.append(car["slug"])
            continue
        # Сырьё остаётся рядом нетронутым: пересобрать кадр по-другому
        # (--recompose) можно бесплатно, а перегенерировать — нет.
        # Направление морды задаёт образец; без него модель может
        # нарисовать её влево — тогда --flip, как с Кандинским.
        raw_path = os.path.join(args.out, car["slug"] + ".raw.png")
        open(raw_path, "wb").write(best[1])
        os.replace(best[2], dest)
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
