#!/usr/bin/env python3
"""Русская типографика в строках интерфейса.

Проверяются только строковые литералы Swift, содержащие кириллицу: всё
остальное — идентификаторы, ключи, имена символов SF — латиница, и правила
русского набора к ним неприменимы. Комментарии не проверяются вовсе: они
не попадают на экран.

Интерполяция `\\(...)` схлопывается в один символ-заглушку. Без этого
«\\(grouped(mileage)) км» выглядит как строка без чисел, и разрыв между
числом и единицей не находится — а он и есть самое частое нарушение здесь.

Запуск:
    python3 tools/check-typography.py            # ошибки + предупреждения
    python3 tools/check-typography.py --strict   # предупреждения тоже валят
    python3 tools/check-typography.py --policy   # плюс слова-просьбы
"""
import os, re, sys

SRC = "AppMVP"
VALUE = "\u2591"          # заглушка интерполяции: «здесь было значение»
NBSP = "\u00A0"
UNITS = r"км|м|л|₽|%|мин|ч|сек|шт|кг|л/100"

# (имя, регекс, чем чинить)
ERRORS = [
    ("дефис вместо тире между словами", r"(?<=\s)-(?=\s)", "«—» (длинное тире)"),
    ("диапазон через дефис", r"\d-\d", "«–» (короткое тире, без пробелов)"),
    ("прямые кавычки", r'\\"', "«ёлочки», внутри них „лапки“"),
    ("многоточие тремя точками", r"\.\.\.", "«…» одним символом"),
    ("двойной пробел", r"[ ]{2,}", "один пробел"),
    ("пробел перед знаком препинания", r"[ ]+[,.;:!?](?:\s|$)", "убрать пробел"),
    ("нет пробела после запятой", r",(?=[А-Яа-яЁёA-Za-z])", "пробел после запятой"),
    # Граница здесь не \b: после «₽» и «%» словесного символа нет, и \b
    # не сработал бы вовсе — правило молчало бы ровно там, где нужнее всего.
    (f"число и единица разорваны обычным пробелом",
     rf"[\d{VALUE}][ ](?:{UNITS})(?![А-Яа-яЁёA-Za-z])", rf"неразрывный пробел \\u{{00A0}}"),
]

# Предупреждения: правило верное, но на коротких подписях, которые никогда
# не переносятся, оно шумит. Порог — длина строки, при которой перенос реален.
WRAP_MIN = 25
WARNINGS = [
    # Не ошибка: перенос здесь проставлен руками под макет, и такой же пробел
    # может стоять в самой ноде Figma. Снимешь — центрированная строка уедет
    # на полпробела, и попиксельная сверка покраснеет. Решается сверкой,
    # а не грепом, поэтому только предупреждение.
    ("пробел перед ручным переносом строки", r"[ ]+\\n",
     "убрать, если в макете его нет — проверять сверкой"),
    ("однобуквенный предлог или союз может остаться в конце строки",
     r"(?<=\s)[вксоуиая](?=\s)", rf"неразрывный пробел после него: \\u{{00A0}}"),
]

# Политика «тупиков не бывает»: в приложении, которое умеет доделать само,
# состояние покоя не просит человека ничего нажимать. Решение не принято —
# поэтому только по флагу --policy.
POLICY = [
    ("слово-просьба в тексте интерфейса",
     r"Повторить|Попробуйте|попробуйте|Не удалось|Нажмите",
     "сказать, что произошло, и доделать самим"),
]

def literals(path):
    """(номер строки, текст) для каждого литерала с кириллицей."""
    src = open(path, encoding="utf-8").read()
    src = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), src, flags=re.S)
    out = []
    for i, line in enumerate(src.split("\n"), 1):
        # Убрать построчный комментарий, не тронув // внутри строки.
        clean, in_str, esc = [], False, False
        for ch in line:
            if esc: esc = False; clean.append(ch); continue
            if ch == "\\" and in_str: esc = True; clean.append(ch); continue
            if ch == '"': in_str = not in_str
            if not in_str and ch == "/" and clean and clean[-1] == "/":
                clean.pop(); break
            clean.append(ch)
        code = "".join(clean)
        for m in re.finditer(r'"((?:[^"\\\n]|\\.)*)"', code):
            text = m.group(1)
            # Кириллица — главный признак, но не единственный: «\(сумма) ₽»
            # кириллицы не содержит вовсе, а это интерфейсная строка, и
            # именно в ней рвётся число с единицей.
            if len(text) > 1 and re.search(r"[А-Яа-яЁё₽…«»°]", text):
                out.append((i, text))
    return out

def collapse(text):
    """Интерполяция → один символ; экранированные юникод-точки → сам символ."""
    text = re.sub(r"\\u\{00A0\}", NBSP, text)
    res, i = [], 0
    while i < len(text):
        if text.startswith("\\(", i):
            depth, j = 0, i + 1
            while j < len(text):
                if text[j] == "(": depth += 1
                elif text[j] == ")":
                    depth -= 1
                    if depth == 0: break
                j += 1
            res.append(VALUE); i = j + 1
        else:
            res.append(text[i]); i += 1
    return "".join(res)

def main():
    strict = "--strict" in sys.argv
    policy = "--policy" in sys.argv
    root = os.popen("git rev-parse --show-toplevel 2>/dev/null").read().strip()
    if root: os.chdir(root)

    found = {"ошибка": [], "предупреждение": [], "политика": []}
    total = 0
    for dp, _, fs in os.walk(SRC):
        for f in sorted(fs):
            if not f.endswith(".swift"): continue
            path = os.path.join(dp, f)
            for line, raw in literals(path):
                text = collapse(raw)
                total += 1
                for kind, rules in (("ошибка", ERRORS), ("предупреждение", WARNINGS),
                                    ("политика", POLICY if policy else [])):
                    for name, pat, fix in rules:
                        if (kind == "предупреждение" and len(text) < WRAP_MIN
                                and "перенос" not in name): continue
                        if re.search(pat, text):
                            found[kind].append((path, line, raw, name, fix))

    for kind in ("ошибка", "предупреждение", "политика"):
        items = found[kind]
        if not items: continue
        print(f"\n=== {kind.upper()}: {len(items)} ===")
        for path, line, raw, name, fix in items:
            print(f"{path}:{line}")
            print(f"    «{raw}»")
            print(f"    {name} → {fix}")

    print(f"\nПроверено строк интерфейса: {total}. "
          f"Ошибок: {len(found['ошибка'])}, "
          f"предупреждений: {len(found['предупреждение'])}"
          + (f", политика: {len(found['политика'])}" if policy else ""))
    bad = len(found["ошибка"]) + (len(found["предупреждение"]) if strict else 0)
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
