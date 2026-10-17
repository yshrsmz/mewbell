# Proposal

## Why

手元で `bash scripts/run.sh` などで起動した Debug ビルドも、Homebrew や Releases の zip で入れた Release ビルドも、ポップオーバーの見出しに `Mewbell`、About パネルと Diagnostics に同じ `0.5.0` を出す。どちらが動いているか見分けられず、手元の確認や不具合の報告で取り違える。Debug ビルドのアプリ名とバージョンに印を付けて、本番と区別できるようにする。

M5（配布）の後の改善で、配布物の運用に関わる change として扱う。

## What Changes

- Debug ビルドが表示・送信するバージョンを `X.Y.Z-dev`（例: `0.5.0-dev`）にする。対象は About パネル、Diagnostics タブの Version の行とコピーするテキスト、API の `User-Agent`（`Mewbell/0.5.0-dev`）
- Debug ビルドがアプリの画面に出すアプリ名を `Mewbell (dev)` にする。対象はポップオーバーの見出しと、Diagnostics タブの Mewbell の節の見出し（コピーするテキストの `[Mewbell (dev)]` を含む）
- Release ビルドの表示は変えない（`Mewbell`、`0.5.0`）
- Info.plist の `CFBundleDisplayName`・`CFBundleShortVersionString`・`CFBundleVersion`、`project.xcproj` のバージョンの書き方は変えない（release-please の印、CI のバージョンの検査、配布物の検査 `verify-app.sh` はそのまま）。About パネルのアプリ名、通知のバナーのアプリ名、システム設定に出る名前は `Mewbell` のまま

## Capabilities

### New Capabilities

（なし）

### Modified Capabilities

- `distribution`: Debug ビルドが表示・送信するバージョンに `-dev` を、画面に出すアプリ名に `(dev)` を付ける要件を足す
- `ui`: About パネルに出すバージョンを、Info.plist の値そのものではなく、アプリが表示するバージョン（Debug なら `-dev` 付き）にする

## Impact

- コード: `Mewbell/Shared/` に表示用のアプリ名とバージョンを置き、`Mewbell/App/StatusItemMenu.swift`（About パネル）、`Mewbell/App/MenuBarContentView.swift`（ポップオーバーの見出し）、`Mewbell/UI/SettingsView.swift` と `Mewbell/Diagnostics/DiagnosticsReport.swift`（Diagnostics）、`Mewbell/GitHubAPI/APIGateway.swift`（`User-Agent`）がそれを使う
- テスト: 表示用のアプリ名とバージョンの組み立てのユニットテストを足し、Diagnostics の節の見出しのテストを直す
- ネットワーク: `User-Agent` の値だけが変わる（Debug のみ）。トークン、送り先、オリジン検査には触れない。gh サブプロセスと URL を開く処理には触れない。トークンを永続化しない方針にも影響しない
- ビルド設定・CI・リリースのワークフロー: 変えない
