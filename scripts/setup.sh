#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> AppMVP setup"

if [[ ! -f Config.plist ]]; then
  cp Config.example.plist Config.plist
  echo "Created Config.plist from example — add Supabase keys."
fi

if ! command -v xcodegen &>/dev/null; then
  echo "XcodeGen not found. Install: brew install xcodegen"
  echo "Or open project after: xcodegen generate"
  exit 1
fi

xcodegen generate
echo "Generated AppMVP.xcodeproj"

if [[ -d /Applications/Xcode.app ]]; then
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer 2>/dev/null || true
  echo "Open in Xcode: open AppMVP.xcodeproj"
else
  echo "Install Xcode from App Store, then: open AppMVP.xcodeproj"
fi
