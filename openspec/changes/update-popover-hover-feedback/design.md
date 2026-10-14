# Design

## Context

ポップオーバーのボタンのスタイルは 3 種類が混ざっている（proposal.md の Why）。

- 見出しの歯車（`OpenSettingsButton`）と再読み込み（`ReloadButton`）は、`ReloadButton.swift` にある `PressableIconButtonStyle` を使う。ラベルに 4pt の余白を付け、`onHover` と `configuration.isPressed` で角丸の塗り（`.primary` の透明度 0.08 / 0.2）を出す。押せないときは塗りを出さない
- スレッドの行の既読・Done（`ThreadActionButtons`）、Web の通知一覧（`OpenWebNotificationsButton`）、すべて既読（`MarkAllReadButton`）、コピー（`CommandRow`）は `.borderless` で、マウスを載せても見た目が変わらない。押せないときは、`.borderless` がラベルを薄くする
- スレッドの行（`ThreadRow`）と開閉の見出し（`DisclosureButton`）は `.plain` で、マウスを載せても見た目が変わらない

`ThreadRow` は、行にマウスを載せると既読・Done のボタンを `overlay` で重ね、件名がボタンの下に透けないように、`Button` の外側に付けた `.mask` でボタンの範囲と手前を消している。`DisclosureButton` のラベルは中身の幅で、`RepositoryGroupView` の `.frame(maxWidth: .infinity)` はボタンの外に付いているので、押せる範囲は中身の幅だけである。アカウントの見出しは `DisclosureButton` の後ろに `Spacer(minLength: 0)` と 2 つのアイコンのボタンを並べている。

## Goals / Non-Goals

**Goals:**

- spec の「ポップオーバーの押せる要素のホバーの反応」を、1 つのボタンのスタイルで満たす
- 行と見出しの高さ、アイコンと文字の位置、件名の折り返しを変えない

**Non-Goals:**

- 設定ウィンドウのボタンと、システム標準の押しボタン（Quit など）は変えない
- キーボードのフォーカスの見た目は変えない
- アニメーションは足さない（塗りは出し消しするだけ。今の歯車・再読み込みと同じ）

## Decisions

### D1. 塗りは 1 つの `ButtonStyle` にまとめ、余白と角の丸みだけを引数にする（A1・A9）

`PressableIconButtonStyle` を `HoverHighlightButtonStyle` に改名し、`UI/HoverHighlightButtonStyle.swift` に移す。引数は塗りの内側の余白（`padding`、既定 4）だけにし、角の丸みは今の 5pt に揃える。

- 歯車・再読み込み・Web の通知一覧・すべて既読・コピー: 既定の余白 4
- スレッドの行の既読・Done: 余白 0（今の 22pt 四方の枠をそのまま塗る。余白を足すとボタンが大きくなり、件名を消す範囲 `ThreadActionButtons.size` もずれる）
- スレッドの行と開閉の見出し: 余白 0

`configuration.isPressed` を読むには `ButtonStyle` が要るので、`onHover` の modifier で済ませる形は取らない。行・見出し・アイコンで別々のスタイルにすると、塗りの色・透明度・押せないときの扱いが 3 か所に分かれるので、1 つにまとめる（A9 の「役割でまとめる」。役割は「ポップオーバーの押せる要素の塗り」）。スタイルは `UI/` だけが使うので `UI/` に置く（A1）。

代替案: `.borderless` のまま `.onHover` で背景を足す。押している間の濃い塗りが出せず、歯車・再読み込みと見た目が揃わないので採らない。

`PressableIconButtonStyle` の名前は `docs/architecture.md` に書かれていない（grep で確認済み）ので、改名で文書は直さない。

### D2. 塗りを出さないときと、ラベルの色（A4）

スタイルは、`isEnabled` が false のとき塗りを出さない（今と同じ）。`.borderless` をやめると、押せないときにラベルが自動では薄くならないので、スタイルが押せないときのラベルに `.foregroundStyle(.tertiary)` を付ける。アイコンの色は「ポップオーバーの文字の読みやすさ」の文字色の決まりの外である。押せなくなるのはすべて既読（アイコン）と再読み込み（読み込み中の表示に替わる）だけで、押せない文字のラベルは無い。

すべて既読の確認の文は、今は `.tint(.accentColor)` と `.borderless` でアクセントカラーにしている。独自のスタイルでは `.tint` がラベルの色にならないので、確認の文の `Text` に `.foregroundStyle(.tint)` を付ける。アイコンの色は、`.borderless` のときと同じに見えることをプレビューで確かめ、変わったらスタイルで今の色に合わせる。

### D3. `ThreadRow` の mask はラベルの中に移す（今の形）

今の `.mask` は `Button` の外に付いているので、スタイルがラベルの後ろに付ける塗りも、既読・Done のボタンの範囲で一緒に抜かれる（spec の「ボタンの下を含めて行の全体に出し続ける」を満たさない）。`.mask` を `Button` のラベルの `HStack` に付け替える。消えるのは件名と下の行の文字だけになり、スタイルの塗りはマスクの外で行の全体に出る。ボタンは `overlay` のまま行の塗りの上に重なり、ボタン自身の塗りが重なる。

行の塗りは、スタイルの `onHover`（ラベルの範囲）で出す。既読・Done のボタンは行のボタンの `overlay` にあり、マウスがボタンの上に移ると、行のラベルの `onHover` が外れたと知らせるかもしれない（Risks）。その場合は、行の塗りを `ThreadRow` の `isHovering`（`overlay` を含む行全体の `onHover`）で出すように変える。

### D4. 開閉の見出しの押せる範囲を、行の空いている幅に広げる

`DisclosureButton` のラベルの `HStack` に、`.contentShape(Rectangle())` の前で `.frame(maxWidth: .infinity, alignment: .leading)` を付ける。リポジトリの見出しは行の幅いっぱいになり、アカウントの見出しは `Spacer(minLength: 0)` が 0 になって Web の通知一覧のボタンの手前までになる。ボタンとは `HStack` の間隔（6pt）で分かれたままなので、押し間違えて開閉しない（今のコメントの意図）。1 つの変更で両方の見出しが spec を満たすので、`DisclosureButton` に引数は足さない（A9）。折りたたみの操作を出さないときの見出し（`isCollapsible` が false）はボタンではないので、塗りは出ない。

`OneLineText` は、提案された幅で `ViewThatFits` を選ぶ。幅いっぱいの枠を付けても、中身に提案される幅は今と同じ（空いた幅のぶん大きくなるだけ）なので、省略の仕方は変わらない。長いホスト名の `grace` のプレビューで確かめる。

### D5. 状態の置き場所とスレッド（A2・A3）

マウスを載せている状態は、スタイルの中の View の `@State` にだけ持つ（ポップオーバーを閉じれば消えてよい状態）。すべて `@MainActor` の View の中で動き、store・actor・ネットワーク・gh には触れない。テストで差し替える外部は無い（A5 は該当しない）。

### D6. 確かめ方（A12）

ホバーの見た目は単体テストせず、tasks に手元で確かめる項目として spec の Scenario ごとに置く。寸法を測る既存のテスト（`IconColumnTests`、`AccountDisclosureTests` など）は、全体のテストを回して落ちないことを確かめる。

## セキュリティ

この change は View の見た目と押せる範囲だけを変え、`.claude/rules/security.md` のどの項目にも触れない。

- トークン: 取得・保持・送信・破棄の流れを変えない。View はトークンを受け取らない
- gh サブプロセス: 触れない
- ネットワーク: 触れない。リクエストの組み立てとオリジン検査は変えない
- URL を開く処理: Web の通知一覧とスレッドを開くボタンの見た目だけを変え、`ThreadWebURL` と `NotificationStore` の開く経路は変えない
- アプリとビルドの設定、依存: 変えない（外部依存は足さない。A13）

## Risks / Trade-offs

- [既読・Done のボタンにマウスを移すと、行の塗りが消える（SwiftUI の `onHover` が重なった View で外れたと知らせる）] → 手元で確かめ、消えるときは D3 のとおり行の塗りを `ThreadRow` の `isHovering` で出す
- [Done で行が消えると、次の行がカーソルの下に来ても、マウスを動かすまで `onHover` が届かず塗りが出ない] → 今の既読・Done のボタンの出し消しと同じ振る舞いなので受け入れる。手元で確かめる
- [見出しの押せる範囲が広がり、空いたところのクリックでも開閉する] → spec で決めた振る舞い。すべて既読のボタンとは重ねない
- [`.borderless` をやめてアイコンの色や太さが変わる] → プレビューで前後を比べ、変わったらスタイルで合わせる（D2）
