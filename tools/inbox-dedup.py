#!/usr/bin/env python3
"""Дубли задач: то, что уже закрыто в другой ветке, в работу не берётся.

Откуда берутся дубли. Прогон работает от `main`, а закрытая задача может лежать
в `done/` другой, ещё не слитой ветки. Для `main` она по-прежнему `todo`, и
прогон делает её заново. Так 2026-09-11 две задачи получили по две реализации.

Что делает. Для каждой заметки `status: todo` считает ключ — тот же, что
у `inbox-extract.py`: sha1 первой строки тела, то есть исходного текста задачи.
Переименование файла ключ не меняет. Затем смотрит `inbox/done/` во **всех**
ветках на GitHub (`refs/remotes/origin/*`) и в своей же папке: совпал ключ —
это дубль. Плюс две одинаковые `todo` в одной папке — тоже дубль, вторая.

С `--mark` дубль получает `status: duplicate` и раздел с указанием, где он
сделан. `inbox-scan.py` берёт только `todo`, так что помеченное в очередь
не попадает — процесс на дубле останавливается сам.

Код возврата: 0 — дублей нет, 3 — есть (и с `--mark`, и без).

Запуск:
    python3 tools/inbox-dedup.py            # показать
    python3 tools/inbox-dedup.py --mark     # пометить в файлах
    python3 tools/inbox-dedup.py --json
"""
import hashlib, json, os, re, subprocess, sys

INBOX = "inbox"
OPEN_DIRS = ("tasks", "bugs")
DONE_DIR = "done"


def git(*args):
    # quotepath=false: иначе кириллические пути приходят в кавычках
    # с восьмеричными кодами, и «inbox/done/…md» не кончается на .md.
    r = subprocess.run(["git", "-c", "core.quotepath=false", *args], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def split(text):
    """(фронтматтер-словарь или None, первая непустая строка тела)."""
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


def key(text):
    return hashlib.sha1(text.strip().lower().encode("utf-8")).hexdigest()[:12]


def done_elsewhere():
    """ключ → (ветка, путь) для всего, что лежит в done/ в любой ветке origin."""
    out = {}
    refs = git("for-each-ref", "--format=%(refname:short)", "refs/remotes/origin").split()
    for ref in refs:
        if ref.endswith("/HEAD"):
            continue
        paths = git("ls-tree", "-r", "--name-only", ref, "--", f"{INBOX}/{DONE_DIR}").split("\n")
        for p in paths:
            if not p.endswith(".md"):
                continue
            _, first = split(git("show", f"{ref}:{p}"))
            if first:
                out.setdefault(key(first), (ref, p))
    # и своя же папка done/ — закрытое здесь, но по ошибке снова заведённое
    local = os.path.join(INBOX, DONE_DIR)
    if os.path.isdir(local):
        for name in sorted(os.listdir(local)):
            if name.endswith(".md"):
                with open(os.path.join(local, name), encoding="utf-8") as f:
                    _, first = split(f.read())
                if first:
                    out.setdefault(key(first), ("(эта ветка)", f"{local}/{name}"))
    return out


def open_notes():
    for d in OPEN_DIRS:
        folder = os.path.join(INBOX, d)
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            if not name.endswith(".md") or name.startswith("_"):
                continue
            path = os.path.join(folder, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            fm, first = split(text)
            if fm and fm.get("status") == "todo" and first:
                yield path, first, text


def find():
    done = done_elsewhere()
    seen = {}
    dups = []
    for path, first, text in open_notes():
        k = key(first)
        if k in done:
            ref, where = done[k]
            dups.append({"path": path, "text": first, "reason": "уже сделано", "ref": ref, "where": where})
        elif k in seen:
            dups.append({"path": path, "text": first, "reason": "та же задача в очереди", "ref": "(эта ветка)", "where": seen[k]})
        else:
            seen[k] = path
    return dups


def mark(d):
    with open(d["path"], encoding="utf-8") as f:
        s = f.read()
    if "status: todo" not in s:
        return False
    s = s.replace("status: todo", "status: duplicate", 1).rstrip() + (
        "\n\n## Дубль\n\n"
        f"{d['reason'].capitalize()}: `{d['where']}` в `{d['ref']}`. "
        "Помечено `tools/inbox-dedup.py`: в очередь не берётся, чтобы не делать "
        "одну работу дважды. Если это всё-таки другая задача — перепиши первую "
        "строку заметки так, чтобы она отличалась, и верни `status: todo`.\n"
    )
    with open(d["path"], "w", encoding="utf-8") as f:
        f.write(s)
    return True


def main():
    dups = find()
    do_mark = "--mark" in sys.argv
    marked = [d["path"] for d in dups if do_mark and mark(d)]
    if "--json" in sys.argv:
        print(json.dumps({"duplicates": dups, "marked": marked}, ensure_ascii=False, indent=2))
    elif not dups:
        print("Дублей нет.")
    else:
        print(f"Дублей: {len(dups)}" + (" — помечены, в очередь не пойдут." if do_mark else " (без --mark ничего не меняю)."))
        for d in dups:
            print(f"  {d['path']}\n      «{d['text'][:70]}»\n      {d['reason']}: {d['where']}  [{d['ref']}]")
    return 3 if dups else 0


if __name__ == "__main__":
    sys.exit(main())
