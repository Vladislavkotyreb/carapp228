#!/usr/bin/env bash
# Сгенерированные кадры → каталог приложения.
#
# Берёт PNG из ~/beepy-catalog/raw для каждого слага из списков генерации
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
# Папка кадров: новая, а если её ещё нет и осталась старая (до
# переименования в Beepy 2026-09-22) — старая, чтобы не потерять сырьё.
CATALOG_HOME="$HOME/beepy-catalog"
[[ ! -d "$CATALOG_HOME" && -d "$HOME/canary-catalog" ]] && CATALOG_HOME="$HOME/canary-catalog"
# Кадры v3 (рецепт прода) лежат в своей папке `v3`; если она есть, импорт
# берёт их. В `raw` на маке остались PNG первой партии с чужими машинами —
# импорт оттуда по умолчанию вернул бы их в каталог, как 2026-09-17.
if [[ -n "${BEEPY_RAW:-}" ]]; then RAW="$BEEPY_RAW"
elif [[ -d "$CATALOG_HOME/v3" ]]; then RAW="$CATALOG_HOME/v3"
else RAW="$CATALOG_HOME/raw"; fi
DEST="$REPO/AppMVP/Resources/CarCatalog"
echo "кадры из: $RAW"

# HEIC — тем же `sips` с качеством 80, что и 76 кадров прода. Без мака
# (облачная сессия) — pillow-heif с тем же качеством: кодек другой, вид тот
# же. Питон с pillow-heif — в BEEPY_PY, если он не системный.
PY="${BEEPY_PY:-python3}"
if command -v sips >/dev/null; then
  to_heic() { sips -s format heic -s formatOptions 80 "$1" --out "$2" >/dev/null; }
elif "$PY" -c "import pillow_heif" 2>/dev/null; then
  to_heic() {
    "$PY" -I -c 'import sys, pillow_heif; from PIL import Image
pillow_heif.register_heif_opener()
Image.open(sys.argv[1]).convert("RGB").save(sys.argv[2], format="HEIF", quality=80)' "$1" "$2"
  }
else
  echo "нет ни sips (macOS), ни pillow-heif в $PY — HEIC собрать нечем" >&2
  exit 1
fi

if [[ $# -gt 0 ]]; then
  slugs=("$@")
else
  slugs=()
  while IFS= read -r s; do slugs+=("$s"); done < <(
    python3 - "$REPO" "$FORCE" <<'PY'
import json, os, sys
root = sys.argv[1]
# С --force без списка — только вторая очередь: 75 кадров прода
# (catalog_cars.json) перезаписываются лишь поимённо, решением человека.
names = ("catalog_cars_next.json",) if sys.argv[2] == "1" else \
        ("catalog_cars.json", "catalog_cars_next.json")
for name in names:
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
  to_heic "$src" "$dst"
  echo "  + $slug.heic ($(du -k "$dst" | cut -f1) КБ)"
  made=$((made+1))
done

echo "импортировано: $made, уже было: $kept, без PNG: ${#missing[@]}"
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "  не сгенерированы: ${missing[*]}"
fi
echo
python3 "$REPO/tools/check-catalog.py" || true
