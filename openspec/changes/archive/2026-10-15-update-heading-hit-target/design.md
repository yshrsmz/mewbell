# Design

## Context

開閉の見出しは `DisclosureButton` が描く。畳めるときは `Button` のラベルの `HStack`（山形と見出しの中身）に `.frame(maxWidth: .infinity, alignment: .leading)` を付け、`HoverHighlightButtonStyle()` を当てている。スタイルは塗りと押せる範囲（`contentShape(Rectangle())`）をラベルの枠に合わせるので、押せる範囲の高さはラベルの中身の高さ（16〜18pt）になる。畳めないときは同じ中身の `HStack` をボタンにせずに出す。

アカウントの見出しは `AccountSectionView.header` の `HStack` に `DisclosureButton`、`Spacer`、Web の通知一覧とすべて既読のボタン（`HoverHighlightButtonStyle(outset: 3)`、枠はアイコンの大きさ）を並べる。リポジトリの見出しは `RepositoryGroupView` の `VStack(spacing: 2)` の先頭に置く。一覧の寸法は `ListLayout` にまとめている。

## Goals / Non-Goals

**Goals:**

- spec の「見出しの押せる範囲の高さ」を `DisclosureButton` の 1 か所で満たす
- 畳める見出しと畳めない見出しの高さを揃える

**Non-Goals:**

- 見出しのアイコンのボタン、スレッドの行、ポップオーバーの上の見出しの大きさは変えない
- 区画やグループの間の間隔（`VStack` の spacing）は変えない
- 文字の大きさの設定ごとに高さを変える（中身が高いときに中身に合わせるだけにする）

## Decisions

### D1. 高さは `ListLayout.headingHeight`（24）に置く（A9）

見出しの高さは一覧の寸法なので、`ListLayout` に `headingHeight: CGFloat = 24` を足す（A9 の「一覧の寸法を `ListLayout` にまとめる」）。24 は macOS のサイドバーの小さい行（`NSTableView.RowSizeStyle.small`）の高さで、HIG の最小 20pt を満たし、既定 28pt ほど一覧を伸ばさない。

### D2. `DisclosureButton` の中身に高さの下限を付ける（A9・A16）

畳めるときは、ラベルの今の枠を `.frame(maxWidth: .infinity, minHeight: ListLayout.headingHeight, alignment: .leading)` にする。スタイルの塗りと押せる範囲はラベルの枠に合わせるので、それだけで 24pt になる。中身は枠の縦の中央に置かれる（`alignment: .leading` は縦が中央）。中身が 24pt より高いときは `minHeight` なので中身に合わせて伸びる。

畳めないときの `HStack` にも同じ `.frame(maxWidth: .infinity, minHeight: ListLayout.headingHeight, alignment: .leading)` を付け、同じ枠にする（横の配置を呼び出し側の `Spacer` や枠に頼らない）。2 つの枝で同じ下限を書くので、`labelWithCount` と同じように private の computed property か `ViewModifier` にはせず、2 か所の 1 行の modifier のままにする（A9 の「1 行の modifier を型で包まない」）。

アカウントの見出しの `HStack` は既定で縦の中央揃えなので、24pt の開閉のボタンの横で、アイコンのボタンは今の大きさのまま縦の中央に並ぶ。

代替案:

- `HoverHighlightButtonStyle(outset:)` で、見た目の高さを変えずに押せる範囲だけ上下に広げる: リポジトリの見出しとその下の行の間隔は 2pt しかなく、広げると押せる範囲が隣と重なる。畳めない見出しには効かない。採らない
- ラベルに上下の余白（`.padding(.vertical, 4)` など）を付ける: 高さが書体の大きさで変わり、アカウント（`.headline`）とリポジトリ（`.subheadline`）で揃わない。採らない
- `DisclosureButton` に高さの引数を足す: 2 つの見出しで同じ値なので要らない（A9）

A16 は「並べる大きさを変えられないボタンは `outset` で広げる」としている。見出しは並べる大きさを変えてよいとこの change で決めたので、A16 から外れない。押せる範囲の大きさは D5 で A16 に書き足す。

### D3. 状態とスレッド（A2・A3）

寸法の変更だけで、状態は足さない。すべて `@MainActor` の View の中で動き、store・actor・ネットワーク・gh には触れない。テストで差し替える外部は無い（A5 は該当しない）。

### D4. 確かめ方（A12）

見出しの高さは `NSHostingView` の `fittingSize` で測る（A12 の「SwiftUI の実際の寸法は `NSHostingView` で測る」）。アカウントの見出しの書体（`.headline`）とリポジトリの見出しの書体（`.subheadline.weight(.semibold)`）の中身で、畳めるときと畳めないときの `DisclosureButton` の高さが `ListLayout.headingHeight` であることを確かめる。下限を消すと 16〜18pt になって落ちるので、削ったら見逃す不具合を守る。塗りの範囲と中央の配置、押せる範囲は手元で確かめる項目として tasks に置く。

### D5. 押せる範囲の大きさを A16 に書き足す（A16）

押せる要素の大きさは、要素を足すたびに同じ問いが出るので、`docs/architecture.md` に書く。新しい原則にはせず、押せる要素の見た目を扱う A16 に書き足す（スキル `update-architecture-doc` の「既存の原則に書き足せないかを先に探す」）。書き足すのは次のとおり。

- 原則: 押せる範囲は縦横とも 20pt（macOS の HIG の最小）以上にする。一覧の開閉の見出しの高さは `ListLayout.headingHeight` にそろえ、枠の `minHeight` で広げる
- 理由: HIG はコントロールの大きさを既定 28pt、最小 20pt としている。見出しは 2 種類の書体で中身の高さが違うので、余白ではなく高さの下限でそろえる
- 採らなかった案: 見出しの押せる範囲を `outset` で広げる（隣の行と押せる範囲が重なり、畳めない見出しの高さがそろわない）。見出しに上下の余白を付ける（書体ごとに高さが変わる）
- 根拠: update-heading-hit-target D1・D2

アイコンのボタンの押せる範囲を `NSHostingView` で測ると、歯車・再読み込みは 24pt 四方（余白 4）、Web の通知一覧は 22×20pt、すべて既読は 21pt 四方、その確認の文は縦 20pt（いずれも `outset: 3`）、スレッドの行の既読・Done は 22pt 四方で、20pt を満たす。コマンドの行のコピーのボタンだけは、ラベルの枠が幅しか決めておらず、コピーした後の 2 秒間に記号が `checkmark` に替わると縦が 19pt に縮んだ。ラベルの枠を `.frame(width: 16, height: 18)` にして、コピーの記号（`doc.on.doc`）の高さにそろえる（1 行の直しで済むので、逸脱として残さずにこの change で直す。記号を替えても行の高さが動かなくなる）。

`ListLayout.headingHeight` は実装で足す名前で、先に文書に書くと `scripts/check-architecture.sh` の「コードの名前」の検査で止まる。文書の更新は実装と同じタスク群に置く。

## セキュリティ

この change は見出しの寸法だけを変え、`.claude/rules/security.md` のどの項目にも触れない。

- トークン: 取得・保持・送信・破棄の流れを変えない。View はトークンを受け取らない
- gh サブプロセス、ネットワーク、URL を開く処理: 触れない
- アプリとビルドの設定、依存: 変えない（外部依存は足さない。A13）

## Risks / Trade-offs

- [一覧が縦に長くなり、480pt の上限でスクロールが出やすくなる] → 見出し 1 つで 6〜8pt ほど。ユーザーが見た目の高さが伸びることを受け入れた。手元で、リポジトリが多いアカウントで確かめる
- [リポジトリの見出しと上のグループの最後の行の間が広く見える] → 間隔（spacing 10）は変えずに手元で見る。詰めたくなったら別の change にする（spec の振る舞いではないが、見た目の判断が要るため）
- [アカウントの見出しで、取得中の `ProgressView`（mini）が中央からずれる] → `ProgressView` もアイコンの列の中で縦の中央に置かれる。手元で確かめる
