# Design

## Context

スレッドの行の種類のアイコンは `ThreadIcon`（`Mewbell/UI/ThreadEventText.swift`）が種類（`SubjectKind`）と状態（`SubjectState?`）から決める。種類に合う状態があれば `stateIcon(kind:state:)` の記号・色・状態の名前を使い、無ければ（nil、または Issue に merged のような種類に合わない状態）`kindSymbol(_:)` の記号を薄い色（`color == nil`）で出す。`kindSymbol` が Pull request と Issue に返す記号は、開いている状態の記号と同じ（`arrow.triangle.pull`、`smallcircle.filled.circle`）。

記号は 24pt のアイコンの列（`ListLayout.iconColumnWidth`）に書体の大きさのまま収まらなければならない。`IconColumnTests.fitsEveryThreadIcon` は種類と状態（nil を含む）のすべての組の記号を測るので、記号を変えれば自動で測られる。

## Goals / Non-Goals

**Goals:**

- 状態が分からない Pull request・Issue のアイコンを、その種類のどの状態のアイコンとも形で見分けられるようにする

**Non-Goals:**

- 状態のある記号・色、状態を持たない種類の記号を変えること
- VoiceOver の名前を変えること（種類だけのまま）
- 新しい型や、記号の部品化

## Decisions

### D1: 記号は `arrow.triangle.branch`（Pull request）と `circle`（Issue）

13pt・ライトとダークで候補を描いて見比べ、ユーザーが選んだ。

- Pull request: `arrow.triangle.branch` は枝分かれの形で、ブランチを表すので Pull request と結びつき、`arrow.triangle.pull`（open）・`arrow.triangle.merge`（merged）・丸の記号（draft・closed）のどれとも形が違う
- Issue: 中が空の `circle` は、Issue の丸の外形を残しつつ、open（中に点）・closed as completed（チェック）・closed as not planned（斜線）のどれとも形が違う

検討した代わりの案:

- `questionmark.circle` を両方に使う: 「分からない」ことははっきりするが、見た目で Pull request と Issue の区別がつかなくなる
- `circle.dotted`（Issue）: 点線の丸が Pull request の下書き（`circle.dashed`）と見分けにくい
- `arrow.trianglehead.pull`（Pull request）: `arrow.triangle.pull` とほとんど同じ形
- 開いている状態の記号の側を変える: GitHub の見慣れた形から離れ、Pull request には形の違う代わりの記号が無い

新しい記号の配置の幅は、13pt で `arrow.triangle.branch` が 16pt（倍率 2 で 15pt）、`circle` が 15pt で、24pt の列に収まる。

### D2: `kindSymbol` は「状態で決まらないときの記号」として残す

`init` の分岐（種類に合う状態があれば状態の記号、無ければ種類の記号）は変えず、`kindSymbol(_:)` が Pull request と Issue に返す記号だけを D1 のものにする。名前は `fallbackSymbol(_:)` に改め、状態を持たない種類ではいつも、Pull request と Issue では状態が分からないときに使う記号だと doc に書く。種類に合わない状態は、状態が無いときと同じアイコンのまま（`ThreadIconTests.fallsBackToTheKindWithoutAMatchingState`）。

### D3: テスト

`ThreadIconTests.distinguishesStatesByShape` の Pull request と Issue の記号の集まりに、状態が nil のアイコンを加え、すべての記号が互いに違うことを確かめる。状態が nil のときの色が nil（薄い色）で名前が種類だけであることは、今の `fallsBackToTheKindWithoutAMatchingState` が確かめている。列に収まることは `IconColumnTests` が確かめる。

### スレッドと actor の境界

本体の actor と `@MainActor` の境界は変えない。変わるのは `ThreadIcon` の記号の文字列だけ。

### テストでの差し替え

ネットワークと gh サブプロセスには触れないので、差し替えるものは無い。

## セキュリティ

トークン・gh サブプロセス・ネットワーク・URL を開く処理のいずれにも触れない。変えるのは行のアイコンの記号だけで、トークンの流れは変わらない。`.claude/rules/security.md` の項目で、この change で新しく満たすものは無い。

## Risks / Trade-offs

- [`arrow.triangle.branch` は列の中で幅が広め（16pt）で、ほかの行のアイコンと見た目の重さが少し違う] → 列の中央に置くので揃いは崩れない。手元の画面で見え方を確かめる（tasks 2.2）
- [薄い色の `circle` が、何も無い丸に見えて意味が伝わりにくい] → 状態が分からないことを示す形として、ほかの状態と見分けられることを優先する。VoiceOver では「Issue」と読まれる
