#!/usr/bin/env bash
# 配布物（zip と SHA-256）を作る。リリースのワークフロー（.github/workflows/release.yml）と手元の両方で使う。
# Release ビルド → 検査 → zip → 展開した zip の検査 の順に進め、すべて通ったときだけ build/dist/<version>/ に置く。
# （build/release は大文字と小文字を区別しない APFS では build/Release と同じ場所になるので使わない）
# Release への添付・公開・tap への知らせはしない（それはワークフローが行う）。
# 使い方: bash scripts/package-release.sh X.Y.Z
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib/verify-app.sh
source scripts/lib/verify-app.sh

version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "使い方: bash scripts/package-release.sh X.Y.Z（X.Y.Z は 0 以上の整数 3 つ）" >&2
  exit 2
fi

# 警告をエラー扱いにする。リリースのワークフローの Release のビルドはこれで兼ねる
bash scripts/build.sh Release MEWBELL_WARNINGS_AS_ERRORS=YES
verify_app build/Release/Mewbell.app "$version"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

zip_name="Mewbell-$version.zip"
mkdir "$work/out"
# 拡張属性（ローカルの com.apple.provenance など）やリソースフォークは入れない。署名は _CodeSignature にあるので影響しない
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent build/Release/Mewbell.app "$work/out/$zip_name"
(cd "$work/out" && shasum -a 256 "$zip_name" >"$zip_name.sha256")

unexpected="$(zipinfo -1 "$work/out/$zip_name" | grep -v '^Mewbell\.app/' || true)"
if [[ -n "$unexpected" ]]; then
  echo "zip に Mewbell.app 以外のものが入っています:" >&2
  echo "$unexpected" >&2
  exit 1
fi
mkdir "$work/unzipped"
ditto -x -k "$work/out/$zip_name" "$work/unzipped"
verify_app "$work/unzipped/Mewbell.app" "$version"

destination="build/dist/$version"
rm -rf "$destination"
mkdir -p "$(dirname "$destination")"
mv "$work/out" "$destination"
echo "$destination/$zip_name"
cat "$destination/$zip_name.sha256"
