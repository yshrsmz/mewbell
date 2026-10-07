#!/usr/bin/env bash
# swift-format（Xcode 同梱）と swiftlint（mise で固定）で lint する。
set -euo pipefail

cd "$(dirname "$0")/.."

xcrun swift-format lint --strict --recursive Mewbell MewbellTests
mise exec -- swiftlint lint --strict --quiet
