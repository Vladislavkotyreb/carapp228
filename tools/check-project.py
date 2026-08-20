#!/usr/bin/env python3
"""Проверка целостности Wheelly.xcodeproj/project.pbxproj.

Проект ведётся вручную, и Xcode на битом проекте падает сообщениями, которые
не намекают на причину: коллизия ID однажды дала `unrecognized selector`.
Здесь тот же файл читается как объектный граф — без Xcode, на любой машине.

Запуск: python3 tools/check-project.py
"""
import collections, json, os, subprocess, sys, tempfile

PBX = "Wheelly.xcodeproj/project.pbxproj"
SRC = "AppMVP"

def main() -> int:
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True).stdout.strip()
    if root:
        os.chdir(root)
    if not os.path.isfile(PBX):
        print(f"нет {PBX}")
        return 1

    with tempfile.NamedTemporaryFile(suffix=".json") as tmp:
        r = subprocess.run(["plutil", "-convert", "json", "-o", tmp.name, PBX],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print("plutil не смог разобрать проект — сломан plist:")
            print(r.stderr.strip())
            return 1
        objects = json.load(open(tmp.name))["objects"]

    bad = []
    def check(good, msg):
        print(("  ✓ " if good else "  ✗ ") + msg)
        if not good:
            bad.append(msg)

    # 1. Висячие ссылки: объект ссылается на ID, которого в проекте нет.
    dangling = []
    for oid, obj in objects.items():
        for key in ("children", "files"):
            for ref in obj.get(key, []):
                if ref not in objects:
                    dangling.append(f"{oid}.{key} → {ref}")
        ref = obj.get("fileRef")
        if isinstance(ref, str) and ref not in objects:
            dangling.append(f"{oid}.fileRef → {ref}")
    check(not dangling, f"висячих ссылок нет ({len(dangling)})")
    for x in dangling[:10]:
        print("       ", x)

    phases = [k for k, v in objects.items() if v.get("isa") == "PBXSourcesBuildPhase"]
    compiled = {}
    for ph in phases:
        for b in objects[ph].get("files", []):
            ref = objects.get(b, {}).get("fileRef")
            if ref in objects:
                compiled[ref] = objects[ref].get("path")

    # 2. Один файл — одна запись компиляции.
    counts = collections.Counter(
        objects[b]["fileRef"] for ph in phases for b in objects[ph].get("files", [])
        if objects.get(b, {}).get("fileRef") in objects)
    dup = sorted(objects[r].get("path", r) for r, n in counts.items() if n > 1)
    check(not dup, f"дублей в фазе компиляции нет ({dup})")

    # 3. Каждый .swift на диске проект собирает, и наоборот.
    names = set(compiled.values())
    on_disk = []
    for dirpath, _, files in os.walk(SRC):
        on_disk += [(os.path.join(dirpath, f), f) for f in files if f.endswith(".swift")]
    missing = sorted(p for p, f in on_disk if f not in names)
    check(not missing, f"все .swift из {SRC}/ собираются ({len(missing)} мимо проекта)")
    for x in missing:
        print("        НЕ СОБИРАЕТСЯ:", x)

    disk_names = {f for _, f in on_disk}
    stale = sorted(n for n in names if n and n.endswith(".swift") and n not in disk_names)
    check(not stale, f"ссылок на удалённые файлы нет ({stale})")

    # 4. Пути групп существуют на диске.
    def walk(gid, prefix):
        g = objects[gid]
        path = g.get("path")
        here = os.path.join(prefix, path) if path else prefix
        if g.get("isa") == "PBXGroup" and path and not os.path.isdir(here):
            yield here
        for c in g.get("children", []):
            if objects.get(c, {}).get("isa") == "PBXGroup":
                yield from walk(c, here)
    roots = [k for k, v in objects.items()
             if v.get("isa") == "PBXGroup" and not v.get("path") and "children" in v]
    ghost = sorted({g for r in roots for g in walk(r, ".")})
    check(not ghost, f"каталоги групп существуют ({ghost})")

    print("\nПроект цел." if not bad else f"\nПроблем: {len(bad)}.")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
