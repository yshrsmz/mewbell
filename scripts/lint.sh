#!/usr/bin/env bash
# swift-format と swiftlint（mise で固定）で lint する。
# macOS では Xcode 同梱の swift-format、Linux（CI）では Swift ツールチェーン同梱の swift-format を使う。
set -euo pipefail

cd "$(dirname "$0")/.."

if command -v xcrun >/dev/null 2>&1; then
  swift_format=(xcrun swift-format)
else
  swift_format=(swift-format)
fi

"${swift_format[@]}" lint --strict --recursive Mewbell MewbellTests
mise exec -- swiftlint lint --strict --quiet
