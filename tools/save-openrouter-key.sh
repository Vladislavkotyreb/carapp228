#!/bin/zsh
# Сохраняет ключ OpenRouter для генерации каталога (tools/catalog_openrouter.py)
# в ~/.config/beepy/openrouter.env с правами 600 — вне репозитория (он
# публичный) и вне iCloud. Ключ вводится скрыто и в историю оболочки не попадает.
set -e
mkdir -p ~/.config/beepy
read -rs "key?Вставь ключ OpenRouter и нажми Enter: "
echo
[[ "$key" == sk-or-* ]] || { echo "Это не похоже на ключ OpenRouter (sk-or-…). Ничего не сохранено."; exit 1; }
printf 'OPENROUTER_API_KEY=%s\n' "$key" > ~/.config/beepy/openrouter.env
chmod 600 ~/.config/beepy/openrouter.env
unset key
echo "Сохранено в ~/.config/beepy/openrouter.env. Можно возвращаться в чат."
