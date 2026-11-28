#!/usr/bin/env bash
# OpenSpec のスキル（.agents/skills/openspec-*/ と、そこを指す .claude/skills/openspec-* のリンク）を生成し直す。
# CI（.github/workflows/ci.yml）も同じスクリプトで生成し直して差分を検査する。
set -euo pipefail

cd "$(dirname "$0")/.."

# 生成するスキルの組み合わせは global 設定（$XDG_CONFIG_HOME/openspec/config.json の profile と workflows）で決まり、
# 設定が無いと既定の core（verify を含まない）になる。手元の設定に左右されないよう、空の設定ディレクトリで 7 つに固定する
XDG_CONFIG_HOME="$(mktemp -d)"
export XDG_CONFIG_HOME
trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
pnpm exec openspec config set profile custom
pnpm exec openspec config set workflows '["propose","explore","apply","update","sync","archive","verify"]'

# CLI が生成物を見つけられずに何も書かずに終わっても差分に出るよう、実体を消してから書き直させる
rm -rf .agents/skills/openspec-*
pnpm exec openspec update --force
