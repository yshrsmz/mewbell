# Design

## Context

メニューバーのアイコンは SwiftUI の `MenuBarExtra`（`.menuBarExtraStyle(.window)`）で作っている。`MenuBarExtra` には右クリックを扱う API が無く、今は右クリックしても左クリックと同じくポップオーバーが開く。設定ウィンドウは `OpenSettingsButton` が SwiftUI の `@Environment(\.openSettings)` で開き、`SettingsWindowActivator` が前面に出している。終了は `MenuBarContentView` の Quit ボタン（`.keyboardShortcut("q")`）で、`AppDelegate.applicationShouldTerminate` がポーリングを止めてトークンを捨ててから終わる。

macOS 27 では、ウィンドウ型の `MenuBarExtra` はステータスアイテムのボタンの target と action を使わず（どちらも nil）、システムのメニューバーから届くシーンのアクションと非公開の expanded interface session でポップオーバーを開く（[MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) の `NSStatusItem+ExpandedInterfaceSession.swift` の説明と、手元の確認による）。Apple Developer Forums では、Apple のエンジニアが「ローカルのイベントモニターは、ステータスアイテムのイベントを見る方法としてもう勧めていない」と答え、ステータスアイテムの `button` をそのまま使うことと、ジェスチャー認識を付けることを挙げている（[thread 832823](https://developer.apple.com/forums/thread/832823)）。

proposal を書く前に、macOS 27.0.1 の手元で試作して次のことを確かめた（試作のコードは戻してある）。

- `NSApp.windows` のうち `NSStatusBarWindow` の `contentView` の中に、`MenuBarExtra` の `NSStatusBarButton` がある。起動の直後ではなく、`MenuBarExtra` がステータスアイテムを作った後に見つかる
- そのボタンに `buttonMask = 0x2`（右ボタン）の `NSClickGestureRecognizer` を付けると、右クリックで認識が終わり（`.ended`）、そこでメニューを出せる。ポップオーバーは開かない
- Control+左クリックは、システムが右クリックに変えて届けるので、同じジェスチャー認識で受け取れる
- 修飾キーの無い左クリックでは、これまでどおりポップオーバーが開く
- `NSStatusBarButton.menu` にメニューを入れておくと、アクセシビリティの `AXShowMenu`（VoiceOver の VO+Shift+M）でそのメニューが出る。マウスの右クリックは、`menu` を入れただけでは何も出ない
- 先にローカルのイベントモニター（`rightMouseDown`・`rightMouseUp`）も試し、27.0.1 では動いた。ただし押したときと離したときの両方のイベントを止めないとポップオーバーも開き、上の Apple の答えにも反する

手元に macOS 26 の Mac が無いため、対応 OS の下限の macOS 26 での動きは確かめていない。

## Goals / Non-Goals

**Goals:**

- `MenuBarExtra` とポップオーバーの今の振る舞い（ui の spec の既存の要件）を変えずに、右クリック・Control+クリック・VoiceOver の「メニューを表示」でメニューを出す
- メニューの項目の並びを、ユニットテストで確かめられる形にする

**Non-Goals:**

- `MenuBarExtra` をやめて `NSStatusItem` と `NSPopover` で作り直すこと
- メニューに再読み込み・ログイン時に起動などの項目を足すこと（ユーザーと決めた項目は About・Settings…・Releases・Quit の 4 つ）
- ポップオーバーを開いている間の ⌘Q（ユーザーと決めて、メニューの ⌘Q だけにする）

## Decisions

### D1. `MenuBarExtra` のまま、ステータスアイテムのボタンに右ボタンのジェスチャー認識を付ける（A1・A9・A13）

`App/` に `StatusItemMenu`（`@MainActor final class`）を置き、`AppDelegate.applicationDidFinishLaunching` で作って持つ（テストのホストとプレビューでは作らない）。`StatusItemMenu` は `NSApp.windows` から `NSStatusBarWindow` の `contentView` の中の `NSStatusBarButton` を探し、`buttonMask = 0x2` の `NSClickGestureRecognizer` を 1 つ付ける。認識が終わったら、メニューを `menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)` でアイコンの下に出す。出している間にアイコンを押した見た目にする `button.highlight(true)` は、macOS 27.0.1 では見た目が変わらず（ポップオーバーの表示も、ボタンの状態ではなく expanded interface session が受け持つ）、26 では確かめられないので付けない（A9）。同じボタンに 2 つ目を付けないよう、付けたボタンを弱参照で覚える。

Control+クリックは、システムが右クリックに変えて届けるので、別に扱わない（試作で確かめた。A9）。

- 採らなかった案: ローカルのイベントモニター（`NSEvent.addLocalMonitorForEvents`）で右クリックを横取りする。27.0.1 では動いたが、Apple がステータスアイテムには勧めないと答えている。押したときと離したときの両方を握りつぶす必要があり、アプリのすべての右クリックがモニターを通る
- 採らなかった案: `NSStatusItem` と `NSPopover` で作り直し、`button.sendAction(on: [.leftMouseDown, .rightMouseUp])` で左右を分ける（以前からの定番の形）。公開 API だけで済むが、`@Environment(\.openSettings)` が SwiftUI のシーンの外では使えなくなり、ポップオーバーの既存の要件（外側のクリックで閉じる、⌘, など）をすべて作り直して確かめ直すことになる。macOS 27 では自作のステータスアイテムのクリックが壊れたという報告もある（thread 832823）
- 採らなかった案: 外部のライブラリ（MenuBarExtraAccess）を入れる。ステータスアイテムを `NSStatusBarWindow` の非公開のキー（`statusItem`）から取る手口で、右クリックの API は持たない。A13 に照らして依存を足すほどの量ではなく、こちらは公開されたビューの階層をたどるだけにする
- `NSStatusBarWindow` の中の構造は公開された約束ではない。ボタンが見つからないときは何もせず（右クリックは今までどおりポップオーバーを開く）、アプリは止めない。リスクに書く

### D2. VoiceOver には `NSStatusBarButton.menu` で同じメニューを渡す（A1）

`AXShowMenu` はマウスのクリックではないので、D1 のジェスチャー認識には届かない。`StatusItemMenu` は、見つけた `NSStatusBarButton` の `menu` に、右クリックで出すのと同じ `NSMenu` を入れる。

ボタンを探してジェスチャー認識と `menu` を付けるのは、`MenuBarLabel` が表示されたとき（`MenuBarExtra` がステータスアイテムを作った後）にする。ラベルが作り直されたとき（ステータスアイテムが作り直された場合を含む）も同じ合図が来るので、まだ付けていないボタンにだけ付ける。`MenuBarLabel` からは A14 のとおりクロージャで `AppDelegate` に伝える。

- 採らなかった案: 起動の直後に探す。`MenuBarExtra` はステータスアイテムを遅れて作るので、起動の時点ではまだ無いことがある

### D3. メニューの並びを切り出してテストする（A9・A10）

`StatusItemMenu.makeMenu()` が項目（タイトル、`keyEquivalent`、区切りの位置）を組む。テストではタイトルとキーの並びを確かめる。可視性はテストのために広げず、`makeMenu()` は private にして、テストはアプリがボタンに付けるのと同じ `menu`（外からは読むだけ）を確かめる。右クリックかどうかの判定はジェスチャー認識の `buttonMask` に任せ、判定の関数は作らない（守る分岐が無い。A9）。ジェスチャー認識とボタン探しは、ユニットテストの `NSHostingView` ではメニューバーのウィンドウが無いので、手元の確認のタスクで確かめる。

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

- [`NSStatusBarWindow` の中の構造は非公開で、将来の macOS で変わりうる] → 見つからないときは何もせず、右クリックではポップオーバーが開く。設定はポップオーバーの歯車から開けるが、終了の手段はこのメニューだけなので、その場合は UI から終了できなくなる（アクティビティモニタなどで終了するしかない）。手元の確認のタスクで、右クリックと VO+Shift+M の両方を確かめる
- [ポップオーバーを開いている間に ⌘Q で終了できなくなる] → ユーザーと決めた。メニューの Quit の表示に ⌘Q を付ける
- [対応 OS の下限の macOS 26 では確かめていない] → 手元に 26 の Mac が無い。ジェスチャー認識はボタンのビューに付けるだけで、26 以前の target と action の経路にも 27 の expanded interface session の経路にも手を入れないので、26 でも左クリックの動きは変わらない見込み。右クリックが 26 でもジェスチャー認識に届くかは、確かめられる人がいれば確かめる。届かない場合も、右クリックでポップオーバーが開く今の動きに戻るだけになる
- [macOS 26 以降、メニューバーの一番上の端の右クリックがステータスアイテムに届かないという報告がある（[thread 811718](https://developer.apple.com/forums/thread/811718)）] → システム側の当たり判定の問題で、アプリからは直せない。少し下を右クリックすれば出る
- [macOS 27 のメニューバーのクリックの経路は変わったばかりで、更新でまた変わりうる] → 手元の確認のタスクで、右クリック・Control+クリック・左クリック・VO+Shift+M を毎回確かめる

## セキュリティ

- トークン: 取得・保持・送信・破棄の流れは変えない。Quit は `applicationShouldTerminate` を通り、ポーリングを止めてメモリ上のトークンを捨てる今の処理をそのまま使う
- gh サブプロセス: 触れない
- ネットワーク: 触れない。API への新しいリクエストは無い
- URL を開く処理: Releases の項目は、コードに書いた固定の `https://github.com/yshrsmz/mewbell/releases` だけを開く。API のレスポンス・設定・ユーザーの入力から URL を組み立てないので、`.claude/rules/security.md` の「ブラウザで開く URL はアカウントの Web ホストと一致するもの」（API が返す URL のための規則）の対象外で、`https://cli.github.com/` のボタンと同じ扱いになる。固定の URL が `https` であることをテストで確かめる
- ログ: 新しいログは出さない。出す場合も `Logger` を使い、可変値は `.private` のままにする
- アプリとビルドの設定: entitlement と Info.plist は変えない
