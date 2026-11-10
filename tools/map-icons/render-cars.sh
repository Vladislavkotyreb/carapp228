#!/bin/bash
# Rebuild all native SceneKit map miniatures; no API calls or external keys.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
render_tmp="$(mktemp -d "${TMPDIR:-/tmp}/beepy-map-cars.XXXXXX")"
trap 'rm -rf "$render_tmp"' EXIT
python3 - "$script_dir" "$render_tmp/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1])
shared = (source / 'render.swift').read_text().split('// MARK: - Рендер')[0]
Path(sys.argv[2]).write_text(shared + (source / 'cars.swift').read_text())
PY
swiftc -O "$render_tmp/main.swift" -o "$render_tmp/render"
"$render_tmp/render" "${1:-$repo_dir/AppMVP/Resources/MapCars}" 384 "$script_dir/cars.json"

# Preserve the detailed Discovery instead of the procedural placeholder.
sips -z 384 384 "$script_dir/overrides/giraffe-discovery-source.png" --out "${1:-$repo_dir/AppMVP/Resources/MapCars}/giraffe-discovery.png" >/dev/null
