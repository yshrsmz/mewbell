# Design

## Context

一覧は `NotificationListView`（`Mewbell/UI/AccountSectionView.swift`）の `ScrollView` に入っていて、高さの上限 480pt を超えるとスクロールできる。`ScrollView` には `HidesScrollIndicatorsWhileAnimating` を付けていて、開閉のアニメーションの間だけ `scrollIndicators(.never)`、それ以外は `.automatic` にしている（update-notification-list の判断。アニメーションの間は高さが毎フレーム変わり、スクロールバーがちらつくため）。

macOS の `NSScrollView` は、スクロールバーの表示のしかた（`NSScroller.preferredScrollerStyle`）が `.legacy` のとき、スクロールバーを中身の横に置き、その幅だけ中身の幅を狭める。`.overlay` のときは中身の上に重ねるので、中身の幅は変わらない。SwiftUI の `ScrollView` も同じふるまいで、legacy では次のときに中身の幅がスクロールバーの幅（約 15pt）だけ変わる。

- 中身が収まる・収まらないが切り替わったとき（`.automatic` は、はみ出すときだけスクロールバーを出す）
- 開閉のアニメーションが始まった・終わったとき（`.never` の間はスクロールバーを出さない）

スレッドの行の既読・Done のボタン（`ThreadRow` の `overlay(alignment: .topTrailing)`）、リポジトリの見出しのボタン、アカウントの見出しの Web の通知一覧とすべて既読のボタンは、どれも中身の右端に揃えているので、中身の幅が変わると一緒に動く。

## Goals / Non-Goals

**Goals:**

- spec の「スクロールバーによる一覧の幅」を満たす。legacy では、スクロールバーが出ていてもいなくても中身の幅を同じにする
- overlay のときの見た目は今のままにする

**Non-Goals:**

- スクロールバーを出す条件（はみ出すときだけ）と、アニメーションの間に隠すことは変えない
- スクロールバーの表示のしかたをアプリで上書きしない（overlay に固定しない）
- ポップオーバーの幅、外側の余白は変えない

## Decisions

### D1. legacy では中身の幅の上限を「一覧の幅 − スクロールバーの幅」に固定する（A3・A9）

legacy のときは、`ScrollView` の中身に `.frame(maxWidth: 一覧の幅 − スクロールバーの幅, alignment: .leading)` を付け、スクロールバーが出ていてもいなくても中身の幅を同じにする。スクロールバーが出ているときは、見える幅がちょうどその幅になり、出ていないときは右にスクロールバーの分の空きが残る。overlay のときは上限を付けない。`ScrollView` は自分より狭い中身を横の中央に置くので、外側にもう一度 `.frame(maxWidth: .infinity, alignment: .leading)` を付けて左に寄せる。

一覧の幅は `ScrollView` に付けた `onGeometryChange` で測り、`NotificationListView` の `@State` に持つ（ポップオーバーを閉じれば消えてよい状態なので View に置く。A3）。`ScrollView` の幅はポップオーバーの幅（380pt）と余白だけで決まり、スクロールバーの出し消しでは変わらない。

はみ出しているかどうかは判断しない。スクロールの中の値（`onScrollGeometryChange` の `contentSize`・`containerSize`）は、AppKit がスクロールバーを置き直した後のレイアウトで届くので、それで空きを決めると、出し消しのフレームで必ず 1 フレーム遅れる。一覧の幅は出し消しで変わらないので、この形では遅れが起きない。開閉のアニメーションの数（「視差効果を減らす」のときは数えない）も、高さの比較の端数も、「常に」の設定でスクロールバーの溝が出たままになるかどうかも、幅の判断に関わらない。

開閉のアニメーションの間にスクロールバーを隠す `HidesScrollIndicatorsWhileAnimating` は今のままにする（update-notification-list の判断）。

代替案:

- はみ出しを `onScrollGeometryChange` で予想し、スクロールバーが出ないときだけ `contentMargins` で空ける（最初の実装）: 上の理由で出し消しのフレームに 1 フレーム遅れ、「視差効果を減らす」のときは開閉でも遅れる。厳密な高さの比較が AppKit の判断と端数で食い違うおそれがあり、「常に」の設定で溝が出たままなら空きが二重になる（simplify と code-review の指摘）
- 実際のスクロールバーの有無や幅を `ScrollGeometry` で測る: `ScrollGeometry` にスクロールバーの有無や幅は無く、測れる値も置き直しの後に届くので同じく遅れる
- スクロールバーを常に出す（`.scrollIndicators(.visible)`）: 「はみ出すときだけ出す」「開閉の間は隠す」を変えるので、この change の範囲の外
- 中の `NSScrollView` を探して `scrollerStyle = .overlay` にする、または隠れているかを監視する: ユーザーの設定を上書きし、SwiftUI の内側の `NSScrollView` に手を入れることになる
- 中身の幅を「380 − 余白 − スクロールバーの幅」の定数にする: `.padding()` の既定の幅は名前の付いた定数でなく、一覧がポップオーバーの幅を知ることになる

### D2. 上限の判断は純粋な関数にして単体テストする（A7・A9・A10・A12）

上限は `ListScroller.contentWidthLimit(scrollerStyle:listWidth:) -> CGFloat?` で決める。legacy で一覧の幅を測った後は「一覧の幅 − スクロールバーの幅」、overlay のときと幅をまだ測っていないときは nil（上限なし）。テストは、spec の Scenario「スクロールバーが重なる表示では空きを残さない」の退行を見逃さないための overlay の場合、legacy の場合、幅をまだ測っていない場合を守る。分岐は 2 つだけなので、状態を持つ型にはしない（A9）。

スクロールバーの幅は `NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)` で得る。SwiftUI の `ScrollView` のスクロールバーは標準の大きさの `NSScroller` なので、同じ値になる。合っていることは手元で確かめる（tasks の 4）。値がずれても上限なので、見える幅がそれより狭ければ中身はそちらに合わせ、右端は切れず、横にもスクロールしない。

`ListScroller` と、`AccountSectionView.swift` から移した `HidesScrollIndicatorsWhileAnimating` は、新しいファイル `UI/ListScroller.swift` に置く（AppKit の型を使い、一覧だけが使う。A1。`AccountSectionView.swift` が行数の上限に当たるため、スクロールバーに関わるものをまとめて移す）。`HidesScrollIndicatorsWhileAnimating` は別のファイルから使うので `private` を外す。

### D3. スクロールバーの表示のしかたの変化は通知で拾う（A3・A5）

スクロールバーの表示のしかたは、`NotificationListView` の `@State` に `NSScroller.preferredScrollerStyle` を持ち、`NSScroller.preferredScrollerStyleDidChangeNotification` を受けたら読み直す（マウスをつないだ・外した、システム設定を変えたときに届く）。`@State` の初期値は View が作られたときに 1 回だけ読まれるが、View が生きている間は通知の購読も生きているので、ポップオーバーを閉じている間に切り替わっても通知で読み直される。

表示のしかたは AppKit のシステムの値で、テストで差し替えたい外部ではない（判断は D2 の関数に引数で渡してテストする）ので、プロトコルの裏には置かない（A5 の対象外）。

### D4. スレッドと actor の境界（A2）

すべて View の中の `@MainActor` の処理で、actor・store・ポーラーには触れない。通知は main の上で届く `NotificationCenter` の通知を、View の modifier（`onReceive`）で受ける。

## セキュリティ

トークン・gh サブプロセス・ネットワーク・URL を開く処理のどれにも触れない。一覧の余白の付け外しだけを変え、表示する文字や開く URL は変えないので、`.claude/rules/security.md` の各項目は該当しない。新しく持つ状態（はみ出しているか、スクロールバーの表示のしかた）は View の `@State` にだけ置き、永続化しない。

## Risks / Trade-offs

- [`NSScroller.scrollerWidth` と SwiftUI のスクロールバーの幅が合わない] → 差の分だけ、出し消しでボタンがずれる（上限なので右端は切れない）。手元で、スクロールバーが出ているときと出ていないときのボタンの位置を比べる
- [ポップオーバーを開いた最初の 1 フレームは上限が無い] → 一覧の幅を測る前の 1 フレームだけ、legacy でも中身が幅いっぱいで描かれ、次のフレームで上限が付く。開いた直後で操作の前なので、ボタンを続けて押す場面には当たらない
- [legacy で収まっているとき、右に 15pt ほどの空きが常に出る] → 中身の幅はスクロールバーが出ているときと同じで、狭くなるのは収まっているときだけ。ボタンが動かないことを優先する
