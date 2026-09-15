#!/usr/bin/env bash
# Сгенерированные кадры → каталог приложения.
#
# Берёт PNG из ~/canary-catalog/raw для каждого слага из списков генерации
# и кладёт HEIC в AppMVP/Resources/CarCatalog тем же `sips` с качеством 80,
# которым сделаны остальные кадры. Уже лежащие HEIC не перезаписывает:
# перегенерировать кадр — удалить старый HEIC руками, чтобы это было
# решением, а не побочным эффектом.
#
# Папка каталога подключена в проект одной folder reference, поэтому
# project.pbxproj трогать не надо: новый файл сам оказывается в бандле.
#
# После импорта — python3 tools/check-catalog.py: правила и файлы должны
# сойтись, иначе превью покажет пустую подложку или кадр будет недостижим.
#
#   tools/catalog_import.sh              # все слаги из обоих списков
#   tools/catalog_import.sh kia-soul …   # только названные
#   tools/catalog_import.sh --force …    # перезаписать готовые HEIC
set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force" ]]; then FORCE=1; shift; fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="${CANARY_RAW:-$HOME/canary-catalog/raw}"
DEST="$REPO/AppMVP/Resources/CarCatalog"

if ! command -v sips >/dev/null; then
  echo "нет sips — это macOS-инструмент, импорт делается на маке" >&2
  exit 1
fi

if [[ $# -gt 0 ]]; then
  slugs=("$@")
else
  slugs=()
  while IFS= read -r s; do slugs+=("$s"); done < <(
    python3 - "$REPO" <<'PY'
import json, os, sys
root = sys.argv[1]
for name in ("catalog_cars.json", "catalog_cars_next.json"):
    path = os.path.join(root, "tools", name)
    if os.path.exists(path):
        for car in json.load(open(path, encoding="utf-8")):
            print(car["slug"])
PY
  )
fi

made=0; kept=0; missing=()
for slug in "${slugs[@]}"; do
  src="$RAW/$slug.png"; dst="$DEST/$slug.heic"
  if [[ -f "$dst" && $FORCE -eq 0 ]]; then kept=$((kept+1)); continue; fi
  if [[ ! -f "$src" ]]; then missing+=("$slug"); continue; fi
  sips -s format heic -s formatOptions 80 "$src" --out "$dst" >/dev/null
  echo "  + $slug.heic ($(du -k "$dst" | cut -f1) КБ)"
  made=$((made+1))
done

echo "импортировано: $made, уже было: $kept, без PNG: ${#missing[@]}"
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "  не сгенерированы: ${missing[*]}"
fi
echo
python3 "$REPO/tools/check-catalog.py" || true
