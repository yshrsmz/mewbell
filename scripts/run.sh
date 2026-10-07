#!/usr/bin/env bash
# Debug ビルドして起動する。
# 二重起動防止があるため、どこかで Mewbell が動いていると新しいビルドがすぐ終了してしまう。
# 古いビルドのまま確認しないよう、場所を問わず起動中の Mewbell を終了させてから開く。
set -euo pipefail

cd "$(dirname "$0")/.."

bash scripts/build.sh Debug

if pkill -x Mewbell 2>/dev/null; then
  for _ in $(seq 1 50); do
    pgrep -x Mewbell >/dev/null || break
    sleep 0.1
  done
  if pgrep -x Mewbell >/dev/null; then
    echo "起動中の Mewbell が終了しませんでした。手動で終了してから再実行してください。" >&2
    exit 1
  fi
fi

open build/Debug/Mewbell.app
