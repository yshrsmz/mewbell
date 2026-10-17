# Tasks

## 1. メニューと右クリック

- [x] 1.1 `Mewbell/App/StatusItemMenu.swift` に `StatusItemMenu`（`@MainActor final class`）を置き、`makeMenu()` で About Mewbell、区切り、Settings…（⌘,）、Mewbell Releases、区切り、Quit Mewbell（⌘Q、`NSApplication.terminate(_:)`）を組む。Releases は固定の `releasesURL` を初期化で受け取る `openURL` のクロージャで開き、About は `NSApp.activate()` の後に `orderFrontStandardAboutPanel(nil)` を呼ぶ（design.md D5）。テストで、項目のタイトル・`keyEquivalent`・区切りの位置の並び、Releases の項目を選ぶと `https://github.com/yshrsmz/mewbell/releases`（スキームが `https`）が `openURL` に渡ることを確かめる。`-only-testing:` でスイート数を確かめて通す。
- [x] 1.2 `StatusItemMenu` に、`NSApp.windows` の `NSStatusBarWindow` の中から `NSStatusBarButton` を探し、`buttonMask = 0x2` の `NSClickGestureRecognizer` と、`menu`（VoiceOver の「メニューを表示」のため）を付ける処理を足す。認識が終わったら、アイコンの下にメニューを出す（押した見た目にはしない。design.md D1）。付けたボタンは弱参照で覚えて 2 つ目を付けず、見つからないときは何もしない（design.md D1・D2）。ボタン探しとジェスチャー認識はユニットテストで確かめられないので、4.2・4.3 の手元の確認で確かめる。

## 2. 設定ウィンドウとの接続

- [x] 2.1 `OpenSettingsButton.open()` の `NSApp.activate()`・`openSettings()`・`SettingsWindowActivator.bringToFront()` を `SettingsWindowActivator.open(using:)` にまとめ、ボタンからはそれを呼ぶ（design.md D4）。ポップオーバーの歯車と案内画面の Open Settings… で、今までどおり設定ウィンドウが前面に開くことを手元で確かめる。
- [x] 2.2 `MenuBarLabel` で `@Environment(\.openSettings)` を読み、表示されたときにクロージャで `AppDelegate` に渡す。`AppDelegate` は `applicationDidFinishLaunching` で `StatusItemMenu` を作り（テストのホストとプレビューでは作らない）、受け取った `openSettings` と、ボタンを探す合図を `StatusItemMenu` に渡す（design.md D2・D4、A14）。メニューの Settings… で設定ウィンドウが前面に開き、開いている設定ウィンドウは 1 つのまま前に出ることを手元で確かめる。開かなければ design.md D4 を見直してから進める。

## 3. ポップオーバーの Quit を消す

- [x] 3.1 `MenuBarContentView` の下端の `Divider()` と Quit ボタンを消す（design.md D6）。プレビューと手元で、ポップオーバーの下端に余計な区切りや余白が残っていないことを確かめる。
- [x] 3.2 スキル `update-architecture-doc` の手順で、`docs/architecture.md` の A16 の標準の押しボタンの例から Quit を外し、`Open cli.github.com` に差し替える。`bash scripts/check-architecture.sh` を通す。

## 4. 確認

- [x] 4.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [ ] 4.2 `bash scripts/run.sh` で起動し、手元で確かめる。右クリックと Control+クリックでメニューだけが出て、ポップオーバーは開かないこと。修飾キーの無い左クリックではポップオーバーが開くこと。ポップオーバーを開いたまま右クリックすると、ポップオーバーが閉じてメニューが出ること。About Mewbell でバージョン 0.5.0 の About パネルが前面に出て、Dock にアイコンが出ないこと。Mewbell Releases で Releases ページが開くこと。Quit Mewbell と、メニューを開いている間の ⌘Q で終了し、アイコンが消えること。ポップオーバーや設定ウィンドウの中の右クリックの動きが変わっていないこと。
- [ ] 4.3 VoiceOver をオンにして、メニューバーの猫アイコンで VO+Shift+M を押すと同じメニューが出て、項目を選べることを手元で確かめる。

## 5. レビュー

- [x] 5.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 5.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 5.3 ロジックの変更を含む修正が多ければ、5.2 を新しいサブエージェントでもう一度実行する。

## Workflow follow-up

- レビューの対応の後に `/opsx:archive add-menu-bar-context-menu` で archive し、draft PR を ready にする。
