#!/usr/bin/env bash
# Debug ビルドして起動する。この repo でビルドした Mewbell が起動中なら先に終了させる。
set -euo pipefail

cd "$(dirname "$0")/.."

bash scripts/build.sh Debug
# 起動中の Mewbell（build/ 配下のもの）を終了させ、終わるのを待ってから開く
app_binary="$PWD/build/Debug/Mewbell.app/Contents/MacOS/Mewbell"
if pkill -f "^$app_binary" 2>/dev/null; then
  for _ in $(seq 1 50); do
    pgrep -f "^$app_binary" >/dev/null || break
    sleep 0.1
  done
fi
open build/Debug/Mewbell.app
