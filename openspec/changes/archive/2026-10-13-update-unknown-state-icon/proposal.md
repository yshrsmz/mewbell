# Proposal

## Why

ui の Requirement「スレッドの行の状態のアイコン」は、状態を記号の形と色の両方で区別するよう求めている。一方で、状態が分からない Pull request・Issue には、開いている状態と同じ記号を薄い色で出している（違うのは色だけ）。「分からない」がこの決まりの対象の状態に入るのかが書かれていないので、この食い違いが fix-thread-icon-column のレビューで何周も続けて指摘された。

状態が分からなくても、スレッドの種類（Pull request か Issue か）は通知から必ず分かる。種類を表すアイコンを中立の薄い色で出す今の振る舞いは、そのままでよい。この change は、それを spec にはっきり書き、同じ指摘が出ないようにする。

この change は、M4（設定と操作）の UI の仕様の整理にあたる（M5 の v0.1.0 の公開後）。

## What Changes

- ui の Requirement「スレッドの行の状態のアイコン」を書き直す（MODIFIED）
  - 「分からない」・状態が付いていない・種類に合わない状態は、状態として扱わず、種類だけを表すアイコンを薄い色で出す
  - 形と色の両方で区別する決まりは、状態どうしにだけ適用する。種類だけのアイコンは、開いている状態のアイコンと形が同じで色だけが違ってもよい
  - 状態が分からないことを示すために、種類が見分けられなくなる記号（種類によらない疑問符など）を使わない
  - VoiceOver では種類だけを読む
  - 状態が分からない Issue と、種類に合わない状態の Scenario を足す
- 本体のコードは変えない。今の `ThreadIcon` は書き直した Requirement を満たしている。`ThreadIconTests` に、状態が分からない Pull request・Issue の名前と、2 つの記号が違うことを確かめるテストを足す
- 記号を変える案（疑問符の丸、枝分かれの矢印と空の丸など）を検討して採らなかった理由と、今の形のほうがよい理由を design.md に残す

## Capabilities

### New Capabilities

（なし）

### Modified Capabilities

- `ui`: Requirement「スレッドの行の状態のアイコン」の、状態が分からないときのアイコンの決まりをはっきりさせ、Scenario を足す（MODIFIED）。表示は変わらない

## Impact

- 変わるコード: 本体は無し。`MewbellTests/ThreadPresentationTests.swift`（`ThreadIconTests`）と `openspec/specs/ui/spec.md`
- 見た目: 変わらない
- トークン: 扱わない。何も永続化しない
- gh サブプロセス: 触れない
- ネットワーク: 触れない
- URL を開く処理: 触れない
- 外部依存: 追加しない
