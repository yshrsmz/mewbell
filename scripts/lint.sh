#!/usr/bin/env bash
# swift-format（Xcode 同梱）と swiftlint（mise で固定）で lint し、docs/architecture.md を検査する。
# CI（ubuntu）では同じ引数で Docker イメージのツールを実行している（.github/workflows/ci.yml）。
# swift-format のバージョンは手元（Xcode 同梱）と CI（swift イメージ）で異なる（design.md D5）。
set -euo pipefail

cd "$(dirname "$0")/.."

xcrun swift-format lint --strict --recursive Mewbell MewbellTests
mise exec -- swiftlint lint --strict --quiet
bash scripts/check-architecture.sh
