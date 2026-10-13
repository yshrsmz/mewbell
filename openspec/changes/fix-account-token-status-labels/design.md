# Design

## Context

アカウントの見出しのトークンの状態の表示は、`AccountSectionView` の `tokenIcon` が `status.tokenState` と `feed?.phase.isStopped` で分岐し、分岐ごとに記号・色・ツールチップを View に直接書いている。取得中は `ProgressView` で、ツールチップも名前も無い。`.disabled` の分岐もあるが、無効のアカウントの区画は `NotificationListView` が出さないので、ポップオーバーには出ない。

`tokenIcon` は見出しの `title` の中にあり、`title` は `DisclosureButton` のラベルになる。`DisclosureButton` はラベル全体の読み上げを上書きせず、値（`Collapsed` / `Expanded`）と説明（`Expand alice (github.com)` など）だけを付けるので、ラベルの中の要素に付けた名前はボタンの読み上げに含まれる。畳めないとき（トークンを取れないときなど）は、ボタンにせず同じラベルを並べる。

スレッドの行の種類のアイコンは、`ThreadIcon`（`UI/ThreadEventText.swift`）が種類と状態から記号・色（nil なら薄い色）・名前を決め、`ThreadRow` が `.accessibilityLabel(icon.label)` を 1 回だけ付けている。

`IconColumnTests.fitsTheTokenIcon` は、トークンの状態の記号名を View とテストの両方に書いている（fix-thread-icon-column D3 で、記号の部品化が無いため許容した重複）。

## Goals / Non-Goals

**Goals:**

- トークンの状態の名前・記号・色を View の外の値型で決め、単体テストで確かめられるようにする
- 名前を VoiceOver とツールチップの両方に、状態の分岐の外で 1 回だけ付ける

**Non-Goals:**

- 記号・色の変更（「止まっている」と「トークンを取れない」を記号で区別することを含む）
- 見出しのベースラインの揃え、リポジトリの見出しの読み上げ
- `ThreadIcon` の置き場所の変更（`ThreadEventText.swift` からの移動）

## Decisions

### D1: 状態から記号・色・名前を決める値型 `TokenStateIcon` を置く（A4、A7、A9）

`Mewbell/UI/TokenStateIcon.swift` に、`ThreadIcon` と同じ形の値型を置く。

```swift
struct TokenStateIcon: Equatable {
    /// nil なら取得中（`ProgressView` を出す）
    let symbol: String?
    /// nil なら補足の色（`.secondary`）
    let color: Color?
    /// VoiceOver とツールチップに出す名前
    let label: String

    init(tokenState: TokenState, phase: FeedPhase?)
}
```

- 入力は `TokenState` と `FeedPhase?` にする。「止まっている」の判定（`phase?.isStopped == true`）を値型の中に入れ、今 View にある判定を移す。View は `TokenStateIcon(tokenState: status.tokenState, phase: feed?.phase)` を作るだけにする
- 名前は proposal のとおり、今のツールチップの文言（`Ready`、`Stopped`、`No token`、`Disabled`）をそのまま使い、取得中に `Getting token` を足す。`.disabled` はポップオーバーに出ないが、`switch` を網羅するために名前を持たせる
- 置き場所は `UI/`（A1。使うのは `AccountSectionView` とテストだけ）。`ThreadIcon` と違って `UI/` の 1 か所でしか使わないが、テストで状態ごとの名前と、記号の網羅を確かめるために型にする（A9 の「テストに要る」）。A4 の「文言は View の外の値型で決め、単体テストする」にも合う

採らなかった案:

- View の分岐ごとに `.accessibilityLabel` を足すだけにする: 最小だが、名前とツールチップの文言が分岐ごとに 2 回ずつ並び、単体テストで確かめられない（`NSHostingView` ではアクセシビリティの要素が作られない。CLAUDE.md）。A4 にも合わない
- 取得中を `symbol` の nil でなく enum（`case progress`、`case symbol(String, Color?)`）で表す: 取り違えは減るが、型が 1 つ増え、`ThreadIcon` と形が揃わない。nil の意味はドキュメントコメントで書く
- 入力を `isStopped: Bool` にする: テストは書きやすいが、「止まっている」の判定が View に残る

### D2: 名前は分岐の外で 1 回だけ付ける（A4）

`tokenIcon` は、記号か `ProgressView` かの分岐だけを持ち、その外側で `.help(icon.label)` と `.accessibilityLabel(icon.label)` を 1 回ずつ付ける。

```swift
private var tokenIcon: some View {
    let icon = TokenStateIcon(tokenState: status.tokenState, phase: feed?.phase)
    return Group {
        if let symbol = icon.symbol {
            Image(systemName: symbol).foregroundStyle(icon.color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
        } else {
            ProgressView().controlSize(.mini)
        }
    }
    .help(icon.label)
    .accessibilityLabel(icon.label)
}
```

色の nil を `.secondary` にする書き方は、`ThreadRow` の今の書き方に合わせる（実装のときに `ThreadRow` と同じ形にする）。`ProgressView` に `.accessibilityLabel` を付けると、既定の「進行中」の読み上げの代わりに名前が読まれる。`Group` に付けた modifier は中の要素に付くので、要素が 1 つの今の形では要素に直接付けるのと同じになる。

### D3: `IconColumnTests` は値型から記号を集める

`fitsTheTokenIcon` は、テストに書き並べた記号名の代わりに、`TokenState` のすべての case と、止まっている・止まっていない取得の状態の組で `TokenStateIcon` を作り、`symbol` が nil でないものを集めて測る。`TokenState` の一覧の隣には、`kinds` と同じく `default` の無い網羅的な `switch` を置き、case を足したら一覧に足すまでコンパイルを止める。これで fix-thread-icon-column D3 で許容した記号名の重複が消える。

### D4: 値型のテスト

`MewbellTests/ThreadPresentationTests.swift` の `ThreadIconTests` の隣（同じファイル）に `TokenStateIconTests` を置き、次を確かめる。

- 状態ごとの名前が spec のとおり（`Getting token`、`Ready`、`Stopped`、`No token`）
- 「止まっている」と「トークンを取れない」は記号と色が同じで、名前が違う
- 取得中だけ `symbol` が nil
- 止まっていない取得の状態（取得中・取得できた・失敗して待っている）と取得の状態が無いときは `Ready`

VoiceOver で実際に読まれることは、ユニットテストでは確かめられないので、手元の VoiceOver で確かめるタスクにする（CLAUDE.md）。

### スレッドと actor の境界

本体の actor と `@MainActor` の境界は変えない。`TokenStateIcon` は `Color` を持つ値型で、View の中（`@MainActor`）で作る。`ThreadIcon` と同じく actor をまたいで渡さない。

### テストでの差し替え

ネットワークと gh サブプロセスには触れないので、差し替えるものは無い。値型のテストは純粋な初期化だけを確かめ、`IconColumnTests` は本物の SwiftUI の配置で記号を測る。

## セキュリティ

トークン・gh サブプロセス・ネットワーク・URL を開く処理のいずれにも触れない。値型が受け取るのはトークンの状態の列挙値（`TokenState`）と取得の状態（`FeedPhase`）だけで、トークンの値は受け取らない。名前は固定の文言だけで、トークンや API の URL、エラーの本文は入らない（A8）。トークンの流れは変わらない。`.claude/rules/security.md` の項目で、この change で新しく満たすものは無い。

## Risks / Trade-offs

- [ボタンのラベルの中の要素に付けた名前が、VoiceOver でボタンの読み上げに含まれないおそれ] → `DisclosureButton` は中身の読み上げを上書きしない作りだが、ユニットテストでは確かめられない。畳める見出し（ボタン）と畳めない見出し（ボタンでない）の両方で、手元の VoiceOver で確かめる（tasks 3.2）
- [`ProgressView` の名前が `.accessibilityLabel` で置き換わらないおそれ] → 同じく手元の VoiceOver で確かめる。置き換わらなければ、`ProgressView(label:)` で名前を渡す形に変える
- [取得中の印に新しくツールチップが出る] → 見た目の変化はこれだけ。spec の「ツールチップにも同じ名前を出す」に合わせたもの
