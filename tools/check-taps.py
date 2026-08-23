"""Зоны касания у кнопок: фон нарисован, а нажать нельзя.

В SwiftUI зона касания кнопки берётся от **содержимого метки**, а не от
оформления. `.background()` и `.liquidGlass()` рисуют фон, но цель нажатия не
расширяют: нажимаются буквы и значок, а отступы и залитая капсула вокруг них —
нет. Объявляет зону только `.contentShape()`.

Дефект не видно при чтении кода: `.liquidGlass(in: Capsule())` выглядит как
рабочий фон, и кнопка на экране выглядит правильно. Ловится он только пальцем —
и ловился: половина кнопок приложения (14 из 28) нажималась по надписи.

Пропускаются кнопки внутри `contextMenu`, `.alert` и `confirmationDialog` —
там раскладку и зону даёт система.

Запуск: python3 tools/check-taps.py
"""
import glob
import re
import sys

ROOT = "AppMVP"
# Фон, который сам по себе зону не даёт
BACKGROUND = re.compile(r"\.liquidGlass\(|\.background\(|\.glassCapsule\(")
BUTTON = re.compile(r"\bButton\s*[({]|Button\(action|Button\(role|Button\(\"")
# Контейнеры, где зону назначает система
SYSTEM = ("contextMenu", ".alert(", "confirmationDialog", ".sheet(")
# Стили, которые объявляют зону внутри себя
OWN_SHAPE = ("ProminentCapsuleStyle", "PlainCapsuleStyle", "ContentAreaStyle",
             "prominentGlass", "plainGlass")

# Сколько строк после `Button` считаем его телом. С запасом: у карточек
# выбора метка занимает два десятка строк.
WINDOW = 34


def button_blocks(lines):
    """Границы каждой кнопки: от строки с `Button` до конца окна."""
    for index, line in enumerate(lines):
        if BUTTON.search(line):
            yield index, "\n".join(lines[index:index + WINDOW]), \
                "\n".join(lines[max(0, index - 8):index])


def main() -> int:
    problems = []
    for path in sorted(glob.glob(f"{ROOT}/**/*.swift", recursive=True)):
        # Копии от файлового провайдера («Файл 2.swift») в сборку не входят
        if re.search(r" \d+\.swift$", path):
            continue
        lines = open(path, encoding="utf-8").read().split("\n")
        for index, block, before in button_blocks(lines):
            if any(marker in before for marker in SYSTEM):
                continue
            if not BACKGROUND.search(block):
                continue
            if "contentShape" in block or any(s in block for s in OWN_SHAPE):
                continue
            problems.append((path, index + 1, lines[index].strip()[:56]))

    if not problems:
        print("Зоны касания: у всех кнопок с фоном объявлен contentShape.")
        return 0

    print(f"Кнопки с фоном, но без объявленной зоны касания: {len(problems)}\n")
    for path, line, text in problems:
        print(f"  {path}:{line}")
        print(f"      {text}")
    print("\nНажимается только надпись. Добавьте `.contentShape(<форма фона>)`")
    print("сразу после фона — или переведите кнопку на стиль из")
    print("Core/Design/Components/OnboardingButtons.swift, они объявляют зону сами.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
