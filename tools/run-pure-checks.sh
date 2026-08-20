#!/usr/bin/env bash
# Собирает и прогоняет проверки чистого слоя `AppMVP/Core/Pure`.
#
# Xcode для этого не нужен — хватает swiftc из Command Line Tools, поэтому
# прогон доступен на любой машине с исходниками. Если файл из Core/Pure
# затащит SwiftUI, SwiftData или UIKit, сборка здесь упадёт: это и есть
# проверка границы слоя.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

xcrun swiftc -sdk "$sdk" -O \
  AppMVP/Core/Pure/*.swift \
  tools/pure-checks/main.swift \
  -o "$out/pure-checks"

"$out/pure-checks"
