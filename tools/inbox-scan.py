#!/usr/bin/env python3
"""Разбор папки inbox/: что автоматика возьмёт в работу сегодня.

Читает фронтматтер заметок в inbox/tasks и inbox/bugs, отбирает `status: todo`,
сортирует (priority: high первым, дальше по имени файла) и печатает очередь.
Заодно называет заметки, которые взяты не будут, и почему — иначе «не взяли»
и «взяли и молча ничего не сделали» выглядят одинаково.

Колонка `zone` говорит, что с задачей делать: `auto` — писать код, `find` —
сперва выяснить, где это живёт в проекте, и тоже писать, `review` — работа
не в коде (сервер, деньги, договориться с человеком) или в ручном pbxproj.

Перед выдачей очереди сам снимает дубли (`inbox-dedup.py --mark`): то, что
уже сделано в любой ветке на GitHub, в очередь не попадает, и отдельную
команду для этого помнить не нужно.

Запуск:
    python3 tools/inbox-scan.py            # человекочитаемо
    python3 tools/inbox-scan.py --json     # для навыка /inbox
    python3 tools/inbox-scan.py --no-dedup # без проверки дублей, для отладки
"""
import json, os, re, sys

INBOX = "inbox"
FOLDERS = ("tasks", "bugs")
TAKEN = "todo"

# Код проекта. Здесь разбор пишет правку — включая вью. Собрать её в облаке
# нечем, поэтому каждая такая правка едет в ветку с честной пометкой «сборкой
# не проверено», а не выдаётся за готовую. План вместо кода полезен там, где
# работа вообще не в коде, — а не везде, где нет Xcode.
AUTO_PREFIXES = ("AppMVP/", "docs/", "tools/", "inbox/")

# Сюда разбор не лезет: ручной pbxproj ломается молча, а Xcode на битом
# проекте падает сообщениями, которые не намекают на причину.
NEVER = ("Canary.xcodeproj/",)


def frontmatter(text):
    """Плоский YAML между парой `---`. Вложенности здесь не бывает."""
    m = re.match(r"\A---\r?\n(.*?)\r?\n---\r?\n?", text, re.S)
    if not m:
        return None
    out = {}
    for line in m.group(1).splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        k, sep, v = line.partition(":")
        if not sep:
            continue
        out[k.strip()] = v.strip().strip("\"'")
    return out


def zone(scope):
    """auto — писать код; find — сперва выяснить, где это живёт; review — не код."""
    if not scope:
        return "find"
    if scope.startswith(NEVER):
        return "review"
    return "auto" if scope.startswith(AUTO_PREFIXES) else "review"


def scan():
    queue, skipped = [], []
    for folder in FOLDERS:
        path = os.path.join(INBOX, folder)
        if not os.path.isdir(path):
            continue
        for name in sorted(os.listdir(path)):
            if not name.endswith(".md") or name.startswith("_"):
                continue
            full = os.path.join(path, name)
            with open(full, encoding="utf-8") as f:
                text = f.read()
            fm = frontmatter(text)
            if fm is None:
                skipped.append({"path": full, "why": "нет фронтматтера"})
                continue
            status = fm.get("status", "")
            if status != TAKEN:
                skipped.append({"path": full,
                                "why": f"status: {status or '(пусто)'}"})
                continue
            queue.append({
                "path": full,
                "kind": fm.get("kind") or folder.rstrip("s"),
                "scope": fm.get("scope", ""),
                "priority": fm.get("priority", ""),
                "zone": zone(fm.get("scope", "")),
                "title": name[:-3],
            })
    queue.sort(key=lambda it: (it["priority"] != "high", it["path"]))
    return queue, skipped


def main():
    # Дубли снимаются здесь, а не отдельной командой в промпте: очередь,
    # в которой лежит уже сделанное, — не очередь. Любой, кто спросил
    # «что делать сегодня», получает ответ уже без дублей, и помнить про
    # отдельный шаг никому не нужно. --no-dedup — только для отладки.
    if "--no-dedup" not in sys.argv:
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "inbox_dedup", os.path.join(os.path.dirname(os.path.abspath(__file__)), "inbox-dedup.py"))
        dedup = importlib.util.module_from_spec(spec); spec.loader.exec_module(dedup)
        marked = [d for d in dedup.find() if dedup.mark(d)]
        if marked and "--json" not in sys.argv:
            print(f"Дублей снято: {len(marked)} — уже сделано в другой ветке, в очередь не идут.")
            for d in marked:
                print(f"  {d['path']} → {d['where']} [{d['ref']}]")
            print()
    queue, skipped = scan()
    if "--json" in sys.argv:
        json.dump({"queue": queue, "skipped": skipped},
                  sys.stdout, ensure_ascii=False, indent=2)
        print()
        return 0
    if not queue:
        print("Очередь пуста: заметок со `status: todo` нет.")
    for it in queue:
        mark = {"auto": "auto  ", "find": "find  "}.get(it["zone"], "review")
        prio = " [high]" if it["priority"] == "high" else ""
        print(f"{mark}  {it['path']}{prio}")
        if it["scope"]:
            print(f"          scope: {it['scope']}")
    if skipped:
        print("\nНе взято:")
        for it in skipped:
            print(f"  {it['path']} — {it['why']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
