#!/usr/bin/env bash
# Mewbell をビルドし、build/<Configuration>/Mewbell.app に置く。
# 使い方: bash scripts/build.sh [Debug|Release]
set -euo pipefail

cd "$(dirname "$0")/.."

configuration="${1:-Debug}"
derived_data="build/DerivedData"

xcodebuild \
  -project Mewbell.xcodeproj \
  -scheme Mewbell \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data" \
  build

mkdir -p "build/$configuration"
rm -rf "build/$configuration/Mewbell.app"
cp -R "$derived_data/Build/Products/$configuration/Mewbell.app" "build/$configuration/"
echo "build/$configuration/Mewbell.app"
