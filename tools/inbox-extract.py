#!/usr/bin/env python3
"""Из заметок Obsidian — задачи для разбора.

В папке из хранилища лежат обычные заметки: списки с галочками, мысли,
скриншоты. Разбор же работает с отдельной заметкой на задачу — со `status`
и `scope`. Этот скрипт переводит одно в другое: находит в заметках строки
`- [ ] …` и заводит под каждую новую файл в `inbox/tasks/`.

Уже заведённые помнит `inbox/.extracted.json`, иначе одна и та же строка
превращалась бы в задачу каждое утро. Ключ — текст строки: переписал строку
в заметке, она заведётся заново, и это правильнее молчания.

`- [x]` не берутся: галочка и значит «не надо».

Запуск:
    python3 tools/inbox-extract.py            # завести новые задачи
    python3 tools/inbox-extract.py --dry-run  # только показать, что завелось бы
"""
import hashlib, json, os, re, sys
from datetime import date

INBOX = "inbox"
TASKS = os.path.join(INBOX, "tasks")
STATE = os.path.join(INBOX, ".extracted.json")

# Свои файлы — не источник задач: README описывает папку, backlog ведётся руками.
SKIP = {"README.md"}
# Подпапки — хозяйство разбора, туда скрипт не заглядывает.
SKIP_DIRS = {"tasks", "bugs", "done", "reports", "attachments", "_templates"}

ITEM = re.compile(r"^\s*[-*]\s*\[ \]\s*(.+?)\s*$")
HEADING = re.compile(r"^\s*(#{1,6})\s*(.+?)\s*$")
# Заметка «не для разбора»: шапка с `beepy: ignore`. Признак, а не список имён —
# пометить можно любую, и переименование её не расколдует.
IGNORED = re.compile(r"\A---\r?\n(.*?)\r?\n---", re.S)


def ignored(path):
    with open(path, encoding="utf-8") as f:
        head = f.read(2048)
    m = IGNORED.match(head)
    if not m:
        return False
    for line in m.group(1).splitlines():
        k, sep, v = line.partition(":")
        if sep and k.strip() == "beepy" and v.strip().strip("\"'") in ("ignore", "игнор"):
            return True
    return False


def slug(text, limit=60):
    """Имя файла из текста строки: кириллицу оставляем, мусор — нет."""
    s = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE).strip().lower()
    s = re.sub(r"[\s_]+", "-", s)
    return s[:limit].strip("-") or "задача"


def key(text):
    return hashlib.sha1(text.strip().lower().encode("utf-8")).hexdigest()[:12]


def sources():
    """Заметки в корне inbox/ — то, что приехало из хранилища."""
    for name in sorted(os.listdir(INBOX)):
        path = os.path.join(INBOX, name)
        if os.path.isdir(path) or not name.endswith(".md") or name in SKIP:
            continue
        yield path
    # Подпапки хранилища, кроме хозяйства разбора.
    for name in sorted(os.listdir(INBOX)):
        path = os.path.join(INBOX, name)
        if not os.path.isdir(path) or name in SKIP_DIRS or name.startswith("."):
            continue
        for dp, _, files in os.walk(path):
            for f in sorted(files):
                if f.endswith(".md"):
                    yield os.path.join(dp, f)


def items(path):
    """Строки с незакрытой галочкой и раздел, под которым они стоят."""
    section = ""
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            h = HEADING.match(line)
            if h:
                section = h.group(2)
                continue
            m = ITEM.match(line)
            if m:
                text = m.group(1).strip()
                # Пустая галочка — заготовка в шаблоне, а не задача.
                if len(text) < 2:
                    continue
                yield n, text, section


def main():
    dry = "--dry-run" in sys.argv
    seen = {}
    if os.path.exists(STATE):
        with open(STATE, encoding="utf-8") as f:
            seen = json.load(f)

    os.makedirs(TASKS, exist_ok=True)
    today = date.today().isoformat()
    made = []

    for path in sources():
        if ignored(path):
            continue
        for line_no, text, section in items(path):
            k = key(text)
            if k in seen:
                continue
            name = f"{today}-{slug(text)}.md"
            dest = os.path.join(TASKS, name)
            if os.path.exists(dest):
                name = f"{today}-{slug(text)}-{k}.md"
                dest = os.path.join(TASKS, name)
            body = (
                "---\n"
                "status: todo\n"
                "kind: task\n"
                "scope:\n"
                "priority:\n"
                f"source: {path}:{line_no}\n"
                "---\n\n"
                f"{text}\n"
            )
            if section:
                body += f"\nРаздел заметки: {section}\n"
            body += (
                "\nЗаведено автоматически из заметки Obsidian. `scope` пуст, "
                "значит разбор не тронет код: он выяснит, где это делается, "
                "и напишет план.\n"
            )
            made.append((dest, text))
            seen[k] = dest
            if not dry:
                with open(dest, "w", encoding="utf-8") as f:
                    f.write(body)

    if not dry:
        with open(STATE, "w", encoding="utf-8") as f:
            json.dump(seen, f, ensure_ascii=False, indent=2, sort_keys=True)

    if not made:
        print("Новых строк с галочкой нет.")
        return 0
    print(f"{'Завелось бы' if dry else 'Заведено'}: {len(made)}")
    for dest, text in made:
        print(f"  {dest}\n      {text[:80]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
