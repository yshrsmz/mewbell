# Proposal

## Why

手元で `bash scripts/run.sh` などで起動した Debug ビルドも、Homebrew や Releases の zip で入れた Release ビルドも、About パネルと Diagnostics に同じ `0.5.0` を出す。どちらが動いているか見分けられず、手元の確認や不具合の報告で取り違える。Debug ビルドのバージョンに `-dev` を付けて、本番と区別できるようにする。

M5（配布）の後の改善で、配布物の運用に関わる change として扱う。

## What Changes

- Debug ビルドが表示・送信するバージョンを `X.Y.Z-dev`（例: `0.5.0-dev`）にする。対象は About パネル、Diagnostics タブの Version の行とコピーするテキスト、API の `User-Agent`（`Mewbell/0.5.0-dev`）
- Release ビルドの表示は変えない（`0.5.0`）
- Info.plist の `CFBundleShortVersionString` と `CFBundleVersion`、`project.xcproj` のバージョンの書き方は変えない（release-please の印、CI のバージョンの検査、配布物の検査 `verify-app.sh` はそのまま）

## Capabilities

### New Capabilities

（なし）

### Modified Capabilities

- `distribution`: Debug ビルドが表示・送信するバージョンに `-dev` を付ける要件を足す
- `ui`: About パネルに出すバージョンを、Info.plist の値そのものではなく、アプリが表示するバージョン（Debug なら `-dev` 付き）にする

## Impact

- コード: `Mewbell/Shared/` に表示用のバージョンを置き、`Mewbell/App/StatusItemMenu.swift`（About パネル）、`Mewbell/UI/SettingsView.swift`（Diagnostics）、`Mewbell/GitHubAPI/APIGateway.swift`（`User-Agent`）がそれを使う
- テスト: 表示用のバージョンの組み立てのユニットテストを足す
- ネットワーク: `User-Agent` の値だけが変わる（Debug のみ）。トークン、送り先、オリジン検査には触れない。gh サブプロセスと URL を開く処理には触れない。トークンを永続化しない方針にも影響しない
- ビルド設定・CI・リリースのワークフロー: 変えない
