#!/usr/bin/env bash
# Тест tools/inbox-dedup.py на отдельном репозитории. Настоящий не трогает.
#
# Сценарий — тот, что дал дубль 2026-09-11: задача открыта в main, но уже
# закрыта в другой ветке. Плюс: две одинаковые задачи в одной очереди,
# отсутствие ложных срабатываний, идемпотентность --mark.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

note(){ # note <путь> <status> <текст>
  mkdir -p "$(dirname "$1")"
  printf -- '---\nstatus: %s\nkind: task\nscope:\n---\n\n%s\n' "$2" "$3" > "$1"
}

git init -q --bare "$T/remote.git"
git clone -q "$T/remote.git" "$T/repo" 2>/dev/null
cd "$T/repo"; git config user.email t@t; git config user.name t
mkdir -p tools; cp "$here/inbox-dedup.py" "$here/inbox-scan.py" tools/
note inbox/tasks/x.md todo "починить шторку на главной"
note inbox/tasks/y.md todo "иконка приложения"
note inbox/tasks/z.md todo "починить шторку на главной"
git add -A; git commit -qm init; git branch -M main; git push -q -u origin main 2>/dev/null

# другая ветка закрывает x — под другим именем файла
git checkout -q -b claude/inbox-другая
mkdir -p inbox/done; git mv inbox/tasks/x.md inbox/done/сделано-шторка.md
sed -i 's/status: todo/status: done/' inbox/done/сделано-шторка.md
printf '\n## Что сделано\n\nсделано\n' >> inbox/done/сделано-шторка.md
git commit -qam "закрыто в другой ветке"; git push -q -u origin claude/inbox-другая 2>/dev/null
git checkout -q main; git fetch -q origin

echo "== 1. без --mark: находит, ничего не меняет =="
set +e; out="$(python3 tools/inbox-dedup.py)"; rc=$?; set -e
check "код возврата 3" '[[ $rc -eq 3 ]]'
check "x — дубль закрытого в другой ветке" 'grep -q "inbox/tasks/x.md" <<<"$out" && grep -q "claude/inbox-другая" <<<"$out"'
check "z (тот же текст, что x) — тоже дубль" 'grep -q "inbox/tasks/z.md" <<<"$out"'
check "y не тронут" '! grep -q "inbox/tasks/y.md" <<<"$out"'
check "файлы не изменены" '[[ -z "$(git status --porcelain inbox)" ]]'

echo "== 2. --mark: помечает, очередь худеет =="
set +e; python3 tools/inbox-dedup.py --mark >/dev/null; rc=$?; set -e
check "код возврата 3 и с --mark" '[[ $rc -eq 3 ]]'
check "x получил status: duplicate" 'grep -q "^status: duplicate" inbox/tasks/x.md'
check "z получил status: duplicate" 'grep -q "^status: duplicate" inbox/tasks/z.md'
check "y остался todo" 'grep -q "^status: todo" inbox/tasks/y.md'
check "в x записано, где сделано" 'grep -q "## Дубль" inbox/tasks/x.md && grep -q "сделано-шторка" inbox/tasks/x.md'
queue="$(python3 tools/inbox-scan.py)"
check "сканер отдаёт только y" 'grep -q "inbox/tasks/y.md" <<<"$queue" && ! grep -q "^auto.*x.md\|^find.*x.md\|^auto.*z.md\|^find.*z.md" <<<"$queue"'

echo "== 3. повторный --mark ничего не меняет =="
sum1="$(cat inbox/tasks/*.md | sha1sum)"
set +e; out="$(python3 tools/inbox-dedup.py --mark)"; rc=$?; set -e
sum2="$(cat inbox/tasks/*.md | sha1sum)"
check "код возврата 0" '[[ $rc -eq 0 ]]'
check "«Дублей нет»" 'grep -q "Дублей нет" <<<"$out"'
check "файлы байт в байт те же" '[[ "$sum1" == "$sum2" ]]'

echo "== 4. нет ложных срабатываний на похожем тексте =="
note inbox/tasks/w.md todo "починить шторку на главной — вторая версия"
set +e; out="$(python3 tools/inbox-dedup.py)"; rc=$?; set -e
check "другой текст — не дубль" '[[ $rc -eq 0 ]] && grep -q "Дублей нет" <<<"$out"'

echo "== 5. своя же done/ тоже считается =="
mkdir -p inbox/done; git mv inbox/tasks/y.md inbox/done/y.md; sed -i 's/status: todo/status: done/' inbox/done/y.md
note inbox/tasks/y2.md todo "иконка приложения"
set +e; out="$(python3 tools/inbox-dedup.py)"; rc=$?; set -e
check "заведённое заново после закрытия здесь — дубль" '[[ $rc -eq 3 ]] && grep -q "y2.md" <<<"$out" && grep -q "эта ветка" <<<"$out"'

echo "== 6. две одинаковые todo без закрытой копии — вторая дубль первой =="
note inbox/tasks/p.md todo "скелетоны на главной"
note inbox/tasks/q.md todo "скелетоны на главной"
set +e; out="$(python3 tools/inbox-dedup.py)"; rc=$?; set -e
check "q — «та же задача в очереди», p чист" 'grep -q "^  inbox/tasks/q.md" <<<"$out" && grep -q "та же задача" <<<"$out" && ! grep -q "^  inbox/tasks/p.md" <<<"$out"'

echo; echo "прошло: $pass, упало: $fail"
[[ $fail -eq 0 ]]
