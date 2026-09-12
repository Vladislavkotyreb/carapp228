#!/usr/bin/env bash
# Тест tools/inbox-close.py на временной папке. Настоящий inbox не трогает.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }; bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
cd "$T"; mkdir -p tools inbox/done; cp "$here/inbox-close.py" tools/

cat > inbox/Таски.md <<'EOF'
### карта
- [ ] допилить карту (чипсы и избранное)
- [ ]   прелоудеры   скелетоны
- [x] прикрутить апи номерограмма
- [ ] бекенд (бд, vps)
заметка без галочки
EOF
note(){ printf -- '---\nstatus: %s\nkind: task\nscope:\nsource: %s\n---\n\n%s\n\n## Что сделано\n\nсделано\n' "$2" "$3" "$4" > "$1"; }
note inbox/done/2026-09-12-прелоудеры-скелетоны.md done "inbox/Таски.md:3" "Прелоудеры скелетоны"
note inbox/done/2026-09-12-бекенд.md needs-review "inbox/Таски.md:5" "бекенд (бд, vps)"
note inbox/done/2026-09-12-чужая.md done "inbox/Таски.md:99" "строки с таким текстом нет"
note inbox/done/2026-09-12-без-источника.md done "inbox/backlog.md:2" "допилить карту (чипсы и избранное)"

echo "== 1. dry-run ничего не меняет =="
sum0="$(sha1sum inbox/Таски.md)"
out="$(python3 tools/inbox-close.py --dry-run)"
check "файл не тронут" '[[ "$sum0" == "$(sha1sum inbox/Таски.md)" ]]'
check "видит две закрываемые (одну — по запасному поиску) и одну потерянную" 'grep -q "Закрылось бы: 2" <<<"$out" && grep -q "строка не найдена: 1" <<<"$out"'

echo "== 2. закрытие =="
out="$(python3 tools/inbox-close.py)"
check "галочка встала, текст с лишними пробелами найден по норме" 'grep -q "^- \[x\]   прелоудеры   скелетоны — \[\[done/2026-09-12-прелоудеры-скелетоны\]\]$" inbox/Таски.md'
check "needs-review не закрывается" 'grep -q "^- \[ \] бекенд (бд, vps)$" inbox/Таски.md'
check "чужая галочка [x] не тронута" 'grep -q "^- \[x\] прикрутить апи номерограмма$" inbox/Таски.md'
check "источник исчез — строка найдена в другой заметке корня" 'grep -q "^- \[x\] допилить карту (чипсы и избранное) — \[\[done/2026-09-12-без-источника\]\]$" inbox/Таски.md'
check "несуществующий текст — не найден, не сломалось" 'grep -q "строка не найдена: 1" <<<"$out"'
check "остальные строки байт в байт" 'grep -q "^### карта$" inbox/Таски.md && grep -q "^заметка без галочки$" inbox/Таски.md'
check "строк столько же" '[[ $(wc -l < inbox/Таски.md) -eq 6 ]]'

echo "== 3. повтор ничего не меняет =="
sum1="$(sha1sum inbox/Таски.md)"
out="$(python3 tools/inbox-close.py)"
check "идемпотентно" '[[ "$sum1" == "$(sha1sum inbox/Таски.md)" ]]'
check "«уже стояло: 2»" 'grep -q "уже стояло: 2" <<<"$out"'

echo; echo "прошло: $pass, упало: $fail"; [[ $fail -eq 0 ]]
