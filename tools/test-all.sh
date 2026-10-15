#!/usr/bin/env bash
# Весь прогон перед выкладкой одной командой. Падает на первом красном.
#
#   tools/test-all.sh                 # всё, симулятор — первый загруженный iPhone
#   SIM=<UDID> tools/test-all.sh      # конкретный симулятор
#   SKIP_XCODE=1 tools/test-all.sh    # без Xcode: только то, что гоняется swiftc и node
#
# Что внутри и зачем — docs/APPSTORE.md, раздел «Тесты».
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

step() { printf '\n== %s\n' "$1"; }

step "Чистый слой (Core/Pure)"
./tools/run-pure-checks.sh | tail -1

step "Типографика строк интерфейса"
python3 tools/check-typography.py | tail -1

step "project.pbxproj"
python3 tools/check-project.py | tail -1

step "Лицензии в бандле совпадают с docs/licenses"
python3 tools/build-licenses.py --check

step "Сервер"
npm --prefix server test 2>&1 | grep -E "^ℹ (tests|pass|fail)"

if [[ "${SKIP_XCODE:-}" == "1" ]]; then
  echo; echo "XCTest пропущен (SKIP_XCODE=1)"
  exit 0
fi

step "XCTest: юнит и UI на симуляторе"
sim="${SIM:-$(xcrun simctl list devices booted | grep -m1 -oE 'iPhone[^(]*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}' || true)}"
if [[ -z "$sim" ]]; then
  echo "нет загруженного симулятора iPhone: xcrun simctl boot <UDID> или SIM=<UDID>" >&2
  exit 1
fi
# DerivedData — вне папки проекта: Рабочий стол в iCloud, см. CLAUDE.md.
xcodebuild -project Beepy.xcodeproj -scheme AppMVP -sdk iphonesimulator \
  -destination "id=$sim" -derivedDataPath ~/Library/Developer/Xcode/DerivedData/beepy \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  test 2>&1 | grep -E "Test Case.*(passed|failed)|error: |TEST (SUCCEEDED|FAILED)" \
  | sed -E "s/^Test Case '-\[(.*)\]' (passed|failed).*/  \2  \1/"
test "${PIPESTATUS[0]}" -eq 0
