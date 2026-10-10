# Proposal

## Why

M4 までで Mewbell は日常的に使える状態になったが、今は手元で `bash scripts/build.sh` したビルドを動かすしかなく、別の Mac に入れることも更新することも手作業になっている。M5（配布、任意）として、決まった手順でリリース用の配布物を作り、GitHub Releases と自分の Homebrew tap から入れて更新できるようにする。

## What Changes

- リリース用のスクリプト `scripts/release.sh` を追加する。push 前の確認（テスト、警告をエラー扱いにした Debug と Release のビルド、lint）を通したうえで、Release ビルドを ad-hoc 署名のまま zip にし、SHA-256 と Homebrew Cask のファイルを作る。macOS ランナーを使わない方針のため、CI ではなく手元で実行する
- 配布物を作る前に、署名と entitlement を検査する。Hardened Runtime が有効なこと、`get-task-allow` や制限を緩める entitlement が無いこと、Info.plist に ATS の例外が無いこと、バージョンがタグと一致することを確かめ、満たさなければ配布物を作らない
- バージョンの正本を `project.xcproj` の `MARKETING_VERSION` にし、リリースのタグ `vX.Y.Z` と一致させる。`CURRENT_PROJECT_VERSION` はリリースごとに増やす
- Homebrew Cask の雛形をこのリポジトリに置き、リリーススクリプトでバージョンと SHA-256 を入れた `mewbell.rb` を作る。Cask は自分の tap（`yshrsmz/homebrew-tap`、新しく作る）に置く。公式の homebrew-cask には載せない（notarize していない cask は 2026-09-01 から受け付けられないため）
- 署名は ad-hoc のまま（Apple Developer Program の Developer ID は使わない）。notarize もしない。そのため、ダウンロードや `brew install --cask` の後の初回起動で Gatekeeper に止められる。Cask の `caveats` と README で、システム設定の「このまま開く」で開く手順を案内する。quarantine 属性を自動で消すこと（Cask の `postflight_steps` で `xattr` を実行するなど）はしない
- 自動更新（Sparkle など）は入れない。更新は `brew upgrade --cask` か、Releases から入れ直す
- ad-hoc 署名ではビルドごとに署名の要件（cdhash）が変わる。更新の後に、通知の許可とログイン項目の登録が残るかを確かめ、外れる場合は README と `caveats` に書く
- README にインストール・更新・アンインストールの節とリリース手順を足し、CLAUDE.md と SETUP.md の M5 の記述をこの方針に合わせる

## Capabilities

### New Capabilities

- `distribution`: リリース用の配布物（zip、SHA-256、Homebrew Cask）の作り方と、作る前に確かめること（署名・entitlement・ATS・バージョン）、配布物とインストール手順に含めてはならないものを定める。既存の capability（gh-cli / accounts / github-api / polling / notifications / ui / diagnostics / settings）はどれもアプリの実行中の振る舞いを扱っており、ビルドと配布の約束を置ける場所が無いため、新設する

### Modified Capabilities

（なし。アプリの実行中の振る舞いは変えない）

## Impact

- 対象のマイルストーン: M5（配布、任意）
- 追加: `scripts/release.sh`、Homebrew Cask の雛形（`packaging/homebrew/mewbell.rb.template`）、`openspec/specs/distribution/spec.md`
- 変更: `Mewbell.xcodeproj/project.xcproj`（必要ならバージョンと Release のアーキテクチャの設定）、README.md、CLAUDE.md、SETUP.md
- 外部: GitHub に `yshrsmz/homebrew-tap` リポジトリを新しく作り、Cask を置く。GitHub Releases にタグと zip を公開する（どちらも外部に出る操作なので、実施の前にユーザーに確かめる）
- 依存: 追加しない（Sparkle は入れない）。CI のワークフローは変えず、シークレットも渡さない
- セキュリティ（`.claude/rules/security.md`）: トークン・gh サブプロセス・ネットワーク・URL を開くアプリのコードには触れない。トークンの扱い（永続化しない）は変わらない。「アプリとビルドの設定」（Hardened Runtime、制限を緩める entitlement を付けない、ATS の例外を入れない）と「依存とサプライチェーン」の項目が適用され、リリーススクリプトで機械的に確かめる。リリーススクリプトが実行する `gh release create` は開発者の gh の認証で GitHub Releases に上げるだけで、アプリのトークンの扱いとは関係しない
