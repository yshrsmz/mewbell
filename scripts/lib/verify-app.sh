#!/usr/bin/env bash
# 配布する Mewbell.app の署名・entitlement・Info.plist を検査する（openspec/specs/distribution）。
# 使い方: source scripts/lib/verify-app.sh; verify_app <path-to-.app> <X.Y.Z>
# 満たさない項目をすべて表示し、1 つでもあれば 1 を返す。
# 禁止の entitlement は .claude/rules/security.md の「アプリとビルドの設定」に合わせる。
# ad-hoc 署名は Gatekeeper の評価（spctl --assess）を通らないので、ここでは確かめない。

readonly VERIFY_APP_BUNDLE_ID="com.codingfeline.mewbell"
readonly VERIFY_APP_FORBIDDEN_ENTITLEMENTS=(
  com.apple.security.get-task-allow
  com.apple.security.cs.disable-library-validation
  com.apple.security.cs.allow-dyld-environment-variables
  com.apple.security.cs.allow-unsigned-executable-memory
  com.apple.security.cs.allow-jit
  com.apple.security.cs.disable-executable-page-protection
)
readonly VERIFY_APP_REQUIRED_ARCHS=(arm64 x86_64)

verify_app() {
  local app="$1" version="$2"
  local info="$app/Contents/Info.plist"
  local failures=()

  if [[ ! -d "$app" || ! -f "$info" ]]; then
    echo "verify_app: $app は .app ではありません" >&2
    return 1
  fi

  if ! codesign --verify --deep --strict "$app" 2>/dev/null; then
    failures+=("署名の検証（codesign --verify --deep --strict）に失敗しました")
  fi

  local flags
  # 署名が無いと codesign が失敗するが、set -e の呼び出し元でもここで止めずに、まとめて表示する
  flags="$(codesign -dv "$app" 2>&1 | sed -n 's/.*flags=0x[0-9a-f]*(\([^)]*\)).*/\1/p' || true)"
  if [[ ",$flags," != *",runtime,"* ]]; then
    failures+=("Hardened Runtime（runtime）が無効です（flags: ${flags:-なし}）")
  fi

  local entitlements key
  entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)"
  for key in "${VERIFY_APP_FORBIDDEN_ENTITLEMENTS[@]}"; do
    if [[ "$entitlements" == *"<key>$key</key>"* ]]; then
      failures+=("禁止の entitlement があります: $key")
    fi
  done

  if plutil -extract NSAppTransportSecurity raw "$info" >/dev/null 2>&1; then
    failures+=("Info.plist に ATS の設定（NSAppTransportSecurity）があります")
  fi

  local actual
  actual="$(plutil -extract CFBundleIdentifier raw "$info" 2>/dev/null || true)"
  if [[ "$actual" != "$VERIFY_APP_BUNDLE_ID" ]]; then
    failures+=("CFBundleIdentifier が $VERIFY_APP_BUNDLE_ID ではありません: ${actual:-なし}")
  fi
  for key in CFBundleShortVersionString CFBundleVersion; do
    actual="$(plutil -extract "$key" raw "$info" 2>/dev/null || true)"
    if [[ "$actual" != "$version" ]]; then
      failures+=("$key が $version ではありません: ${actual:-なし}")
    fi
  done

  local executable archs arch
  executable="$(plutil -extract CFBundleExecutable raw "$info" 2>/dev/null || true)"
  archs="$(lipo -archs "$app/Contents/MacOS/$executable" 2>/dev/null || true)"
  for arch in "${VERIFY_APP_REQUIRED_ARCHS[@]}"; do
    if [[ " $archs " != *" $arch "* ]]; then
      failures+=("実行ファイルに $arch がありません（archs: ${archs:-なし}）")
    fi
  done

  if ((${#failures[@]} > 0)); then
    local failure
    for failure in "${failures[@]}"; do
      echo "verify_app: $failure" >&2
    done
    return 1
  fi
  echo "verify_app: $app を検査しました（${version}）"
}
