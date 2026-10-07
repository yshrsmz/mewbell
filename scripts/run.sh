#!/usr/bin/env bash
# Debug ビルドして起動する。起動中の Mewbell があれば先に終了させる。
set -euo pipefail

cd "$(dirname "$0")/.."

bash scripts/build.sh Debug
pkill -x Mewbell || true
open build/Debug/Mewbell.app
