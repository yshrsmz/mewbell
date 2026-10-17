# Design

## Context

メニューバーのアイコンは SwiftUI の `MenuBarExtra`（`.menuBarExtraStyle(.window)`）で作っている。`MenuBarExtra` には右クリックを扱う API が無く、今は右クリックしても左クリックと同じくポップオーバーが開く。設定ウィンドウは `OpenSettingsButton` が SwiftUI の `@Environment(\.openSettings)` で開き、`SettingsWindowActivator` が前面に出している。終了は `MenuBarContentView` の Quit ボタン（`.keyboardShortcut("q")`）で、`AppDelegate.applicationShouldTerminate` がポーリングを止めてトークンを捨ててから終わる。

proposal を書く前に、macOS 26 の手元で試作して次のことを確かめた（試作のコードは戻してある）。

- `NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp])` で、アイコンの右クリックを受け取れる。`event.window` は `NSStatusBarWindow` で、その `contentView` の中に `NSStatusBarButton` がある
- `rightMouseDown` でメニューを出して `nil` を返しても、`rightMouseUp` を通すとポップオーバーが開く。`rightMouseUp` も `nil` にすると、メニューだけが出る
- Control+左クリックは、システムが `rightMouseDown`（Control の修飾なし）に変えて届ける。修飾キーの無い左クリックは、このモニターに `leftMouseDown` として届かない（`MenuBarExtra` がそのままポップオーバーを開く）
- ポップオーバーを開いたまま右クリックすると、ポップオーバーはキーウィンドウでなくなって閉じ、メニューが出る
- `NSStatusBarButton.menu` にメニューを入れておくと、アクセシビリティの `AXShowMenu`（VoiceOver の VO+Shift+M）でそのメニューが出る。マウスの右クリックは、`menu` を入れただけでは何も出ない

## Goals / Non-Goals

**Goals:**

- `MenuBarExtra` とポップオーバーの今の振る舞い（ui の spec の既存の要件）を変えずに、右クリック・Control+クリック・VoiceOver の「メニューを表示」でメニューを出す
- メニューの項目の並びと右クリックの判定を、ユニットテストで確かめられる形にする

**Non-Goals:**

- `MenuBarExtra` をやめて `NSStatusItem` と `NSPopover` で作り直すこと
- メニューに再読み込み・ログイン時に起動などの項目を足すこと（ユーザーと決めた項目は About・Settings…・Releases・Quit の 4 つ）
- ポップオーバーを開いている間の ⌘Q（ユーザーと決めて、メニューの ⌘Q だけにする）

## Decisions

### D1. `MenuBarExtra` のまま、ローカルのイベントモニターで右クリックを横取りする（A1・A13）

`App/` に `StatusItemMenu`（`@MainActor final class`）を置き、`AppDelegate.applicationDidFinishLaunching` で作って持つ（テストのホストとプレビューでは作らない）。`NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp])` を 1 つ付け、イベントのウィンドウの中に `NSStatusBarButton` があれば、`rightMouseDown` でメニューを出して `nil` を、`rightMouseUp` でも `nil` を返す。それ以外のイベントはそのまま返す。メニューは `menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)` でアイコンの下に出し、出している間は `button.highlight(true)` でアイコンを押した見た目にする（ほかのメニューバーのアイコンと同じ見た目）。

Control+クリックは、システムが `rightMouseDown` に変えて届けるので、別に扱わない（試作で確かめた。`leftMouseDown` と Control の組を見る分岐は、このモニターに届かないので足さない。A9）。

- 採らなかった案: `NSStatusItem` と `NSPopover` で作り直す。公開 API だけで右クリックを扱えるが、`@Environment(\.openSettings)` が SwiftUI のシーンの外では使えなくなり、ポップオーバーの既存の要件（外側のクリックで閉じる、⌘, など）をすべて作り直して確かめ直すことになる
- 採らなかった案: 外部のライブラリ（MenuBarExtraAccess など）を入れる。中身は同じく `NSStatusBarWindow` を探す手口で、A13 に照らして依存を足すほどの量ではない
- `NSStatusBarWindow` と `NSStatusBarButton` の関係は公開された約束ではない。見つからないときは何もせず（右クリックは今までどおりポップオーバーを開く）、アプリは止めない。リスクに書く

### D2. VoiceOver には `NSStatusBarButton.menu` で同じメニューを渡す（A1）

`AXShowMenu` はマウスのイベントではないので、D1 のモニターには届かない。`StatusItemMenu` は、見つけた `NSStatusBarButton` の `menu` に、右クリックで出すのと同じ `NSMenu` を入れる。ボタンを探すのは、`MenuBarLabel` が表示されたとき（`MenuBarExtra` がステータスアイテムを作った後）と、右クリックを受け取ったとき（ステータスアイテムが作り直された場合に付け直す）。`MenuBarLabel` からは A14 のとおりクロージャで `AppDelegate` に伝える。

- 採らなかった案: 起動の直後に探す。`MenuBarExtra` はステータスアイテムを遅れて作るので、起動の時点ではまだ無いことがある

### D3. 右クリックの判定とメニューの並びを切り出してテストする（A7・A10）

- 判定: `StatusItemClick.action(for type: NSEvent.EventType, onStatusButton: Bool) -> Action`（`.showMenu` / `.swallow` / `.pass`）の純粋な関数にする。モニターはこれを呼ぶだけにする
- メニュー: `StatusItemMenu.makeMenu()` が項目（タイトル、`keyEquivalent`、区切りの位置）を組む。テストではタイトルとキーの並びを確かめる。可視性はテストのために広げず、`makeMenu()` は内部（internal）のままにする

### D4. メニューから設定ウィンドウを開く処理は、`openSettings` を `MenuBarLabel` から受け取る（A1・A14）

AppKit の `NSMenu` からは `@Environment(\.openSettings)` を使えない。`MenuBarLabel` は `MenuBarExtra` のシーンの中で常に生きているので、そこで `openSettings` を読み、表示されたときに `AppDelegate` 経由で `StatusItemMenu` に渡す（D2 のボタン探しと同じ合図に載せる）。Settings… を選んだら、`NSApp.activate()`、`openSettings()`、`SettingsWindowActivator.bringToFront()` の順に呼ぶ。この順は `OpenSettingsButton.open()` と同じなので、`dismiss()` 以外の 3 行を `SettingsWindowActivator.open(using:)` にまとめ、ボタンとメニューの両方から呼ぶ。

- 採らなかった案: `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)`。macOS 14 以降は使えず、警告をログに出すだけになる
- 実装のときに、`MenuBarLabel` の環境の `openSettings` で設定ウィンドウが開くことを手元で確かめる。開かない場合は、この Decision を見直してから進める

### D5. About は標準の About パネル、Releases は固定の URL、Quit は `terminate(_:)`

- About Mewbell: `NSApp.activate()` の後に `NSApp.orderFrontStandardAboutPanel(nil)`。アプリ名・バージョン・著作権表示は Info.plist（`CFBundleShortVersionString`、`NSHumanReadableCopyright`）から標準のパネルが読む。`LSUIElement` なので Dock にアイコンは出ない
- Mewbell Releases: `StatusItemMenu` に `static let releasesURL = URL(string: "https://github.com/yshrsmz/mewbell/releases")!` を置き、`NSWorkspace.shared.open` で開く。URL を開く処理は `StatusItemMenu` の初期化で受け取るクロージャにし（A5）、テストでは渡された URL を確かめる
- Quit Mewbell: `NSMenuItem(title:action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")`。`applicationShouldTerminate` を通るので、終了前の処理は変わらない

### D6. ポップオーバーから Quit ボタンと区切りを消し、A16 の例を差し替える（A16）

`MenuBarContentView` の下端の `Divider()` と Quit ボタンを消す。`docs/architecture.md` の A16 は標準の押しボタンの例に「Quit」を挙げているので、スキル `update-architecture-doc` の手順で例を `Open cli.github.com` に差し替える。型や名前は消さないので、「コードの名前」の検査には掛からない。

## Risks / Trade-offs

- [`NSStatusBarWindow` の中の構造は非公開で、将来の macOS で変わりうる] → 見つからないときは何もせず、右クリックはポップオーバーを開く今の動きに戻るだけにする。設定はポップオーバーの歯車から開けるが、終了の手段がメニューだけになる。手元の確認のタスクで、右クリックと VO+Shift+M の両方を確かめる
- [ポップオーバーを開いている間に ⌘Q で終了できなくなる] → ユーザーと決めた。メニューの Quit の表示に ⌘Q を付ける
- [ローカルのイベントモニターはアプリのすべての右クリックを通る] → 判定はウィンドウの種類を見るだけの軽い処理にし、ステータスアイテム以外のイベントはそのまま返す（ポップオーバーや設定ウィンドウの右クリックは変わらない）

## セキュリティ

- トークン: 取得・保持・送信・破棄の流れは変えない。Quit は `applicationShouldTerminate` を通り、ポーリングを止めてメモリ上のトークンを捨てる今の処理をそのまま使う
- gh サブプロセス: 触れない
- ネットワーク: 触れない。API への新しいリクエストは無い
- URL を開く処理: Releases の項目は、コードに書いた固定の `https://github.com/yshrsmz/mewbell/releases` だけを開く。API のレスポンス・設定・ユーザーの入力から URL を組み立てないので、`.claude/rules/security.md` の「ブラウザで開く URL はアカウントの Web ホストと一致するもの」（API が返す URL のための規則）の対象外で、`https://cli.github.com/` のボタンと同じ扱いになる。固定の URL が `https` であることをテストで確かめる
- ログ: 新しいログは出さない。出す場合も `Logger` を使い、可変値は `.private` のままにする
- アプリとビルドの設定: entitlement と Info.plist は変えない
