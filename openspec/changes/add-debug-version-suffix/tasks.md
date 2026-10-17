# Tasks

## 1. 表示用のアプリ名とバージョン

- [ ] 1.1 `Mewbell/Shared/AppInfo.swift` に `AppInfo`（`#if DEBUG` で分ける `static let name` と `static let version`）を足す（D1、D2）。`project.xcproj` は同期フォルダなので、ファイルを置くだけでターゲットに入る（編集は不要）。確認: `MewbellTests/AppInfoTests.swift` で、`AppInfo.name == "Mewbell (dev)"` と、`AppInfo.version` が Info.plist の `CFBundleShortVersionString` に `-dev` を付けた値であることを確かめる。Debug 構成で動く前提であることをテストのコメントに書く
- [ ] 1.2 `APIGateway.userAgent` を `Mewbell/\(AppInfo.version)` にする。確認: `GitHubAPIClientTests` の `User-Agent` の検査を `Mewbell/` の前方一致から `"Mewbell/\(AppInfo.version)"` との一致に強める

## 2. 画面への反映

- [ ] 2.1 `DiagnosticsReport` に `appName` の引数を足して最初の節の見出しにし、`SettingsView` の `appVersion` を消して `AppInfo.name` と `AppInfo.version` を渡す（D3、D4）。プレビューの呼び出しも直す。確認: `DiagnosticsReportTests` に、`appName: "Mewbell (dev)"`・`appVersion: "0.5.0-dev"` で節の見出しとコピーするテキストに `[Mewbell (dev)]` と `0.5.0-dev` が入り、1 行目が `Mewbell Diagnostics` のままであることを確かめるテストを足し、既存のテストを新しい引数に合わせて通す
- [ ] 2.2 `MenuBarContentView` の見出しを `Text(AppInfo.name)` にする。確認: 手元の Debug ビルドでポップオーバーの見出しが `Mewbell (dev)` になり、見出しの並び（設定と再読み込みのボタン）が崩れないこと（ポップオーバーの範囲だけを撮る）
- [ ] 2.3 `StatusItemMenu.showAbout()` で `orderFrontStandardAboutPanel(options:)` に `.applicationVersion: AppInfo.version` を渡す（D5）。手元の Debug ビルドで About パネルを開き、`.version` を渡さない・空の文字列を渡す・`.applicationVersion` と同じ値を渡すのうち、括弧が付かずに「0.5.0-dev」とだけ出る渡し方を選び、理由をコメントに書く。確認: 既存の `StatusItemMenuTests` が通る。Debug ビルドの About パネルの表示（パネルの範囲だけを撮る）

## 3. 仕上げ

- [ ] 3.1 ビルドとテストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test`、`bash scripts/lint.sh`、`pnpm exec openspec validate --all --strict`、警告をエラー扱いにした Debug と Release のビルド
- [ ] 3.2 手元で起動して確認した: `bash scripts/run.sh` の Debug ビルドで、ポップオーバーの見出しと Diagnostics の節の見出しに `Mewbell (dev)`、About パネルと Diagnostics の Version に `0.5.0-dev` が出る。`bash scripts/build.sh Release` のアプリを起動し、見出しが `Mewbell`、バージョンが `0.5.0` とだけ出ること、About パネルの表示を main の Release ビルドと見比べて違い（括弧の有無）を記録すること、Info.plist の `CFBundleDisplayName` が `Mewbell`、`CFBundleShortVersionString` と `CFBundleVersion` が `0.5.0` のままであること（`plutil -extract`）を確かめる
- [ ] 3.3 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: 3.1 のテストと lint が引き続き通る
- [ ] 3.4 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。確認: 指摘の件数と対応結果を PR 本文の Test plan に書く
- [ ] 3.5 PR 本文に「セキュリティ上の確認」の節を書く（`User-Agent` の組み立てに触れるため。design のセキュリティの節の内容）。確認: PR 本文にその節がある

## Workflow follow-up

- `/opsx:archive add-debug-version-suffix` のときに、`openspec/specs/distribution/spec.md` の Purpose に「Debug ビルドと Release ビルドの表示用のアプリ名とバージョンの区別」を足す（delta では Purpose を変えられないため）
- archive の後に PR を ready にする
