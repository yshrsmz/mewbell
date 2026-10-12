# Design

## Context

スレッドの行の種類のアイコンは `ThreadIcon`（`Mewbell/UI/ThreadEventText.swift`）が種類（`SubjectKind`）と状態（`SubjectState?`）から決める。種類に合う状態があれば状態の記号と色を、無ければ（状態が nil、または Issue に merged のような種類に合わない状態）種類の記号を薄い色で出す。Pull request と Issue の種類の記号は、開いている状態の記号と同じ（`arrow.triangle.pull`、`smallcircle.filled.circle`）で、違うのは色（緑か薄い色か）だけ。

種類は通知の `subject.type` から必ず分かる。状態は、そのあとにイベントを取って初めて分かる（polling「スレッドのイベントの取得」）。スレッドの行には、アイコンのほかに種類を示すものが無い。

## Goals / Non-Goals

**Goals:**

- 状態が分からないときのアイコンを今の形のまま正しいものとし、その理由を残して、同じ指摘がレビューで繰り返されないようにする

**Non-Goals:**

- アイコンの記号・色・VoiceOver の名前を変えること

## Decisions

### D1: 状態が分からないときは、種類のアイコンを薄い色で出す（今の形のまま）

行のアイコンの第一の役目は、その行が Pull request か Issue かを示すことにある。状態は分かったときに足す情報で、分からないときは種類だけを正しく示せばよい。種類の記号をそのまま薄い色で出す今の形は、種類を確実に示し、状態については何も言わない（緑・紫・赤のどの状態の色も付けない）。

開いている状態と形が同じで色だけが違うことは受け入れる。理由:

- 「分からない」は状態ではないので、「状態どうしを形と色の両方で区別する」決まりの対象にしない
- 色を見分けにくい人が「分からない」を「開いている」と取り違えても、種類は正しく伝わる。状態は多くの場合イベントの取得のあとで分かり、アイコンが状態のものに変わる
- VoiceOver では「Pull request」と「Pull request, open」で区別できる

### D2: 記号を変える案は採らない

この change では最初に記号を変える案を立て、手元で 13pt・ライトとダークで描いて見比べた。どれも、PR と Issue を見分けられなくなるか、別の紛らわしさを生むので採らない。

- 両方を `questionmark.circle` にする: 「分からない」ことははっきりするが、見た目で Pull request と Issue の区別がつかなくなる。アイコンの第一の役目（D1）を失うので、今より悪い
- Pull request を `arrow.triangle.branch`、Issue を `circle` にする: branch はマージした Pull request の `arrow.triangle.merge` を上下に反転したような形で、色を見分けにくい人には merged と紛らわしい。薄い色の `circle` は、下書きの Pull request の薄い色の `circle.dashed` と 13pt では見分けにくく、種類を取り違えさせる。どちらも、そのスレッドについて何も表さない新しい形を覚えさせることになる
- Issue を `circle.dotted` にする: 下書きの `circle.dashed` とほとんど同じに見える
- Pull request を `arrow.trianglehead.pull` にする: `arrow.triangle.pull` とほとんど同じ形で、区別の役に立たない
- 開いている状態の記号の側を変える: GitHub で見慣れた形から離れるうえ、Pull request には代わりになる形の違う記号が無い

### スレッドと actor の境界

本体のコードは変えない。

### テストでの差し替え

ネットワークと gh サブプロセスには触れないので、差し替えるものは無い。今の `ThreadIconTests` が、状態が nil のときと種類に合わない状態のときのアイコンを確かめている。

## セキュリティ

トークン・gh サブプロセス・ネットワーク・URL を開く処理のいずれにも触れない。spec の文を変えるだけで、トークンの流れは変わらない。`.claude/rules/security.md` の項目で、この change で新しく満たすものは無い。

## Risks / Trade-offs

- [色を見分けにくい人には、状態が分からない行と開いている行が同じに見える] → 種類は正しく伝わり、取り違えても「開いている」と思うだけで済む。状態は多くの場合イベントの取得のあとで分かる。VoiceOver では区別できる（D1）
