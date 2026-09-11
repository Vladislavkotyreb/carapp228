#!/usr/bin/env bash
# Переносит заметки из хранилища Obsidian в inbox/ репозитория и обратно.
#
# Зачем. Утренний разбор идёт в облаке, а облако видит только GitHub — телефона
# оно не видит. Клонировать сам репозиторий в Obsidian на iPhone нельзя: 85 МБ
# истории и 71 МБ картинок в AppMVP, плагин Git на мобиле это не вывезет.
# Поэтому доставкой занимается мак, где хранилище и так лежит после
# синхронизации с телефоном.
#
# Источник правды — репозиторий. Хранилище получает его зеркалом, включая
# done/ и reports/: иначе разобранная заметка вернулась бы из хранилища
# обратно в очередь и разбиралась каждое утро заново.
#
# Установка — раз:
#   chmod +x tools/inbox-sync.sh
#   cp tools/dev.beepy.inbox-sync.plist ~/Library/LaunchAgents/
#   launchctl load ~/Library/LaunchAgents/dev.beepy.inbox-sync.plist
#
# Разовый прогон руками: tools/inbox-sync.sh
set -euo pipefail

# --- Заполнить под себя ------------------------------------------------------
# Папка репозитория.
REPO="$HOME/Desktop/ios-app"
# Папка внутри хранилища Obsidian, куда пишутся заметки. Для хранилища в iCloud
# путь обычно такой; имя хранилища подставить своё.
VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/тестовая мобила/beepy"
# Ветка, в которую уезжают заметки.
BRANCH="claude/epic-darwin-axs48i"
# -----------------------------------------------------------------------------

log() { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }

[[ -d "$REPO/.git" ]] || { log "нет репозитория: $REPO"; exit 1; }
[[ -d "$VAULT" ]] || { log "нет папки хранилища: $VAULT"; exit 1; }
cd "$REPO"

# Незакоммиченные правки в коде — не наше дело, но и коммитить их скопом нельзя:
# ниже добавляется только inbox/, явным путём.
git fetch origin "$BRANCH" --quiet
git checkout "$BRANCH" --quiet
git pull --rebase origin "$BRANCH" --quiet || { log "pull не прошёл, чиню руками"; exit 1; }

mkdir -p inbox/tasks inbox/bugs inbox/done inbox/reports inbox/attachments

# 1. Хранилище → репозиторий. Без --delete: удалять заметки может только
#    разбор, переносом в done/. Пропавший в хранилище файл — чаще промах
#    пальцем по экрану, чем решение.
rsync -a --exclude '.obsidian' --exclude '.DS_Store' "$VAULT/" inbox/

if ! git diff --quiet -- inbox || [[ -n "$(git status --porcelain inbox)" ]]; then
  git add inbox
  git commit -q -m "inbox: заметки из Obsidian, $(date '+%F %H:%M')" \
    -m "Перенесено tools/inbox-sync.sh с мака: облачный разбор видит только GitHub."
  git push -q origin "$BRANCH"
  log "отправлено в $BRANCH"
else
  log "новых заметок нет"
fi

# 2. Репозиторий → хранилище, зеркалом. Здесь --delete нужен: разобранная
#    заметка уехала в done/, и её копия в tasks/ обязана исчезнуть, иначе
#    завтрашний разбор возьмёт её снова.
rsync -a --delete --exclude '.obsidian' --exclude '.DS_Store' inbox/ "$VAULT/"
log "хранилище обновлено"
