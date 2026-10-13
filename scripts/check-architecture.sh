#!/usr/bin/env bash
# docs/architecture.md の更新の漏れと、ほかの文書への写しを検査する（add-architecture-principles の design D8）。
# 検査: 書式 / ID の参照 / 根拠の change / コードの名前 / 重複。見つけたら標準エラー出力に出して終了コード 1 で終える。
# macOS の bash 3.2 と BSD の grep でも動くように、連想配列や GNU 拡張を使わない。
# 使い方: bash scripts/check-architecture.sh [検査するルート（既定はリポジトリのルート）]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
doc="docs/architecture.md"
cd "$root"

# 文字数を数えるため、UTF-8 のロケールを使う
utf8_locale="$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.utf-?8$' | head -1 || true)"
[[ -n "$utf8_locale" ]] || utf8_locale="$(locale -a 2>/dev/null | grep -iE '\.utf-?8$' | head -1 || true)"
if [[ -z "$utf8_locale" ]]; then
  echo "UTF-8 のロケールが見つかりません（文の長さを文字数で数えられません）" >&2
  exit 1
fi
export LC_ALL="$utf8_locale"

failures=0
# fail <ファイル:行> <検査> <内容と直し方>
fail() {
  echo "$1: [$2] $3" >&2
  failures=$((failures + 1))
}

if [[ ! -f "$doc" ]]; then
  echo "$doc がありません" >&2
  exit 1
fi

# 「## 原則」の節だけを、行番号つきで取り出す（<行番号>\t<行>）
principles="$(awk '/^## /{in_section = ($0 == "## 原則")} in_section{print NR "\t" $0}' "$doc")"
if [[ -z "$principles" ]]; then
  fail "$doc" "書式" "「## 原則」の節がありません"
fi

# --- 書式 ---
ids=""
retired=""
retiring_changes=""
current=""
current_line=""
current_labels=""
check_block() {
  [[ -z "$current" ]] && return 0
  if [[ " $retired " == *" $current "* ]]; then
    [[ "$current_labels" == *"|廃止の理由|"* ]] ||
      fail "$doc:$current_line" "書式" "$current は廃止の見出しなので、本文に「- **廃止の理由**:」を書いてください"
    return 0
  fi
  local label
  for label in 原則 理由 採らなかった案 適用外 根拠; do
    [[ "$current_labels" == *"|$label|"* ]] ||
      fail "$doc:$current_line" "書式" "$current に「- **$label**:」がありません（適用外が無ければ「なし」と書きます）"
  done
}
while IFS=$'\t' read -r line text; do
  [[ -z "${line:-}" ]] && continue
  if [[ "$text" == "### "* ]]; then
    check_block
    if [[ "$text" =~ ^###\ (A[0-9]+)\.\ (.+)$ ]]; then
      current="${BASH_REMATCH[1]}"
      current_line="$line"
      current_labels="|"
      if [[ " $ids " == *" $current "* ]]; then
        fail "$doc:$line" "書式" "ID $current が重複しています。ID は再利用せず、次の番号を振ります"
      fi
      ids="$ids $current"
      if [[ "${BASH_REMATCH[2]}" == 廃止* ]]; then
        retired="$retired $current"
        # 廃止した change の名前（「廃止（<change 名>）」）。その change の文書は、廃止した ID を引いてよい
        retiring_change="${BASH_REMATCH[2]#*（}"
        retiring_changes="$retiring_changes ${retiring_change%%）*}"
      fi
    else
      fail "$doc:$line" "書式" "原則の見出しは「### A<番号>. <名前>」の形にします"
      current=""
    fi
  elif [[ "$text" =~ ^-\ \*\*([^*]+)\*\*: ]]; then
    current_labels="$current_labels${BASH_REMATCH[1]}|"
  fi
done <<<"$principles"
check_block

# --- ID の参照 ---
# 廃止した原則を引いてよいのは、当時の記録である archive と、その原則を廃止した change の文書だけ
# retired_reference_allowed <ファイル>
retired_reference_allowed() {
  [[ "$1" == "$doc" || "$1" == openspec/changes/archive/* ]] && return 0
  local name
  for name in $retiring_changes; do
    [[ "$1" == "openspec/changes/$name/"* ]] && return 0
  done
  return 1
}
reference_files="$(
  {
    ls CLAUDE.md "$doc" openspec/config.yaml .swiftlint.yml 2>/dev/null || true
    ls .claude/rules/*.md .claude/skills/*/SKILL.md 2>/dev/null || true
    find openspec/changes openspec/specs -name '*.md' 2>/dev/null || true
  } | sort -u
)"
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  while IFS= read -r numbered; do
    line="${numbered%%:*}"
    rest="${numbered#*:}"
    # 1 行に複数の ID があっても（「A1・A4」など）、すべてを取り出す
    while [[ "$rest" =~ (^|[^A-Za-z0-9_])(A[0-9]+)([^A-Za-z0-9_]|$) ]]; do
      id="${BASH_REMATCH[2]}"
      rest="${BASH_REMATCH[3]}${rest#*"${BASH_REMATCH[0]}"}"
      if [[ " $ids " != *" $id "* ]]; then
        fail "$file:$line" "ID の参照" "$id は $doc にありません。ID を直すか、原則を足してください"
      elif [[ " $retired " == *" $id "* ]] && ! retired_reference_allowed "$file"; then
        fail "$file:$line" "ID の参照" "$id は廃止した原則です。参照を外すか、今の原則に引き直してください"
      fi
    done
  done < <(grep -nE '(^|[^A-Za-z0-9_])A[0-9]+([^A-Za-z0-9_]|$)' "$file" || true)
done <<<"$reference_files"

# --- 根拠の change ---
while IFS=$'\t' read -r line text; do
  [[ -z "${line:-}" ]] && continue
  [[ "$text" == "- **根拠**:"* ]] || continue
  for name in $(grep -oE '(^|[^a-z0-9-])(add|update|fix|remove)-[a-z0-9]+(-[a-z0-9]+)*' <<<"$text" | sed -E 's/^[^a-z]*//' || true); do
    if [[ ! -d "openspec/changes/$name" ]] && ! ls -d openspec/changes/archive/*-"$name" >/dev/null 2>&1; then
      fail "$doc:$line" "根拠の change" "change $name が openspec/changes/ にも archive にもありません"
    fi
  done
done <<<"$principles"

# --- コードの名前 ---
# 型・メンバー・lint の規則の名前が、コードか設定に出てくるかを見る。採らなかった案（とその下の箇条）は今のコードに無い名前を書く場所なので、検査しない
code_dirs=""
for dir in Mewbell MewbellTests; do
  [[ -d "$dir" ]] && code_dirs="$code_dirs $dir"
done
config_files=""
for file in .swift-format .swiftlint.yml; do
  [[ -f "$file" ]] && config_files="$config_files $file"
done
checked_names=" "
name_exists() {
  [[ "$checked_names" == *" $1 "* ]] && return 0
  # shellcheck disable=SC2086
  { [[ -n "$code_dirs" ]] && grep -rqw --include='*.swift' -- "$1" $code_dirs; } ||
    { [[ -n "$config_files" ]] && grep -qw -- "$1" $config_files; } || return 1
  checked_names="$checked_names$1 "
}
in_rejected=0
while IFS= read -r numbered; do
  line="${numbered%%:*}"
  text="${numbered#*:}"
  if [[ "$text" == "- **採らなかった案**:"* ]]; then
    in_rejected=1
    continue
  fi
  if [[ "$text" == "  "* || "$text" == $'\t'* ]]; then
    [[ "$in_rejected" == 1 ]] && continue
  else
    in_rejected=0
  fi
  [[ "$text" == *'`'* ]] || continue
  # トークンを 1 行ずつ読み、シェルにグロブとして展開させない
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    if [[ "$token" == *[*?\<\>]* ]]; then
      # `.claude/rules/*.md` や `<change>/` のようなパターン・プレースホルダーは、実在を確かめない
      continue
    elif [[ "$token" == */* ]]; then
      [[ -e "$token" || -e "Mewbell/$token" ]] ||
        fail "$doc:$line" "コードの名前" "パス $token がありません。改名や削除に合わせて直してください"
    elif [[ "$token" =~ \.(yml|yaml|md|swift|json|sh)$ ]]; then
      # `hosts.yml` のような、ディレクトリを書かないファイル名は確かめない
      continue
    elif [[ "$token" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)?$ && ! "$token" =~ ^A[0-9]+$ ]]; then
      for part in ${token//./ }; do
        name_exists "$part" ||
          fail "$doc:$line" "コードの名前" "$part がコードにありません。改名や削除に合わせて直してください"
      done
    fi
  done < <(grep -oE '`[^` ]+`' <<<"$text" | tr -d '`' || true)
done < <(grep -n '' "$doc")

# --- 重複 ---
# 原則の文（「。」で区切った 40 文字以上の 1 文）を、ほかの文書（archive を除く）がそのまま写していないかを見る
# 対象のファイルが無いときに grep が標準入力を読まないよう、/dev/null を必ず渡す
duplicate_targets="/dev/null"
for file in CLAUDE.md openspec/config.yaml .claude/rules/*.md .claude/skills/*/SKILL.md openspec/changes/*/design.md; do
  [[ -f "$file" && "$file" != openspec/changes/archive/* ]] && duplicate_targets="$duplicate_targets $file"
done
while IFS=$'\t' read -r line text; do
  [[ -z "${line:-}" ]] && continue
  [[ "$text" =~ ^-\ \*\*[^*]+\*\*:\ (.+)$ ]] || continue
  body="${BASH_REMATCH[1]}"
  while IFS= read -r sentence; do
    sentence="${sentence#"${sentence%%[![:space:]]*}"}"
    [[ ${#sentence} -ge 40 ]] || continue
    # shellcheck disable=SC2086
    for hit in $(grep -lF -- "$sentence" $duplicate_targets 2>/dev/null || true); do
      fail "$hit" "重複" "$doc:$line の文をそのまま写しています。本文は $doc に置き、ここからは ID で引いてください: $sentence"
    done
  done < <(awk '{ gsub(/。/, "\n"); print }' <<<"$body")
done <<<"$principles"

if [[ "$failures" -gt 0 ]]; then
  echo "$doc の検査で $failures 件の問題が見つかりました（更新の手順は .claude/skills/update-architecture-doc/SKILL.md）" >&2
  exit 1
fi
