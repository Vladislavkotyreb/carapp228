#!/usr/bin/env python3
"""Каталог кадров машин: правила, файлы и списки генерации сходятся.

Три источника обязаны совпадать:

- правила подбора в `AppMVP/Core/Pure/CarCatalog.swift` (`Rule("slug", …)`
  и `plateOverrides`);
- файлы `AppMVP/Resources/CarCatalog/<slug>.heic`;
- списки генерации `tools/catalog_cars.json` и `tools/catalog_cars_next.json`.

Правило без файла — не безобидная строка: `CarCatalogPreview` на любой
найденный слаг рисует серую подложку и ждёт кадр, которого нет. Файл без
правила — мёртвый груз в бандле, до него не добраться ни по одному названию.
Слаг в списке генерации без файла — просто ещё не сгенерирован, это
предупреждение, а не ошибка.

Запуск: python3 tools/check-catalog.py     # код возврата 1 при расхождении
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWIFT = os.path.join(ROOT, "AppMVP", "Core", "Pure", "CarCatalog.swift")
ASSETS = os.path.join(ROOT, "AppMVP", "Resources", "CarCatalog")
LISTS = [os.path.join(ROOT, "tools", "catalog_cars.json"),
         os.path.join(ROOT, "tools", "catalog_cars_next.json")]


def main():
    src = open(SWIFT, encoding="utf-8").read()
    rules = set(re.findall(r'Rule\("([a-z0-9\-]+)"', src))
    overrides = set(re.findall(r'"[^"]+":\s*"([a-z0-9\-]+)"', src))
    referenced = rules | overrides
    files = {f[:-5] for f in os.listdir(ASSETS) if f.endswith(".heic")}
    listed = set()
    for path in LISTS:
        if os.path.exists(path):
            listed |= {c["slug"] for c in json.load(open(path, encoding="utf-8"))}

    bad = 0
    no_file = sorted(referenced - files)
    if no_file:
        bad += 1
        print(f"ОШИБКА: правило есть, файла нет ({len(no_file)}) — превью "
              f"покажет пустую подложку:")
        for s in no_file:
            print(f"  {s}.heic")
    no_rule = sorted(files - referenced)
    if no_rule:
        bad += 1
        print(f"ОШИБКА: файл есть, правила нет ({len(no_rule)}) — кадр "
              f"недостижим ни по одному названию:")
        for s in no_rule:
            print(f"  {s}")
    pending = sorted(listed - files)
    if pending:
        print(f"ещё не сгенерировано ({len(pending)}): {', '.join(pending)}")

    print(f"правил: {len(rules)}, пасхалок: {len(overrides)}, файлов: {len(files)}, "
          f"в списках: {len(listed)} — "
          + ("расхождения есть" if bad else "всё сходится"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
