# Tasks

## 1. 表示用のアプリ名とバージョン

- [ ] 1.1 `Mewbell/Shared/AppInfo.swift` に `AppInfo`（`name`・`version` と、純粋な関数 `makeName(isDebug:)`・`makeVersion(shortVersion:isDebug:)`）を足す（D1、D2）。`project.xcproj` にファイルを足す必要があれば足し、`xcodebuild` で開けることを確かめる。確認: `MewbellTests/AppInfoTests.swift` で、`makeName` が Debug で `Mewbell (dev)`・Release で `Mewbell`、`makeVersion("0.5.0", …)` が Debug で `0.5.0-dev`・Release で `0.5.0`、`shortVersion` が `nil` のとき `0-dev` / `0` になること、Debug 構成のテストで `AppInfo.name` と `AppInfo.version` に印が付いていることを確かめる
- [ ] 1.2 `APIGateway.userAgent` を `Mewbell/\(AppInfo.version)` にする。確認: `GitHubAPIClientTests` の `User-Agent` の検査を `Mewbell/` の前方一致から `"Mewbell/\(AppInfo.version)"` との一致に強める

## 2. 画面への反映

- [ ] 2.1 `DiagnosticsReport` に `appName` の引数を足して最初の節の見出しにし、`SettingsView` の `appVersion` を消して `AppInfo.name` と `AppInfo.version` を渡す（D3、D4）。プレビューの呼び出しも直す。確認: `DiagnosticsReportTests` に `appName: "Mewbell (dev)"` で節の見出しとコピーするテキストの `[Mewbell (dev)]` を確かめるテストを足し、既存のテストを新しい引数に合わせて通す
- [ ] 2.2 `MenuBarContentView` の見出しを `Text(AppInfo.name)` にする。確認: 手元の Debug ビルドでポップオーバーの見出しが `Mewbell (dev)` になり、見出しの並び（設定と再読み込みのボタン）が崩れないこと（ポップオーバーの範囲だけを撮る）
- [ ] 2.3 `StatusItemMenu.showAbout()` で `orderFrontStandardAboutPanel(options:)` に `.applicationVersion: AppInfo.version` を渡す（D5）。手元の Debug ビルドで About パネルを開き、`.version` を渡さない・空の文字列を渡す・`.applicationVersion` と同じ値を渡すのうち、括弧が付かずに「0.5.0-dev」とだけ出る渡し方を選び、理由をコメントに書く。確認: 既存の `StatusItemMenuTests` が通る。Debug ビルドの About パネルの表示（パネルの範囲だけを撮る）

## 3. 仕上げ

- [ ] 3.1 ビルドとテストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test`、`bash scripts/lint.sh`、警告をエラー扱いにした Debug と Release のビルド
- [ ] 3.2 手元で起動して確認した: `bash scripts/run.sh` の Debug ビルドで、ポップオーバーの見出しと Diagnostics の節の見出しに `Mewbell (dev)`、About パネルと Diagnostics の Version に `0.5.0-dev` が出る。`bash scripts/build.sh Release` のアプリを起動し、見出しが `Mewbell`、バージョンが `0.5.0` とだけ出ること、Info.plist の `CFBundleDisplayName` が `Mewbell`、`CFBundleShortVersionString` と `CFBundleVersion` が `0.5.0` のままであること（`plutil -extract`）を確かめる
- [ ] 3.3 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: 3.1 のテストと lint が引き続き通る
- [ ] 3.4 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。確認: 指摘の件数と対応結果を PR 本文の Test plan に書く

## Workflow follow-up

- `/opsx:archive add-debug-version-suffix` の後に PR を ready にする
