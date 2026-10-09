# Design

## Context

メニューバーのラベルは `MenuBarLabel`（`Mewbell/UI/MenuBarLabel.swift`）で、`MewbellApp` の `MenuBarExtra` の `label:` に渡している。未読があるときは `Text("\(Image(systemName: "cat.fill")) \(badge)")` を、無いときは `Image(systemName: "cat.fill")` を返す。M3 で「`HStack` を並べても画像しか出ないことがある」ため 1 つの `Text` にしたが、手元（macOS 26）では未読があると猫が消えて数字だけになっている。`MenuBarExtra` のラベルは SwiftUI のビューのまま描かれるのではなく、AppKit のステータス項目のボタンの画像とタイトルに変換されるので、画像と文字の組み合わせはどちらかが落ちることがある。

件数の文字列は `UnreadBadge.text(for:)` が作り、`UnreadBadgeTests` で確かめている。件数は `NotificationStore.unreadCount`（`@MainActor` の `@Observable`）から読む。

## Goals / Non-Goals

**Goals:**

- 未読があるときも猫のアイコンを出し、件数をその右に出す
- 未読があるときは猫を緑で、件数の文字はメニューバーの文字の色で描く
- 未読が 0 件のときは今までどおりのテンプレート画像（メニューバーの色に合わせて AppKit が塗る）にする

**Non-Goals:**

- 緑以外の色や、色を変えない設定（必要になったら `add-settings` 以降で考える）
- 件数を丸いバッジ（背景つきの円）で描くこと
- ラベルを AppKit の `NSStatusItem` で作り直すこと（`MenuBarExtra` のまま直す）

## Decisions

### D1. 猫と件数を 1 枚の `NSImage` に描いて、ラベルには画像だけを渡す

`MenuBarLabel` は、件数に応じて作った `NSImage` を `Image(nsImage:)` で返す。ラベルに渡すのが画像 1 つだけなら、AppKit 側で片方が落ちることがない。

画像は `MenuBarIcon.image(badge:)`（`MenuBarLabel.swift` に置く、`@MainActor` の純粋な関数）が作る。

- `badge == nil`（0 件）: `NSImage(systemSymbolName: "cat.fill")` をメニューバーの大きさに合わせた `SymbolConfiguration` で作り、`isTemplate = true` のまま返す。見た目は今と同じ
- `badge != nil`: `NSImage(size:flipped:drawingHandler:)` で、猫（`SymbolConfiguration(paletteColors: [.systemGreen])` を付けた記号）と、その右に少し間をあけて件数の文字を描く。`isTemplate = false` にする。文字は `NSFont.menuBarFont(ofSize: 0)` に数字の幅をそろえる指定（`monospacedDigit`）を付け、色は `NSColor.labelColor` にする

大きさは、猫の記号の大きさ + 間 + 件数の文字の幅、高さは記号と文字の大きいほう。件数ごとに幅が変わるので、メニューバーの項目の幅も件数に合わせて変わる（今と同じ）。

代わりの案:

- (a) 今の `Text` に `.foregroundStyle(.green)` を付ける。テンプレートとして描かれるので色が付かず、猫が落ちる問題も残る
- (b) `HStack { Image; Text }`。M3 で画像しか出ないことがあったので採らない
- (c) `NSStatusItem` を自前で持つ。ボタンの `image` と `title` を別々に設定できるが、`MenuBarExtra(.window)` のポップオーバーを自前で作り直すことになり、変更が大きい

### D2. 文字と緑の色は、描くときの外観で決める

`isTemplate = false` の画像は AppKit が塗り直さないので、文字の色を自分で決める必要がある。`drawingHandler` の中で `NSColor.labelColor` と `NSColor.systemGreen` を使うと、描くときの外観（`NSAppearance.current`）で色が決まる。ステータス項目のボタンは自分の外観（メニューバーの外観。壁紙によってはシステムの外観と違う）で描くので、メニューバーの文字と同じ色になる。

外観を切り替えたときは、ボタンが描き直すときに `drawingHandler` がまた呼ばれるので、画像を作り直さなくても色が変わる。

この前提（`MenuBarExtra` が渡した `NSImage` を、ラスタライズせずにボタンの外観で描く）は、実装の最初のタスクで手元で確かめる。崩れていたら Risks の代わりの手を取る。

### D3. 画像は件数が変わったときだけ作る

`MenuBarLabel` の `body` は `unreadCount` が変わったときに評価される。`MenuBarIcon.image(badge:)` はそのたびに新しい画像を作る。作るのは軽い（記号 1 つと短い文字列）ので、キャッシュはしない。

### D4. アクセシビリティ

今と同じく、未読があるときは `Mewbell, <badge> unread`、無いときは `Mewbell` を `accessibilityLabel` に付ける。色だけで状態を伝えないよう、件数の文字は残す（spec どおり）。

### D5. スレッドと actor の境界

すべて `@MainActor` で動く。`MenuBarLabel` は View なので `@MainActor`、`MenuBarIcon.image(badge:)` も `@MainActor` にする（`NSImage` と `NSFont` を使うため）。ネットワークや ポーラーには触れない。

### D6. テスト

`MenuBarIcon.image(badge:)` をユニットテストで確かめる。

- `nil` なら `isTemplate == true`、件数があれば `false`
- `"1"` と `"99+"` で幅が増え、どちらも猫だけの画像より広い
- 件数ありの画像を、ライトとダークの外観（`NSAppearance(named:).performAsCurrentDrawingAppearance`）でそれぞれ `NSBitmapImageRep` に描き、緑の画素があること、文字の部分にライトでは暗い画素、ダークでは明るい画素があること

ネットワークも gh も使わないので、差し替えるプロトコルは要らない。メニューバーでの見た目は手元で確かめる。

## セキュリティ

この change はメニューバーの表示だけを変える。表示する値は未読の件数（`UnreadBadge.text(for:)` の結果）だけで、トークン・API の URL・レスポンスの中身はラベルに入らない。

- トークンの流れ: 変わらない（取得・保持・送り先・破棄のどれにも触れない）
- gh サブプロセス・ネットワーク・URL を開く処理: 触れない。security.md の該当項目は今の実装のまま満たす
- ログ: 新しいログは足さない
- 依存: 足さない

## Risks / Trade-offs

- **[`MenuBarExtra` が画像をラスタライズする]** → ボタンの外観ではなくアプリの外観で文字の色が決まり、メニューバーとシステムの外観が違うときに文字が見えにくくなる。手元の確認で崩れていたら、`MenuBarLabel` で `@Environment(\.colorScheme)` を読んで外観ごとに画像を作るか、文字だけを `.primary` の `Text` にしてアイコンと分ける形を試す。どちらも駄目なら D1 の (c) を別の change で考える
- **[緑がメニューバーの背景に埋もれる]** → `systemGreen` はライトとダークで明るさが変わる動的な色なので、どちらでも背景と区別できる見込み。壁紙によってメニューバーが色付きのときは見づらいことがあるが、件数の文字は残るので未読があることは分かる
- **[記号の大きさがほかのアイコンと合わない]** → 0 件のときのテンプレート画像と、件数ありの画像で同じ `SymbolConfiguration` を使い、猫の大きさが変わらないようにする。手元で並べて確かめる
