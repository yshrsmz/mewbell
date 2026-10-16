# Design

## Context

- `ThreadIcon`（`Mewbell/UI/ThreadIcon.swift`）は、件名の種類と状態から記号・色・読み上げの名前を決める値型で、View の外で決めて単体テストしている（A4）。色は `Color?` で持ち、`nil` なら `ThreadRow` が `.secondary` で描く。今の割り当ては Pull request の open が `.green`、merged が `.purple`、closed が `.red`、Issue の open が `.green`、closed as completed が `.purple`、draft と closed as not planned が `nil`。
- 色の割り当ては GitHub の Web と同じだが、色そのものは macOS のシステムの色で、Primer の値と違う（proposal の Why）。
- `Mewbell/Assets.xcassets` には `AccentColor`（中身の無い既定のもの）と `AppIcon` だけがある。プロジェクトの設定で `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` が `YES` なので、色セットを足すと `Color(.stateOpen)` のような名前の付いた記号が生成される。
- `ThreadIconTests`（`MewbellTests/ThreadPresentationTests.swift`）は、状態どうしの記号の違い、読み上げの名前、状態が無いときの `color == nil` を確かめている。色の値そのものは確かめていない。
- アカウントの見出しの `TokenStateIcon` は `.green`・`.yellow` のシステムの色を使い、テストでもその値を確かめている。メニューバーの猫アイコンの緑もシステムの色。どちらも GitHub の状態ではないので、この change では変えない。
- ui spec の「ポップオーバーの文字の読みやすさ」は、アイコンの色を文字の色の決まりから外している。独自の色をアイコンに使うことは、その Requirement と矛盾しない。

## Goals / Non-Goals

**Goals:**

- 状態のアイコンの緑・赤・紫を、Primer の `fgColor-open`・`fgColor-closed`・`fgColor-done` の値にする。ライト・ダーク・それぞれのコントラストを上げたときの 4 通りで、Primer の対応するテーマの値を使う。
- 外観と「コントラストを上げる」の切り替えに、アプリのコードで追従しなくて済むようにする。
- 色の値（12 個）が spec の表と一致することを単体テストで確かめる。

**Non-Goals:**

- 状態ごとの色の割り当て、記号の形、読み上げの名前を変えること。
- draft・closed as not planned・状態が分からないアイコンの薄い色を変えること。
- `TokenStateIcon`、メニューバーの猫アイコン、警告の黄色など、GitHub の状態ではないアイコンの色を変えること。
- Commit・Release・Discussion などの種類のアイコンに色を付けること。
- Primer のパッケージを取り込むこと、Primer の値をビルド時に取ってくること。

## Decisions

### D1. 色はアセットカタログの色セットに置く（A13、A9）

`Mewbell/Assets.xcassets` に色セットを 3 つ足す。名前は Primer の役割の名前に合わせて `StateOpen`・`StateClosed`・`StateDone` にする。各色セットには、何も指定しないもの（ライト）、`luminosity: dark`、`contrast: high`、`luminosity: dark` かつ `contrast: high` の 4 つの外観を置き、spec の表の値を sRGB で書く。

`ThreadIcon` の `stateIcon` で、`.green` を `Color(.stateOpen)`、`.red` を `Color(.stateClosed)`、`.purple` を `Color(.stateDone)` に置き換える。`ThreadIcon` の形（`color: Color?`、`nil` なら薄い色）と `ThreadRow` の描き方は変えない。

外観と「コントラストを上げる」の切り替えは、色セットを読むシステムが行う。描くたびにその時の外観で解決されるので、設定を変えたときにポップオーバーを開き直さなくても新しい色で出る（spec）。

採らなかった案:

- コードで 4 通りの値を持つ（`NSColor(name:dynamicProvider:)` で `NSAppearance` の `bestMatch` を見て返す）: 値はテストしやすいが、外観の名前の組み合わせ（`.aqua`・`.darkAqua`・`.accessibilityHighContrastAqua`・`.accessibilityHighContrastDarkAqua`）をアプリで判定することになり、システムがしてくれることを自前で書くことになる。アセットカタログは Apple の慣用で、Xcode でも値を確かめられる。
- Primer のパッケージを取り込む: Swift 向けのパッケージは無く、使うのは 12 個の値だけなので、依存を足す理由にならない（A13）。
- 色の名前を GitHub の状態の名前でなく見た目の名前（`GitHubGreen` など）にする: Primer は同じ緑を `success` と `open` の両方に使うが、このアプリで使うのは状態の色だけなので、役割の名前の方が `ThreadIcon` の割り当てと対応して読める。
- 色を `ThreadIcon` の外の新しい型（`StateColor` など）にまとめる: 使うのは `ThreadIcon` の 1 か所で、生成された記号がすでに名前の付いた入口になる（A9）。

### D2. 値のテストは色セットを外観ごとに解決して確かめる（A12、A10）

`ThreadIconTests` に、`ThreadIcon` が状態ごとに返す色を 4 つの外観（`NSAppearance(named:)` の `.aqua`・`.darkAqua`・`.accessibilityHighContrastAqua`・`.accessibilityHighContrastDarkAqua`）で解決し、sRGB の成分が spec の表と一致する（8 bit に丸めて一致する）ことを確かめるテストを足す。`NSColor(Color)` を `appearance.performAsCurrentDrawingAppearance` の中で `usingColorSpace(.sRGB)` にして成分を読む。

このテストは、色セットの書き間違い（外観の取り違え、値の打ち間違い）と、`ThreadIcon` の割り当ての取り違え（open に done を使うなど）の両方を見逃さないためにある（A12）。テストのために `ThreadIcon` の可視性や形は変えない（A10）。

draft と closed as not planned の色が `nil` のままであることも、同じテストの表に入れて確かめる。

採らなかった案:

- 割り当て（`color == Color(.stateDone)` など）だけを確かめる: 色セットの値の打ち間違いと外観の取り違えを見逃す。ハイコントラストの値は手元で目で見ても気づきにくい。

### D3. GitHub の状態でないアイコンはシステムの色のままにする（A9）

`TokenStateIcon` の緑と黄、メニューバーの猫アイコンの緑は、トークンの状態とアプリの状態を表すもので、GitHub の Web に対応するものが無い。Primer の色に揃える理由が無く、macOS の他のアプリの状態の表示と揃っている方がよいので、変えない。docs/architecture.md には足さない（独自の色を使ってよいのは「GitHub の Web と対応させる表示」だけという判断は、ui spec の Requirement に書いたことで足りる。別の機能で同じ問いが出たら、そのときに原則にするかを決める）。

## Risks / Trade-offs

- Primer の値が将来変わると、GitHub の Web とずれる → spec に Primer の版と値を書いておき、ずれに気づいたら change で直す。自動で追いかけることはしない。
- ポップオーバーの背景はシステムのマテリアルで、壁紙によってはライトの値（特に紫 `#8250DF`）の小さい記号が背景に沈むことがある → GitHub の Web も同じ値を白に近い背景で使っている。手元でライト・ダーク・コントラストを上げたときに見て確かめる（tasks）。
- `contrast: high` の外観をアセットカタログが「コントラストを上げる」で選ぶことは、ユニットテストでは `NSAppearance` を名前で作って確かめるだけで、設定を切り替えたときの実際の描画は手元で確かめる。

## テストでの差し替え

ネットワークと gh サブプロセスには触れないので、差し替えるものは無い。色の値のテストは、`NSAppearance` を名前で作って色を解決するだけで、画面に描かない。

## スレッドと actor の境界

`ThreadIcon` は View の中で作る値型で、`@MainActor` の View の body の上で作られる（A2）。色セットの解決は描画のときにシステムが行う。actor の境界は変えない。テストは `NSAppearance.performAsCurrentDrawingAppearance` を使うので、`@MainActor` のテストにする。

## セキュリティ

該当しない。表示の色を変えるだけで、トークンの取得・保持・送信・破棄、gh サブプロセス、ネットワーク、URL を開く処理のどれにも触れない。`.claude/rules/security.md` の項目は、どれも今までどおり変えない。
