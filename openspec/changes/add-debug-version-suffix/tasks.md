# Tasks

## 1. 表示用のバージョン

- [ ] 1.1 `Mewbell/Shared/AppVersion.swift` に `AppVersion`（`current` と純粋な関数 `make(shortVersion:isDebug:)`）を足す（D1、D2）。`project.xcproj` にファイルを足す必要があれば足し、`xcodebuild` で開けることを確かめる。確認: `MewbellTests/AppVersionTests.swift` で、`make("0.5.0", isDebug: true)` が `0.5.0-dev`、`isDebug: false` が `0.5.0`、`shortVersion` が `nil` のとき `0` / `0-dev` になること、Debug 構成のテストで `AppVersion.current` が `-dev` で終わることを確かめる
- [ ] 1.2 `APIGateway.userAgent` を `Mewbell/\(AppVersion.current)` にする。確認: `GitHubAPIClientTests` の `User-Agent` の検査を `Mewbell/` の前方一致から `"Mewbell/\(AppVersion.current)"` との一致と `-dev` で終わることに強める
- [ ] 1.3 `SettingsView` の `appVersion` を消し、Diagnostics に `AppVersion.current` を渡す（D3）。確認: 既存の `DiagnosticsReportTests` が通る。手元の Debug ビルドで Diagnostics の Version の行とコピーしたテキストに `0.5.0-dev` が出る

## 2. About パネル

- [ ] 2.1 `StatusItemMenu.showAbout()` で `orderFrontStandardAboutPanel(options:)` に `.applicationVersion: AppVersion.current` を渡す（D4）。確認: 既存の `StatusItemMenuTests` が通る
- [ ] 2.2 手元の Debug ビルドで About パネルを開き、`.version` を渡さない・空の文字列を渡す・`.applicationVersion` と同じ値を渡すのうち、括弧が付かずに「0.5.0-dev」とだけ出る渡し方を選び、理由をコメントに書く。確認: Debug ビルドの About パネルの表示（ポップオーバーではなくパネルの範囲だけを撮る）

## 3. 仕上げ

- [ ] 3.1 ビルドとテストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test`、`bash scripts/lint.sh`、警告をエラー扱いにした Debug と Release のビルド
- [ ] 3.2 手元で起動して確認した: `bash scripts/run.sh` の Debug ビルドで About パネルと Diagnostics に `0.5.0-dev` が出る。`bash scripts/build.sh Release` のアプリを起動し、About パネルと Diagnostics に `0.5.0` とだけ出ること、Info.plist の `CFBundleShortVersionString` と `CFBundleVersion` が `0.5.0` のままであること（`plutil -extract`）を確かめる
- [ ] 3.3 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: 3.1 のテストと lint が引き続き通る
- [ ] 3.4 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。確認: 指摘の件数と対応結果を PR 本文の Test plan に書く

## Workflow follow-up

- `/opsx:archive add-debug-version-suffix` の後に PR を ready にする
