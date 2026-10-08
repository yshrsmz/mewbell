#!/usr/bin/env bash
# swift-format（Xcode 同梱）でソースを整形する。確認だけなら scripts/lint.sh を使う。
# 対象を変えるときは scripts/lint.sh と .github/workflows/ci.yml も合わせて直す。
set -euo pipefail

cd "$(dirname "$0")/.."

xcrun swift-format format --in-place --recursive Mewbell MewbellTests
