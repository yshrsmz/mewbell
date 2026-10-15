# Design

## Context

`AccountPoller.fetch(with:)` は、`GitHubAPIClient.fetchNotifications` の `.updated(threads:...)` を受け取ると、`HiddenThreads.revealOrHide` で隠すスレッドを除き、`prefetchNewDetails` で新着の状態とイベントを取り、`details.listed(fetched)` で記録を整理する。その後、`lastFullFetch` を今の時刻にする。`handle` は `state.threads = details.attach(to: threads)` で一覧を置き換え、`FeedRecorder.recordFetch` は `state.isTruncated` をその取得の打ち切りにする。この流れは、送った取得に `If-Modified-Since` を付けたかどうかで分かれていない。

`NotificationStore.apply` は、ポーラーが知らせた `FeedState` を `ThreadChangeDispatcher` に渡す。`NotificationTracker.update` は、前の一覧にあって新しい一覧に無い ID を取り下げの対象にする。ポーラーが知らせる一覧が正しければ、store と tracker は変えなくてよい。

GitHub の振る舞い（手元で確かめた）: `If-Modified-Since` を付けた `200` は、その時刻より後に `updated_at` が進んだスレッドだけを返し、`Last-Modified` は返したスレッドの `updated_at` の最新値になる。

## Goals / Non-Goals

**Goals:**

- 条件付きの `200` で、受け取らなかったスレッドを一覧から外さない（macOS の通知も取り下げない）。
- 条件なしの取り直しの 5 分を、条件なしの `200` から数える。
- 打ち切りの値を、一覧の中身に合わせる。

**Non-Goals:**

- API の呼び出しの回数・間隔・リクエストの形は変えない。
- 5 分ごとの条件なしの取得で直しているずれ（古いスレッドが未読に戻った、ほかの場所で既読にした）を、それより早く直すことはしない。
- `NotificationStore`・`NotificationTracker`・`ThreadChangeDispatcher` は変えない。

## Decisions

### D1. 重ねる処理はポーラーで行い、判断は純粋な関数に切り出す（A3・A7）

一覧の正本はポーラーが持つ（A3）。条件付きの `200` の一覧は、ポーラーが今の `state.threads` に重ねてから `handle` に渡す。store と tracker には今までどおり全体の一覧が届くので、取り下げの判定（`NotificationTracker`）は変えずに正しくなる。

重ね方は `Mewbell/Polling/ThreadListMerge.swift` の `enum ThreadListMerge` の `static func merge(_ fetched: [NotificationThread], into current: [NotificationThread]) -> [NotificationThread]` にする（A7。actor を組まずに差し替え・追加・残すの境界をテストする）。結果は、受け取ったスレッドを受け取った順に並べ、その後に `current` のうち受け取ったスレッドと ID が重ならないものを `current` の順に並べる。並べ替えはしない（一覧の並びは `RepositoryGroup.groups` が決める）。`current` のスレッドに付いている `details` は使わない（`handle` が `details.attach` で付け直す）。

採らなかった案:

- `HiddenThreads` に足す: 隠すスレッドの判断とは役割が違う（A9 は役割でまとめる）。
- 型を足さずに `AccountPoller` の中に書く: 差し替えと残すの境界を確かめるテストに、偽物の API と時刻を組む必要がある。A7 の「判断は切り出す」に反する。
- 条件付きの取得をやめる（毎回条件なしで取る）: ユーザーが採らなかった。API の消費が増え、CLAUDE.md の約束（`If-Modified-Since` を送る）も変えることになる。

### D2. 重ねる時点と、隠すスレッドの扱い（A3・A7）

`fetch(with:)` の今の順序（隠す → 状態とイベントを取る → もう一度隠す → 記録の整理）は保つ。条件付きの取得のときは、状態とイベントを取った後、2 回目の `revealOrHide` の前に `ThreadListMerge.merge(threads, into: state.threads)` で重ねる。状態とイベントを取っている間（actor の再入がある）に既読・Done・すべて既読で `state.threads` から外したスレッドは、重ねる元に入らない。受け取ったスレッドに入っていても、2 回目の `revealOrHide` で取り除かれる。

`prefetchNewDetails` に渡すのは、重ねる前の受け取ったスレッドのままにする。新着の判定（`ThreadDetailsCache.pending(newOnly: true)`）は前に知らせた一覧と比べるので、重ねた一覧を渡しても結果は変わらない。受け取ったスレッドだけを見るほうが軽い。

`details.listed` には、条件なしの取得では今までどおり受け取ったスレッド（隠したものを含む）を、条件付きの取得では `ThreadListMerge.merge(fetched, into: state.threads)`（隠す前の受け取ったスレッドを今の一覧に重ねたもの）を渡す。これで条件付きの取得では、一覧に残るスレッドの状態とイベントの記録が捨てられない（polling「スレッドのイベントの取得」の「一覧から消えたスレッドの分は捨てる」に合う）。

### D3. 条件付きかどうかは、送ったリクエストで決める（A3）

`fetch(with:)` はすでに `ifModifiedSince` を決めている。`ifModifiedSince != nil` のときの `200` を条件付きの `200` とする。`NotificationsFetchResult` と `GitHubAPIClient` は変えない（受け取った結果が差分かどうかは、送った側が知っている）。

### D4. 5 分の起点（A3）

`lastFullFetch` は、条件なしの取得の `200` のときだけ今の時刻にする。条件付きの `200` では変えない。名前は役割に合わせて `lastUnconditionalFetch` にし、doc コメントを直す。`PollSchedule.unconditionalFetchIsDue(lastFullFetch:...)` の引数名も同じに変える。`docs/architecture.md` にはどちらの名前も書かれていない（grep で確かめた）。

### D5. 打ち切り（A7）

条件付きの `200` では、`handle` に渡す `.updated` の `truncated` を「受け取った取得の打ち切り または 今の `state.isTruncated`」にする。`FeedRecorder.recordFetch` は変えない（受け取った値をそのまま入れる）。

### D6. 動く場所とテストの差し替え（A2・A5・A12）

重ねる処理・5 分の起点・打ち切りは、すべて `AccountPoller`（actor）の中の `fetch(with:)` で行う。`ThreadListMerge.merge` は同期の純粋な関数なので、actor の中で呼んでも待ちは増えない。`@MainActor` の `NotificationStore` に届くのは、今までどおり `onUpdate` で知らせる `FeedState` だけ。

テストは、`ThreadListMerge` を単体で確かめるものと、既存の `PollerFixture`（`FakeHTTPTransport` で API を、偽の `sleep` と `now` で時刻を差し替える）でポーラーの振る舞いを確かめるものに分ける。ポーラーのテストは、条件付きの `200` で古いスレッドが残ること、隠しているスレッドが戻らないこと、5 分の起点、打ち切りを、削ったら見逃す不具合として置く（A12）。store を通したテストで、条件付きの `200` の後に macOS の通知が取り下げられないことも確かめる。

## Risks / Trade-offs

- 条件付きの `200` の後も、一覧から消えるべきスレッド（ほかの場所で既読にした）は、次の条件なしの取得（最大 5 分後）まで残る。今の `304` のときと同じずれで、仕様どおり。
- 隠しているスレッドのうち、条件付きの `200` で受け取らなかったものは、`details.listed` に渡す一覧に入らないので、状態とイベントの記録が捨てられる。既読化に失敗して一覧に戻ったときに、状態とイベントを取り直す。API の呼び出しが 1〜2 回増えるだけで、表示は変わらない。
- 既存のテストのうち、条件付きの `200` で一覧が置き換わることを前提にしたもの（`UnconditionalFetchTests.countsAConditional200AsAFullFetch` など）は、新しい振る舞いに合わせて直す。

## セキュリティ

- トークンの流れは変えない。トークンは `tokens.currentToken(for:)` で取り、`fetchNotifications` に渡すだけで、新しく保持・送信・ログ出力する箇所は無い。
- `.claude/rules/security.md` の各項目: gh サブプロセス・ネットワーク（送り先、オリジン検査、リダイレクト、キャッシュ）・URL を開く処理には触れないので該当しない。重ねる処理はメモリの中の `NotificationThread` の配列だけを扱い、ディスクやログに書かない。
