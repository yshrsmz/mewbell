# Proposal

## Why

M4 までで Mewbell は日常的に使える状態になったが、今は手元で `bash scripts/build.sh` したビルドを動かすしかなく、別の Mac に入れることも更新することも手作業になっている。M5（配布、任意）として、リリースを release-please と GitHub Actions で自動化し、GitHub Releases と自分の Homebrew tap から入れて更新できるようにする。

## What Changes

- release-please を入れる。`main` へのマージ（Conventional Commits の PR タイトル）から Release PR を作り、バージョン（`project.xcproj` の `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION`）と `CHANGELOG.md` を更新する。Release PR をマージすると、タグ `vX.Y.Z` と draft の GitHub Release を作る
- 同じワークフローで、GitHub の macOS ランナー（Xcode 27 のイメージ）がタグからビルドする。テスト、警告をエラー扱いにしたビルド、Release ビルド、署名と entitlement の検査を通した後に、zip と SHA-256 を Release に添付してから公開する。どこかで失敗したら draft のまま残し、公開しない
- 配布物を作る処理（Release ビルド → 検査 → zip → SHA-256）は `scripts/package-release.sh` にまとめ、CI と手元の両方で同じものを使う。検査は Hardened Runtime、`get-task-allow` や制限を緩める entitlement が無いこと、ATS の例外が無いこと、universal であること、バージョンがタグと一致することを確かめる
- 公開の後に、`yshrsmz/homebrew-tap` に `repository_dispatch` でバージョンだけを知らせる。tap 側のワークフローはバージョンの形式を検証し、Release の zip を自分でダウンロードして SHA-256 を計算し、Cask を更新する PR を作る。tap の CI（`brew style` と `brew audit`）が通ったら自動でマージする
- 資格情報は GitHub App にする。mewbell 用の App（release-please、Release の公開、tap への dispatch に使う）と tap 用の App（Cask の PR に使う）を作り、秘密鍵はそれぞれのリポジトリの、`main` だけに限定した Environment のシークレットに置く。トークンはジョブごとに対象のリポジトリと権限を絞って発行する。PAT は使わない
- 署名は ad-hoc のまま（Developer ID は使わない）。notarize もしない。初回起動と更新のたびに Gatekeeper に止められるので、Cask の `caveats` と README で、システム設定の「このまま開く」で開く手順を案内する。quarantine 属性を消す処理は入れない
- 自動更新（Sparkle など）は入れない。更新は `brew upgrade --cask` か、Releases から入れ直す
- ad-hoc 署名ではビルドごとに署名の要件（cdhash）が変わる。更新の後に通知の許可とログイン項目の登録が残るかを確かめ、外れる場合は README と `caveats` に書く
- 開発の規則を変える: CLAUDE.md の「CI は ubuntu だけ」に「リリースのワークフローに限り macOS ランナーを使う」を足す。`.claude/rules/security.md` の「CI にシークレットを渡さない」「`permissions: contents: read`」を、リリースのワークフローに限って GitHub App の秘密鍵と必要な書き込み権限を認める形に改める（条件は design に書く）
- README にインストール・更新・アンインストールの節とリリースの流れを足し、SETUP.md の M5 の記述を合わせる

## Capabilities

### New Capabilities

- `distribution`: リリースの流れ（release-please → タグと draft → macOS ランナーでのビルドと検査 → 添付 → 公開 → tap の更新）、配布物の中身と検査、CI の資格情報の扱い、Homebrew Cask とインストールの案内を定める。既存の capability（gh-cli / accounts / github-api / polling / notifications / ui / diagnostics / settings）はどれもアプリの実行中の振る舞いを扱っており、ビルドと配布の約束を置ける場所が無いため、新設する

### Modified Capabilities

（なし。アプリの実行中の振る舞いは変えない）

## Impact

- 対象のマイルストーン: M5（配布、任意）
- 追加（mewbell）: `.github/workflows/release.yml`、`release-please-config.json`、`.release-please-manifest.json`、`CHANGELOG.md`（release-please が作る）、`scripts/package-release.sh`、`scripts/lib/verify-app.sh`、`scripts/tests/verify-app-test.sh`、`packaging/homebrew/mewbell.rb.template`、`openspec/specs/distribution/spec.md`
- 変更（mewbell）: `Mewbell.xcodeproj/project.xcproj`（バージョンをプロジェクトの設定に 1 か所にまとめ、release-please の印を付ける）、README.md、CLAUDE.md、`.claude/rules/security.md`、SETUP.md
- 追加（homebrew-tap、OpenSpec の外）: Cask を更新するワークフロー、`brew style` と `brew audit` の CI、Cask の雛形
- 外部の設定（ユーザーが行う、または確かめてから行う）: GitHub App を 2 つ作ってインストールする、両リポジトリに Environment `release` とシークレットを作る、homebrew-tap で auto-merge を有効にし、CI を必須にする ruleset を作る
- 依存: アプリの依存は増やさない。CI に `googleapis/release-please-action` と `actions/create-github-app-token` を足す（コミット SHA で固定する）
- セキュリティ（`.claude/rules/security.md`）: アプリのトークン・gh サブプロセス・ネットワーク・URL を開くコードには触れず、トークンを永続化しない方針も変わらない。「アプリとビルドの設定」はリリースごとに機械的に確かめる。「依存とサプライチェーン」のうち CI のシークレットと権限の項目を、上記のとおり改める
