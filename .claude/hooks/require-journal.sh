#!/usr/bin/env bash
# PreToolUse-заслонка на Bash, только для этого проекта (Beepy / carapp228).
# Проверяет `git commit` по трём пунктам и блокирует его (exit 2), если хоть
# один не сошёлся. stderr возвращается агенту как причина отказа.
#
#   1. Запись в docs/JOURNAL.md. Правило «дополнять после каждой заметной
#      задачи» записано в самом журнале и в CLAUDE.md — и всё равно
#      пропускается: контекст сессии кончается раньше, чем доходят руки.
#      Коммит — единственный момент, где проверка и дешёвая, и однозначная.
#
#   2. Членство .swift-файлов в project.pbxproj. Проект ведётся вручную, файл
#      прописывается в четырёх местах, и расхождение уже случилось:
#      `AppMVP/Features/Issues/IssuesScreen 2.swift` лежит в гите 25 КБ и не
#      компилируется вовсе. Проверяются только файлы этого коммита — отвечаешь
#      за то, что трогал. Разовый обход всего репозитория: `--audit`.
#
#   3. `plutil -lint` на project.pbxproj. Ручная правка ломает plist молча,
#      а Xcode на битом проекте падает сообщениями, которые не намекают
#      на причину.
#
# Падает открытым по устройству: нет jq, не репозиторий, нет pbxproj, ошибка
# git — exit 0. Сломанный сторож не должен заклинить все вызовы Bash.
set -uo pipefail

journal="docs/JOURNAL.md"
pbx="Wheelly.xcodeproj/project.pbxproj"
src_root="AppMVP"

# Файл прописан в фазе компиляции? В pbxproj это комментарий вида
# `/* Theme.swift in Sources */` — он есть и у PBXBuildFile, и в самой фазе.
in_sources() { grep -qF "/* $1 in Sources */" "$pbx"; }

# Все .swift, которые проект собирает.
sources_list() {
  grep -o '/\* [^*]*\.swift in Sources \*/' "$pbx" \
    | sed 's|/\* ||; s| in Sources \*/||' | sort -u
}

# --- Режим ревизии: обход всего репозитория, запускается руками ---------------
if [[ "${1:-}" == "--audit" ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "не репозиторий"; exit 1; }
  cd "$root" || exit 1
  [[ -f "$pbx" ]] || { echo "нет $pbx"; exit 1; }
  bad=0
  while IFS= read -r file; do
    base="${file##*/}"
    in_sources "$base" || { echo "НЕ СОБИРАЕТСЯ: $file"; bad=1; }
  done < <(find "$src_root" -name '*.swift' | sort)
  while IFS= read -r base; do
    [[ -z "$base" ]] && continue
    find "$src_root" -name "$base" -print -quit | grep -q . \
      || { echo "НЕТ ФАЙЛА, а в проекте есть: $base"; bad=1; }
  done < <(sources_list)
  plutil -lint "$pbx" >/dev/null 2>&1 || { echo "БИТЫЙ plist: $pbx"; bad=1; }
  [[ $bad -eq 0 ]] && echo "Ревизия чистая: $(find "$src_root" -name '*.swift' | wc -l | tr -d ' ') файлов, все в проекте, plist цел."
  exit $bad
fi

# --- Режим заслонки ----------------------------------------------------------
payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)" || exit 0
[[ -z "$cmd" ]] && exit 0

# `git commit`, в том числе внутри цепочки `git add -A && git commit -m x`.
# Между двумя словами перечислены только собственные флаги git — иначе
# `git log --grep commit` читался бы как коммит.
gflag='(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir[=[:space:]][^[:space:]]+|--work-tree[=[:space:]][^[:space:]]+|--no-pager|--paginate|-P)'
is_commit="(^|[;&|(\`[:space:]])git([[:space:]]+${gflag})*[[:space:]]+commit([[:space:]]|$)"
[[ "$cmd" =~ $is_commit ]] || exit 0

# --amend переписывает коммит, чью запись уже оценили; --dry-run ничего не пишет.
[[ "$cmd" =~ (^|[[:space:]])--amend([[:space:]]|$) ]] && exit 0
[[ "$cmd" =~ (^|[[:space:]])--dry-run([[:space:]]|$) ]] && exit 0

cwd="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null)"
[[ -n "$cwd" && -d "$cwd" ]] && cd "$cwd" 2>/dev/null
# `git -C dir commit` коммитит в dir — значит, смотреть надо туда.
if [[ "$cmd" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  target="${BASH_REMATCH[1]//\"/}"
  [[ -d "$target" ]] && cd "$target" 2>/dev/null
fi
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -z "$root" ]] && exit 0
cd "$root" || exit 0

staged="$(git diff --cached --name-only 2>/dev/null)" || exit 0
deleted="$(git diff --cached --name-only --diff-filter=D 2>/dev/null)"
# `commit -a` / `-am` подметает изменения отслеживаемых файлов мимо стейджа.
if [[ "$cmd" =~ (^|[[:space:]])(--all([[:space:]]|=|$)|-[a-zA-Z]*a[a-zA-Z]*([[:space:]]|$)) ]]; then
  staged="$staged
$(git diff --name-only 2>/dev/null)"
  deleted="$deleted
$(git diff --name-only --diff-filter=D 2>/dev/null)"
fi
changed="$(printf '%s\n' "$staged" | grep -v '^[[:space:]]*$' | sort -u)"
deleted="$(printf '%s\n' "$deleted" | grep -v '^[[:space:]]*$' | sort -u)"

# Коммитить нечего — git скажет это сам, добавлять нечего.
[[ -z "$changed" ]] && exit 0

problems=""

# --- 1. Запись в журнале -----------------------------------------------------
# Код — это AppMVP/, tools/ и сам проект. Коммит одних доков не требует записи:
# он часто и есть эта запись.
code_changed="$(printf '%s\n' "$changed" | grep -E "^($src_root/|tools/|.*\.pbxproj$)" | head -1)"
if [[ -n "$code_changed" ]]; then
  if ! printf '%s\n' "$changed" | grep -qx "$journal"; then
    # Запись за сегодня уже закоммичена: CLAUDE.md просит коммиты размером
    # с шаг, но запись — одну на кусок работы, поэтому следующие шаги того же
    # дня не блокируются. Ключ — дата записи, а не «прошлый коммит трогал файл»:
    # иначе первый коммит новой работы получал бы пропуск даром.
    today="$(date +%F)"
    if ! git show "HEAD:$journal" 2>/dev/null | grep -q "^###[[:space:]]*${today}"; then
      problems="$problems
• Коммит меняет код, но записи в $journal нет, и записи с датой $today
  в HEAD тоже нет. Нужна одна запись на кусок работы: что изменилось и в
  каких файлах, зачем, как проверено (точная команда и настоящий вывод —
  или прямо «не проверено»), что осталось. Заголовок вида «### $today — тема»,
  новое сверху, в раздел «Хроника» в начале файла."
    fi
  fi
fi

# --- 2. Членство в project.pbxproj -------------------------------------------
if [[ -f "$pbx" ]]; then
  # Удаляемые файлы сюда не идут: коммит, который сносит мёртвый .swift, — это
  # уборка, а не пропущенная регистрация. Требовать «пропиши его в проект» от
  # того, кто его удаляет, значит блокировать ровно ту работу, ради которой
  # заслонка и написана. `git rm --cached` оставляет файл на диске, поэтому
  # одной проверки на существование мало — вычитаем список удалённых явно.
  missing=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    [[ -f "$file" ]] || continue
    printf '%s\n' "$deleted" | grep -qxF "$file" && continue
    base="${file##*/}"
    in_sources "$base" || missing="$missing
  – $file"
  done < <(printf '%s\n' "$changed" | grep -E "^${src_root}/.*\.swift$")

  if [[ -n "$missing" ]]; then
    problems="$problems
• Эти .swift лежат в коммите, но проект их не собирает:$missing
  Файл прописывается в $pbx в четырёх местах: PBXBuildFile,
  PBXFileReference, children своей группы и PBXSourcesBuildPhase.
  Свободный префикс ID проверить грепом, а не угадать — совпадение
  с чужим объектом Xcode ловит падением с «unrecognized selector».
  Если файл лишний — удалить его, а не оставлять мёртвым в гите."
  fi

  stale=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    base="${file##*/}"
    if in_sources "$base"; then stale="$stale
  – $base"; fi
  done < <(printf '%s\n' "$deleted" | grep -E "^${src_root}/.*\.swift$")

  if [[ -n "$stale" ]]; then
    problems="$problems
• Файл удалён, а ссылка в $pbx осталась:$stale
  Снять её из тех же четырёх мест, иначе сборка упадёт на отсутствующем файле."
  fi

  if ! plutil -lint "$pbx" >/dev/null 2>&1; then
    problems="$problems
• $pbx не проходит plutil -lint — ручная правка сломала plist.
  Точная причина: plutil -lint $pbx"
  fi
fi

[[ -z "$problems" ]] && exit 0

echo "Коммит остановлен.
$problems

Разовый обход всего репозитория: .claude/hooks/require-journal.sh --audit
Если пункт неприменим — пустой коммит, чистый откат, фиксап вместо --amend —
скажи мне об этом, не обходи заслонку молча." >&2
exit 2
