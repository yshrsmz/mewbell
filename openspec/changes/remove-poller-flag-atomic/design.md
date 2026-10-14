# Design

## Context

- `AccountPoller`（`Mewbell/Polling/AccountPoller.swift`）は 1 アカウントの取得を受け持つ actor。actor の外から同期的に触る状態は、走っているループの `loop`（`Mutex`）と、条件なしの取得の印 `unconditionalRequested`（`Atomic<Bool>`）の 2 つを `nonisolated let` で持っている。
- `loop` は `start()`・`resume()`・`stop()`（いずれも `nonisolated`）から触るので、`Mutex` が要る。
- `unconditionalRequested` を触るのは次の 5 か所で、どれも actor に隔離されたメソッドの中にある。
  - 立てる: `refreshNow()`（`private nonisolated func requestUnconditionalFetch()` を通す）、`perform(_:)` と `markAllRead(through:)`（`AccountPoller+ThreadActions.swift`、直接 `store`）、`fetch(with:)` で条件なしの取得を取り終えられなかったとき（直接 `store`）
  - 下ろす: `fetch(with:)` の先頭の `exchange(false, ordering: .relaxed)`
- テストは印を直接触らない。振る舞いは `UnconditionalFetchTests`・`RefreshNowTests`・`MarkReadPollingTests`・`DonePollingTests`・`MarkAllReadPollingTests` が、送ったリクエストの `If-Modified-Since` で確かめている。

## Goals / Non-Goals

**Goals:**

- 印の持ち方を A2 に合わせ、actor の外から触る経路が無いことを型で表す。
- 印を立てる書き方を 1 通りにする。

**Non-Goals:**

- 条件なしにする時機（再読み込み、操作の後、5 分ごと、取り終えられなかったとき）を変えること。
- `loop` の `Mutex` や、ほかの状態の持ち方を変えること。A2 は書き方を今のコードに合わせるだけで、原則の意味は変えない（D2）。
- テストを足す・変えること。振る舞いを変えないので、既存のテストがそのまま通ることで確かめる。

## Decisions

### D1. 印を actor の `var` にし、立てる・下ろすを代入で書く（A2）

`nonisolated let unconditionalRequested = Atomic(false)` を `var unconditionalRequested = false` にする。置き場所は `hidden`・`readThroughs` と同じ actor の状態の並びにし、`AccountPoller+ThreadActions.swift` の extension から書けるように `private` にしない（ファイル先頭のコメントの方針どおり）。`requestUnconditionalFetch()` の doc にあった「取得を早めはしない」は、印のコメントに移す。

`fetch(with:)` では、今の `exchange` と同じく、取得を送る前（最初の `await` の前）に `let requested = unconditionalRequested` と `unconditionalRequested = false` を続けて書く。actor は `await` の間に再入できるので、取得の途中に `refreshNow()`・`perform(_:)`・`markAllRead(through:)` が立てた印は、下ろした後に立つ。今と同じく、その印は次の取得まで残る。読んでから下ろすまでの間に `await` は無いので、その間に印が立つことは無い。

actor の境界とスレッド: 印を読み書きするのは、すべて `AccountPoller` の actor の上で動くコードだけになる。`nonisolated` の入口（`start()`・`resume()`・`stop()`）は印を触らない。

採らなかった案:

- `Atomic` のまま、4 か所を `requestUnconditionalFetch()` 経由にする: 書き方は 1 通りになるが、actor の外から触る経路が無いのに `Atomic` と `nonisolated` が残り、A2 の条件と合わない。
- `Atomic` のまま `requestUnconditionalFetch()` を消し、4 か所を `store` で直接書く: 書き方は揃うが、`Atomic` を残す理由が無いのは同じ。
- 印を立てる `private` のメソッドを actor に残す: 代入 1 行を包むだけで、`hidden` などのほかの状態は直接書いているので、書き方が増えるだけになる。

### D2. A2 の「actor の外から同期的に触る状態」の書き方を、今のコードに合わせる（A2）

A2 は「actor の外から同期的に触る状態は `Mutex` や `Atomic` で持つ」と型の名前を挙げている。D1 で `Atomic` を使う箇所が無くなるので、`scripts/check-architecture.sh` の「コードの名前」の検査で止まる。A2 から `Atomic` の名前を外し、外から触る状態は `Synchronization` の型（`Mutex` など）で持つことと、中だけで触る状態は actor の `var` で持つことを書く。根拠に D1 を足す。スキル `update-architecture-doc` の手順で更新する。原則の意味（外から同期的に触る状態だけを同期の型で持つ）は変えず、今の形を書き、D1 の判断（中だけで触るなら `var`）を書き足す。

採らなかった案:

- 「`Mutex` で持つ」だけにする: `Atomic` は単一の値（フラグやカウンタ）を actor の外から触るときの Swift の慣用の道具で、使ってはいけないわけではない。`Mutex` だけを挙げると、外から触るフラグを足すときに `Atomic` を選べないように読める。
- `Atomic` をバッククォートなしで残す: 型名はバッククォートで書くという文書の書式に反し、検査を避けるためだけの書き方になる。

「既知の逸脱」には載っていないので、行の増減は無い。

## Risks / Trade-offs

- [`exchange` を 2 行に分けると、読んでから下ろすまでの間に立った印を消してしまう] → 2 行の間に `await` を置かない。actor の中では `await` の外で割り込まれないので、`exchange` と同じ結果になる。取得の途中で押された再読み込みが次の取得を条件なしにすることは、`RefreshNowTests` と `UnconditionalFetchTests` で確かめる。

## セキュリティ

トークンの流れは変えない。トークンは `AccountPoller` が `TokenProviding` から受け取り、取得のたびに引数で `GitHubAPIClient` に渡す。印はトークンを持たず、`If-Modified-Since` を付けるかだけを決める。

`.claude/rules/security.md` の項目への対応: トークンの扱い・gh サブプロセス・ネットワーク（送り先・リダイレクト・ヘッダー・キャッシュ）・URL を開く処理・アプリとビルドの設定・依存のいずれにも触れないので、該当しない。
