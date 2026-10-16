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

### D1. スクロールバーが出ていないときだけ、右の内側の余白でスクロールバーの幅を空ける（A3・A9）

legacy で、スクロールバーが出ていないときは、`ScrollView` に `.contentMargins(.trailing, <スクロールバーの幅>, for: .scrollContent)` を付けて、中身の右を空ける。スクロールバーが出ているときと overlay のときは 0 にする。スクロールバーが出ているときは中身がスクロールバーの分だけ狭まり、出ていないときは余白の分だけ狭まるので、中身の幅はどちらも「`ScrollView` の幅 − スクロールバーの幅」になる。

スクロールバーが出ているかは、次の 2 つで決まる。

- はみ出しているか: `onScrollGeometryChange(for: Bool.self)` で `contentSize.height > containerSize.height` を読み、View の `@State` に持つ（ポップオーバーを閉じれば消えてよい状態なので View に置く。A3）
- アニメーションで隠しているか: 今の `DisclosureAnimations.running > 0`

アニメーションの間は、はみ出しているかどうかにかかわらず余白を付ける（スクロールバーは隠れているので）。update-notification-list で「高さを比べてはみ出すときだけ出す」案を採らなかったのは、アニメーションの間は比較の結果が毎フレーム変わるためだった。この形では、アニメーションの間ははみ出しの値を見ないので、同じちらつきは起きない。

余白は内側の余白（content margin）にし、外側の `.padding` やポップオーバーの幅は変えない。中身の幅はどの状態でも同じなので、余白を付け外ししても件名の折り返しは変わらず、折り返しが変わって高さが変わり、はみ出しが切り替わって余白が戻る、という往復は起きない。

代替案:

- スクロールバーを常に出す（`.scrollIndicators(.visible)`）: 収まっているときにも空のスクロールバーの溝が出る。アニメーションの間に隠すときのずれは残る
- `NSScrollView` を探して `scrollerStyle = .overlay` にする: ユーザーの設定を上書きし、SwiftUI の内側の `NSScrollView` に手を入れることになる
- 中身の幅を `GeometryReader` で測って固定する: 測った幅を状態に持つ経路が増え、余白で済むことに見合わない

### D2. 余白の幅の判断は値型にして単体テストする（A7・A9・A10）

余白の幅は、スクロールバーの表示のしかた・はみ出しているか・アニメーションで隠しているかの 3 つから決まる。この判断を `ScrollerGutter`（`init(style: NSScroller.Style, overflows: Bool, indicatorsHidden: Bool)` と `width: CGFloat`）にして、`AccountDisclosure` と同じように View を組まずに単体テストする。spec の Scenario の 4 つの状態（legacy で収まっている、legacy ではみ出している、legacy でアニメーション中、overlay）を引数にしたテストで守る。型を足すのは、このテストのためである（A9）。

スクロールバーの幅は `NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)` で得る。SwiftUI の `ScrollView` のスクロールバーは標準の大きさの `NSScroller` なので、同じ値になる。合っていることは手元で確かめる（tasks の 4）。

置き場所は `UI/`（AppKit の型を使い、一覧だけが使う。A1）。`HidesScrollIndicatorsWhileAnimating` は、スクロールバーの表示（隠すことと、余白）をまとめて受け持つ modifier に改めて、`ScrollerGutter` と同じ新しいファイル `UI/ListScroller.swift` に移す。名前は `ListScrollerModifier` にする。数を読むのはこの modifier だけにして、開閉のたびに一覧全体が描き直されない今の形は保つ。`HidesScrollIndicatorsWhileAnimating` の名前は `docs/architecture.md` に書かれていない（grep で確認済み）ので、改名で文書は直さない。

### D3. スクロールバーの表示のしかたの変化は通知で拾う（A3・A5）

スクロールバーの表示のしかたは、modifier の `@State` に `NSScroller.preferredScrollerStyle` を持ち、`NSScroller.preferredScrollerStyleDidChangeNotification` を受けたら読み直す（マウスをつないだ・外した、システム設定を変えたときに届く）。読み直すのは一覧が出ている間だけでよく、ポップオーバーを開くたびに `@State` の初期値として読み直される。

表示のしかたは AppKit のシステムの値で、テストで差し替えたい外部ではない（判断は D2 の値型に引数で渡してテストする）ので、プロトコルの裏には置かない（A5 の対象外）。

### D4. スレッドと actor の境界（A2）

すべて View の中の `@MainActor` の処理で、actor・store・ポーラーには触れない。通知は main の上で届く `NotificationCenter` の通知を、View の modifier（`onReceive`）で受ける。

## セキュリティ

トークン・gh サブプロセス・ネットワーク・URL を開く処理のどれにも触れない。一覧の余白の付け外しだけを変え、表示する文字や開く URL は変えないので、`.claude/rules/security.md` の各項目は該当しない。新しく持つ状態（はみ出しているか、スクロールバーの表示のしかた）は View の `@State` にだけ置き、永続化しない。

## Risks / Trade-offs

- [スクロールバーの出し消しと余白の付け外しが 1 フレームずれる] → はみ出しの値は `onScrollGeometryChange` で描画の後に届くので、収まった・はみ出した瞬間の 1 フレームだけ、余白とスクロールバーが両方ある・両方無い状態があり得る。次のフレームで戻り、ボタンの位置は落ち着いた後で同じになる。手元で、Done を続けて押して押せなくならないことを確かめる
- [`NSScroller.scrollerWidth` と SwiftUI のスクロールバーの幅が合わない] → 手元で、スクロールバーが出ているときと出ていないときのボタンの位置を比べる。ずれたら、`onScrollGeometryChange` の `containerSize.width` と `ScrollView` の幅の差で測る形に改める
- [legacy で収まっているとき、右に 15pt ほどの空きが常に出る] → 中身の幅は今のスクロールバーが出ているときと同じで、狭くなるのは収まっているときだけ。ボタンが動かないことを優先する
