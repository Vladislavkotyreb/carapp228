#!/usr/bin/env python3
"""Собирает AppMVP/Resources/Licenses.txt — текст экрана «Ещё» → «Лицензии».

Источник — docs/licenses/: там лежат лицензии как есть, здесь к ним
приставляются названия и ссылки. MIT и Apache 2.0 требуют отдавать текст
лицензии вместе с каждой копией, то есть внутри приложения, а не только в
репозитории (хвост из TAILS.md, 2026-10-07).

    python3 tools/build-licenses.py          # пересобрать
    python3 tools/build-licenses.py --check  # не совпадает — выход 1
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "licenses")
DST = os.path.join(ROOT, "AppMVP", "Resources", "Licenses.txt")

# (название, зачем в приложении, ссылка, файл лицензии или None)
PARTS = [
    ("ShaderKit", "Стекло облачка прослушивания.",
     "https://github.com/jamesrochabrun/ShaderKit", "ShaderKit-MIT.txt"),
    ("car-diagnosis", "Разбор звука двигателя: пайплайн и головы модели.",
     "https://github.com/adam-s/car-diagnosis", "car-diagnosis-MIT.txt"),
    ("LAION CLAP (laion/clap-htsat-unfused)",
     "Аудиомодель разбора звука, переведена в Core ML.",
     "https://huggingface.co/laion/clap-htsat-unfused", "Apache-2.0.txt"),
    ("Yandex MapKit",
     "Карты и адреса поездок. Используется по условиям использования "
     "Яндекс Карт (https://yandex.ru/legal/maps_termsofuse/) и лицензионному "
     "соглашению MapKit SDK (https://yandex.ru/legal/maps_api/).",
     "https://github.com/yandex/mapkit-ios", None),
]


def license_text(name: str) -> str:
    text = open(os.path.join(SRC, name), encoding="utf-8").read()
    # У ShaderKit сверху наша пометка, откуда взят приём; сама лицензия —
    # после черты из минусов.
    marker = "-" * 20
    if marker in text:
        text = text.split(marker, 1)[1].lstrip("-\n")
    return reflow(text.strip("\n"))


def reflow(text: str) -> str:
    """Склеить строки внутри абзаца: файлы лицензий свёрстаны под 80
    колонок, и на телефоне жёсткие переносы рвали строки посередине. Слова
    и порядок не меняются — только перенос."""
    paragraphs = [p for p in text.split("\n\n")]
    return "\n\n".join(" ".join(line.strip() for line in p.splitlines() if line.strip())
                       for p in paragraphs if p.strip())


def build() -> str:
    out = ["Beepy использует открытые компоненты. Их лицензии — ниже без изменений.", ""]
    for title, use, link, file in PARTS:
        out += ["", title, use, link, ""]
        if file:
            out += [license_text(file), ""]
    return "\n".join(out).rstrip("\n") + "\n"


if __name__ == "__main__":
    text = build()
    if "--check" in sys.argv:
        current = open(DST, encoding="utf-8").read() if os.path.exists(DST) else ""
        if current != text:
            print("Licenses.txt устарел: python3 tools/build-licenses.py")
            sys.exit(1)
        print("Licenses.txt совпадает с docs/licenses")
        sys.exit(0)
    with open(DST, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"записано: {os.path.relpath(DST, ROOT)} ({len(text)} символов)")
