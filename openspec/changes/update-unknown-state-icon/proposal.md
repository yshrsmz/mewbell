# Proposal

## Why

スレッドの行の種類のアイコンで、状態が分からない Pull request と Issue は、開いている Pull request・Issue と同じ記号（`arrow.triangle.pull`、`smallcircle.filled.circle`）を使っている。違うのは色だけ（開いているときは緑、分からないときは薄い色）なので、色の区別がつきにくい人には「開いている」と「分からない」を見分けられない。ui の Requirement「スレッドの行の状態のアイコン」は状態どうしを形と色の両方で区別するよう求めているが、「分からない」は状態として扱っておらず、この食い違いが fix-thread-icon-column のレビューで続けて指摘された。

この change は、M4（設定と操作）の UI の改善にあたる（M5 の v0.1.0 の公開後）。

## What Changes

- 状態が分からない（イベントをまだ取っていない、取れなかった、種類に合わない状態が付いている）Pull request の記号を `arrow.triangle.branch` に、Issue の記号を中が空の `circle` にする。色は今までどおり薄い色
- 開いている・下書き・マージした・閉じたなどの状態の記号と色は変えない
- 状態を持たない種類（Commit、Release、Discussion、Check suite、その他）のアイコンは変えない
- VoiceOver の名前は今までどおり種類だけ（「Pull request」「Issue」）
- ui の Requirement「スレッドの行の状態のアイコン」の「状態が分からないときは今までどおり種類だけを表すアイコン」を書き直し、状態が分からない Pull request・Issue は、どの状態のアイコンとも形が違う記号で出すことにする（MODIFIED）

## Capabilities

### New Capabilities

（なし）

### Modified Capabilities

- `ui`: Requirement「スレッドの行の状態のアイコン」の、状態が分からないときのアイコンの決まりと Scenario を書き直す（MODIFIED）

## Impact

- 変わるコード: `Mewbell/UI/ThreadEventText.swift`（`ThreadIcon`）、`MewbellTests/ThreadPresentationTests.swift`（`ThreadIconTests`）
- 見た目: 状態が分からない Pull request・Issue の行のアイコンの形だけが変わる。新しい記号は 13pt で `arrow.triangle.branch` が 16pt 幅（倍率 2 で 15pt）、`circle` が 15pt 幅で、24pt のアイコンの列に収まる（`IconColumnTests` がすべての記号を測る）
- トークン: 扱わない。何も永続化しない
- gh サブプロセス: 触れない
- ネットワーク: 触れない
- URL を開く処理: 触れない
- 外部依存: 追加しない
