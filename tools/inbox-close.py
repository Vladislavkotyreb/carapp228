#!/usr/bin/env python3
"""Закрывает галочки в заметках Obsidian за сделанные задачи.

`inbox-extract.py` заводит задачу из строки `- [ ] …` и записывает в шапку,
откуда она взялась (`source: файл:строка`). Когда задача сделана и лежит
в `inbox/done/`, этот скрипт находит исходную строку и переписывает её:

    - [ ] прелоудеры скелетоны
    - [x] прелоудеры скелетоны — [[done/2026-09-12-прелоудеры-скелетоны]]

Ссылка — вики-ссылка Obsidian на заметку в `done/`: там раздел «Что сделано»
и имя ветки. Строку ищет по тексту, а не по номеру: номера в заметке
уезжают при каждой правке.

Это единственное место, где прогон трогает заметку человека, и трогает
ровно две вещи: галочку и хвост строки. Остальной текст не меняется.
Правка с телефона позже прогона победит — мак копирует более новую версию;
тогда галочка встанет следующим утром: шаг идемпотентный и каждый раз
доставляет недостающие.

Берутся только `status: done`. `blocked`, `needs-review`, `duplicate` —
не закрываются: сделанным это не является.

Запуск:
    python3 tools/inbox-close.py            # поставить галочки
    python3 tools/inbox-close.py --dry-run  # показать, что изменилось бы
"""
import os, re, sys

INBOX = "inbox"
DONE = os.path.join(INBOX, "done")
ITEM = re.compile(r"^(\s*[-*]\s*)\[ \](\s*)(.+?)\s*$")


def split(text):
    m = re.match(r"\A---\r?\n(.*?)\r?\n---\r?\n?", text, re.S)
    if not m:
        return None, ""
    fm = {}
    for line in m.group(1).splitlines():
        k, sep, v = line.partition(":")
        if sep:
            fm[k.strip()] = v.strip().strip("\"'")
    body = text[m.end():]
    first = next((l.strip() for l in body.splitlines() if l.strip()), "")
    return fm, first


def norm(s):
    return " ".join(s.split()).lower()


def done_notes():
    if not os.path.isdir(DONE):
        return
    for name in sorted(os.listdir(DONE)):
        if not name.endswith(".md"):
            continue
        path = os.path.join(DONE, name)
        with open(path, encoding="utf-8") as f:
            fm, first = split(f.read())
        if not fm or fm.get("status") != "done":
            continue
        src = fm.get("source", "")
        src_file = src.rsplit(":", 1)[0] if src else ""
        yield path, name[:-3], first, src_file


CLOSED = re.compile(r"^\s*[-*]\s*\[x\]\s*(.+?)\s*(?:—\s*\[\[.*?\]\])?\s*$", re.I)


def candidates(src_file):
    """Где искать строку: сначала записанный источник, потом все заметки в корне.
    Источник может исчезнуть — так было с backlog.md, который переехал
    в Таски.md; ключ всё равно текст, а не путь."""
    out = []
    if src_file and os.path.isfile(src_file):
        out.append(src_file)
    for name in sorted(os.listdir(INBOX)):
        path = os.path.join(INBOX, name)
        if name.endswith(".md") and os.path.isfile(path) and path not in out:
            out.append(path)
    return out


def find_line(src_file, text):
    """(файл, индекс, 'open'|'closed') или None."""
    target = norm(text)
    for path in candidates(src_file):
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
        for i, line in enumerate(lines):
            m = ITEM.match(line)
            if m and norm(m.group(3)) == target:
                return path, i, "open"
            c = CLOSED.match(line)
            if c and norm(c.group(1)) == target:
                return path, i, "closed"
    return None


def close_line(src_file, text, link):
    """'closed' — закрыли сейчас; 'already' — уже стояло; 'missing' — не нашли."""
    hit = find_line(src_file, text)
    if not hit:
        return "missing"
    path, i, state = hit
    if state == "closed":
        return "already"
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    m = ITEM.match(lines[i])
    lines[i] = f"{m.group(1)}[x]{m.group(2)}{m.group(3)} — [[{link}]]"
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return "closed"


def main():
    dry = "--dry-run" in sys.argv
    closed, already, missing = [], [], []
    for path, stem, text, src_file in done_notes():
        link = f"done/{stem}"
        if dry:
            hit = find_line(src_file, text)
            bucket = missing if not hit else (already if hit[2] == "closed" else closed)
            bucket.append((hit[0] if hit else src_file, text))
            continue
        r = close_line(src_file, text, link)
        hit_path = (find_line(src_file, text) or (src_file,))[0]
        {"closed": closed, "already": already, "missing": missing}[r].append((hit_path, text))
    verb = "Закрылось бы" if dry else "Закрыто"
    print(f"{verb}: {len(closed)}, уже стояло: {len(already)}, строка не найдена: {len(missing)}")
    for src, t in closed:
        print(f"  [x] {t[:70]}  ← {src}")
    for src, t in missing:
        print(f"  ?   {t[:70]}  — в {src or '(источник не записан)'} и в корне inbox такой строки нет")
    return 0


if __name__ == "__main__":
    sys.exit(main())
