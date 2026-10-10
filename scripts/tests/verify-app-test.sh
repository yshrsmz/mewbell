#!/usr/bin/env bash
# scripts/lib/verify-app.sh の verify_app が、正常な .app を通し、約束を破った .app を落とすことを確かめる。
# 小さな C の実行ファイルで偽の .app を組み、ad-hoc 署名して使う。codesign が要るので macOS でだけ動く。
# 使い方: bash scripts/tests/verify-app-test.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
# shellcheck source=scripts/lib/verify-app.sh
source scripts/lib/verify-app.sh

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

printf 'int main(void) { return 0; }\n' >"$work/main.c"
clang -arch arm64 -arch x86_64 -o "$work/universal" "$work/main.c"
clang -arch arm64 -o "$work/arm64-only" "$work/main.c"

cat >"$work/get-task-allow.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.get-task-allow</key>
  <true/>
</dict>
</plist>
EOF

# make_app <name> [binary] [bundle-id] [version] → $work/<name>/Mewbell.app を作る（署名はしない）
make_app() {
  local name="$1" binary="${2:-universal}" bundle_id="${3:-com.codingfeline.mewbell}" version="${4:-1.2.3}"
  local app="$work/$name/Mewbell.app"
  mkdir -p "$app/Contents/MacOS"
  cp "$work/$binary" "$app/Contents/MacOS/Mewbell"
  cat >"$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Mewbell</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$version</string>
</dict>
</plist>
EOF
  echo "$app"
}

sign() {
  codesign --force --sign - "$@" 2>/dev/null
}

failures=0

# expect <pass|fail> <description> <app> [version] [expected-message]
expect() {
  local want="$1" description="$2" app="$3" version="${4:-1.2.3}" message="${5:-}"
  local output rc=0
  output="$(verify_app "$app" "$version" 2>&1)" || rc=$?
  if [[ "$want" == pass && $rc -eq 0 ]] || [[ "$want" == fail && $rc -ne 0 && "$output" == *"$message"* ]]; then
    echo "ok: $description"
  else
    echo "NG: $description（rc=$rc）" >&2
    echo "$output" | sed 's/^/    /' >&2
    failures=$((failures + 1))
  fi
}

app="$(make_app valid)"
sign -o runtime "$app"
expect pass "正常な .app は通る" "$app"

app="$(make_app get-task-allow)"
sign -o runtime --entitlements "$work/get-task-allow.entitlements" "$app"
expect fail "get-task-allow 付きは落ちる" "$app" 1.2.3 "com.apple.security.get-task-allow"

app="$(make_app no-runtime)"
sign "$app"
expect fail "Hardened Runtime が無いと落ちる" "$app" 1.2.3 "Hardened Runtime"

app="$(make_app ats)"
plutil -insert NSAppTransportSecurity -json '{"NSAllowsArbitraryLoads":true}' "$app/Contents/Info.plist"
sign -o runtime "$app"
expect fail "ATS の例外があると落ちる" "$app" 1.2.3 "NSAppTransportSecurity"

app="$(make_app single-arch arm64-only)"
sign -o runtime "$app"
expect fail "arm64 だけだと落ちる" "$app" 1.2.3 "x86_64"

app="$(make_app bundle-id universal com.example.other)"
sign -o runtime "$app"
expect fail "CFBundleIdentifier が違うと落ちる" "$app" 1.2.3 "CFBundleIdentifier"

app="$(make_app version)"
sign -o runtime "$app"
expect fail "バージョンが違うと落ちる" "$app" 1.2.4 "CFBundleShortVersionString"

app="$(make_app tampered)"
sign -o runtime "$app"
printf 'tampered' >>"$app/Contents/MacOS/Mewbell"
expect fail "署名の後に書き換えると落ちる" "$app" 1.2.3 "codesign --verify"

if ((failures > 0)); then
  echo "$failures 件が期待どおりではありませんでした" >&2
  exit 1
fi
echo "verify_app のテストがすべて通りました"
