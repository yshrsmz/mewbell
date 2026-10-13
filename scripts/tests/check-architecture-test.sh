#!/usr/bin/env bash
# scripts/check-architecture.sh が、正しい形を通し、5 つの検査それぞれの漏れを見つけることを確かめる。
# 一時ディレクトリに偽のリポジトリを組んで検査する。macOS と ubuntu（CI）の両方で動く。
# 使い方: bash scripts/tests/check-architecture-test.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
check="$PWD/scripts/check-architecture.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0

# make_repo <名前> → 検査が通る偽のリポジトリを $work/<名前> に新しく組み、そのパスを返す
make_repo() {
  local repo="$work/$1"
  mkdir -p "$repo/docs" "$repo/.claude/rules" "$repo/.claude/skills/sample" "$repo/openspec/changes/archive/2026-01-01-add-sample" \
    "$repo/openspec/changes/add-current" "$repo/Mewbell/UI"
  cat >"$repo/docs/architecture.md" <<'EOF'
# 設計方針

## 原則

### A1. 一覧の行は値だけを受け取る

- **原則**: 行の View（`SampleRow`）は値とクロージャだけを受け取り、`Mewbell/UI/SampleRow.swift` に置く。
- **理由**: プレビューとテストで store を組まずに済み、どの操作が起きるかが引数で読めるようになる。
- **採らなかった案**:
  - 行ごとに `SampleViewModel` を置く: 状態を二重に持つ
- **適用外**: なし
- **根拠**: add-sample D1

### A2. 廃止（add-current）

- **廃止の理由**: A1 にまとめた

## 既知の逸脱

| 原則 | 場所 | 直す change |
| --- | --- | --- |
| A1 | `SampleRow` | fix-sample（仮） |
EOF
  printf '# Sample\n\n行の約束は A1 を見る。\n' >"$repo/CLAUDE.md"
  printf '# Rules\n\nレビューでは A1 を引く。\n' >"$repo/.claude/rules/review.md"
  printf -- '---\nname: sample\n---\n\n`A1` のように引く。\n' >"$repo/.claude/skills/sample/SKILL.md"
  printf 'rules:\n  design:\n    - 原則の ID（A1 など）を書く\n' >"$repo/openspec/config.yaml"
  printf 'custom_rules:\n  sample:\n    message: "値だけを受け取る（A1）"\n' >"$repo/.swiftlint.yml"
  printf '# Design\n\n### D1. 前の形（A2）\n' >"$repo/openspec/changes/archive/2026-01-01-add-sample/design.md"
  printf '# Design\n\n### D1. 行（A1）\n' >"$repo/openspec/changes/add-current/design.md"
  printf 'struct SampleRow {\n    let title: String\n}\n' >"$repo/Mewbell/UI/SampleRow.swift"
  echo "$repo"
}

# expect_pass <名前> <リポジトリ>
expect_pass() {
  if bash "$check" "$2" >"$work/out" 2>&1; then
    echo "ok: $1"
  else
    echo "NG: $1（通るはずが落ちた）" >&2
    sed 's/^/    /' "$work/out" >&2
    failures=$((failures + 1))
  fi
}

# expect_fail <名前> <リポジトリ> <出力に含まれるべき文字列>...
expect_fail() {
  local name="$1" repo="$2"
  shift 2
  if bash "$check" "$repo" >"$work/out" 2>&1; then
    echo "NG: $name（落ちるはずが通った）" >&2
    failures=$((failures + 1))
    return
  fi
  local want
  for want in "$@"; do
    if ! grep -qF -- "$want" "$work/out"; then
      echo "NG: $name（出力に「$want」が無い）" >&2
      sed 's/^/    /' "$work/out" >&2
      failures=$((failures + 1))
      return
    fi
  done
  echo "ok: $name"
}

# 書き換え。BSD と GNU の sed -i の違いを避けるため、一時ファイルを経由する
replace() {
  local file="$1" from="$2" to="$3"
  awk -v from="$from" -v to="$to" '{ i = index($0, from); if (i) $0 = substr($0, 1, i - 1) to substr($0, i + length(from)); print }' \
    "$file" >"$file.tmp"
  mv "$file.tmp" "$file"
}

# --- 正しい形 ---
repo="$(make_repo valid)"
expect_pass "正しい形は通る（廃止の原則は 5 項目が無くてよく、archive からの参照も許す）" "$repo"

# --- 書式 ---
repo="$(make_repo heading)"
replace "$repo/docs/architecture.md" "### A1. " "### 1. "
expect_fail "見出しの形が違う" "$repo" "[書式]" "docs/architecture.md:5"

repo="$(make_repo duplicate-id)"
replace "$repo/docs/architecture.md" "### A2. 廃止" "### A1. 廃止"
expect_fail "ID が重複している" "$repo" "[書式]" "ID A1 が重複"

repo="$(make_repo missing-label)"
replace "$repo/docs/architecture.md" "- **適用外**: なし" ""
expect_fail "項目が欠けている" "$repo" "[書式]" "**適用外**"

repo="$(make_repo retired-reason)"
replace "$repo/docs/architecture.md" "- **廃止の理由**: A1 にまとめた" ""
expect_fail "廃止の理由が無い" "$repo" "[書式]" "廃止の理由"

# --- ID の参照 ---
repo="$(make_repo unknown-id)"
printf '原則 A9 を見る。\n' >>"$repo/CLAUDE.md"
expect_fail "無い ID を引いている" "$repo" "[ID の参照]" "CLAUDE.md:4" "A9"

repo="$(make_repo retired-reference)"
printf '原則 A2 を見る。\n' >>"$repo/.claude/rules/review.md"
expect_fail "archive でない文書が廃止した原則を引いている" "$repo" "[ID の参照]" ".claude/rules/review.md" "A2 は廃止"

repo="$(make_repo retired-lint)"
replace "$repo/.swiftlint.yml" "（A1）" "（A2）"
expect_fail "lint の規則が廃止した原則を引いている" "$repo" "[ID の参照]" ".swiftlint.yml"

repo="$(make_repo adjacent-ids)"
printf '原則 A1・A9 を見る。\n' >>"$repo/CLAUDE.md"
expect_fail "1 行の 2 つ目の ID も確かめる" "$repo" "[ID の参照]" "CLAUDE.md:4" "A9"

repo="$(make_repo proposal-reference)"
printf '# Proposal\n\nA9 を足す。\n' >"$repo/openspec/changes/add-current/proposal.md"
expect_fail "proposal.md の参照も確かめる" "$repo" "[ID の参照]" "openspec/changes/add-current/proposal.md:3"

repo="$(make_repo retiring-change)"
printf '\n### D2. A2 を廃止する\n' >>"$repo/openspec/changes/add-current/design.md"
expect_pass "原則を廃止した change の文書は、廃止した ID を引いてよい" "$repo"

repo="$(make_repo retired-other-change)"
mkdir -p "$repo/openspec/changes/add-other"
printf '# Design\n\n### D1. A2 に従う\n' >"$repo/openspec/changes/add-other/design.md"
expect_fail "ほかの change の文書は、廃止した ID を引けない" "$repo" "[ID の参照]" "openspec/changes/add-other/design.md" "A2 は廃止"

# --- 根拠の change ---
repo="$(make_repo missing-change)"
replace "$repo/docs/architecture.md" "add-sample D1" "add-missing D1"
expect_fail "根拠の change が無い" "$repo" "[根拠の change]" "add-missing"

# --- コードの名前 ---
repo="$(make_repo missing-type)"
replace "$repo/Mewbell/UI/SampleRow.swift" "struct SampleRow" "struct RenamedRow"
mv "$repo/Mewbell/UI/SampleRow.swift" "$repo/Mewbell/UI/RenamedRow.swift"
expect_fail "型とパスがコードに無い" "$repo" "[コードの名前]" "SampleRow がコードにありません" "パス Mewbell/UI/SampleRow.swift"

repo="$(make_repo pattern-token)"
replace "$repo/docs/architecture.md" "- **適用外**: なし" '- **適用外**: `.claude/rules/*.md` と `openspec/changes/<change>/design.md`'
expect_pass "グロブやプレースホルダーのパスは、展開も実在の確認もしない" "$repo"

# --- 重複 ---
repo="$(make_repo duplicate)"
printf '\nプレビューとテストで store を組まずに済み、どの操作が起きるかが引数で読めるようになる。\n' >>"$repo/CLAUDE.md"
expect_fail "原則の文をそのまま写している" "$repo" "CLAUDE.md: [重複]" "docs/architecture.md:8"

repo="$(make_repo no-duplicate-targets)"
rm "$repo/CLAUDE.md" "$repo/openspec/config.yaml" "$repo/.claude/rules/review.md"
expect_pass "重複を探す先が無くても、標準入力を読まずに通る" "$repo"

repo="$(make_repo short-sentence)"
printf '\n状態を二重に持つ。\n' >>"$repo/CLAUDE.md"
expect_pass "40 文字に満たない文や採らなかった案の名前は、重複にもコードの名前にも数えない" "$repo"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures 件が失敗しました" >&2
  exit 1
fi
echo "すべて通りました"
