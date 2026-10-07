#!/usr/bin/env bash
# swift-format（Xcode 同梱）と swiftlint（mise で固定）で lint する。
# CI（ubuntu）では同じチェックを Docker イメージで実行している（.github/workflows/ci.yml）。
set -euo pipefail

cd "$(dirname "$0")/.."

xcrun swift-format lint --strict --recursive Mewbell MewbellTests
mise exec -- swiftlint lint --strict --quiet
