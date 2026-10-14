# Design

## Context

- `AccountPoller`（`Mewbell/Polling/AccountPoller.swift`）は、再読み込みの待ちを `RefreshWaiters` で持つ。`refreshNow()` は、`add` で「次に始める試み（取得の途中なら、その次の試み）」が終わるまで待つ待ちを足す。試みはループの先頭の `startAttempt` で始まり、取得を送るのはその後になる。
- `pendingRefreshCount`（`refreshWaiters.count`）を読むのは、テストの `PollerFixture.waitForPendingRefresh()`（`MewbellTests/Support/PollingFakes.swift`）だけ。この関数は、取得を `FakeHTTPTransport` で止めている間に押した再読み込みが、ポーラーの中で待ちに入るまで待つ。呼んでいるのは 4 か所で、`RefreshNowTests` に 3 つ、`ThreadDetailsPollingTests`（`ThreadDetailsPollingTests+Refresh.swift`）に 1 つある。
- `refreshWaitsForNextFetch`（`refreshWaiters.waitsForLaterAttempt`、今の試みより後の試みを待っている待ちがあるか）は、本体の `AccountPoller+ThreadDetails.swift` が、状態とイベントの取得を始めるかを決めるのに使っている。
- ロガーは型ごとに `Logger(category:)` を持ち、カテゴリはモジュールのディレクトリ名にしている。`App/` でログを出すのは `SingleInstance` だけで、そのカテゴリが `"SingleInstance"` になっている。

## Goals / Non-Goals

**Goals:**

- 本体に、テストのためだけに公開しているメンバーを残さない（A10）。
- ログのカテゴリをモジュールのディレクトリ名に揃える（A11）。

**Non-Goals:**

- A10 の適用外を広げること、テスト用のフックを足すこと。
- 再読み込みの振る舞いと、テストで確かめている内容を変えること。

## Decisions

### D1. テストは、本体が使う `refreshWaitsForNextFetch` で再読み込みの待ちを確かめる（A10）

`waitForPendingRefresh()` の条件を `pendingRefreshCount > 0` から `refreshWaitsForNextFetch` に替え、`pendingRefreshCount` と、ほかに使われていない `RefreshWaiters.count` を消す。

4 か所とも、2 つの条件はテストが待っている間ずっと同じ値になる。

- テストは、取得のリクエストが届いた（`startAttempt` は済んだ）後で、取得を止めている間に `refreshNow()` を呼ぶ。`add` が足す待ちは `attempts + 1` 回目を待つので、待ちに入った直後から `waitsForLaterAttempt` は true になる。
- それが false に戻るのは次の `startAttempt` で、これはテストが取得の止めを解いた後にしか起きない。それまで待ちは起こされないので、`count > 0` も true のままになる。

テストのタイムアウトと、`Issue.record` で失敗を記録する待ち方（`waitUntilAsync`）は変えない。

actor の境界とスレッド: `refreshWaitsForNextFetch` は `AccountPoller` の actor に隔離された計算プロパティで、テストは今と同じく `await` で読む。ネットワークは今までどおり `FakeHTTPTransport`（`HTTPTransport` プロトコル）で差し替え、gh サブプロセスには触れない。

採らなかった案:

- テスト用の待ちのフック（`waitUntilRefreshIsPending()` など）を足し、A10 の適用外を広げる: 適用外にある `AccountStore.waitForReload` と `SystemNotifier.waitForPendingWork` は、本体にもともとある `Task` を待つだけで、状態を足していない。今回は待つ対象の `Task` が無いので、本体にテストのためだけの状態を足すことになる。また、`refreshNow()` が早く戻るとテストが失敗にならずに止まったままになる。
- `pendingRefreshCount` を残して適用外に足す: 本体に要らないものを、文書を変えてまで残す理由が無い。
- 公開されている経路の結果（次の待ちが 10 秒の下限になること）だけで待つ: 取得が終わるのと、再読み込みが actor に入るのとで順序の競合が起き、テストが不安定になる。

### D2. `SingleInstance` のロガーのカテゴリを `"App"` にする（A11）

`Logger(category: "SingleInstance")` を `Logger(category: "App")` にする。どのカテゴリにするかの規則は A11 のとおりで、規則は変えない。カテゴリの文字列を参照している設定・スクリプト・テストは無い（`git grep '"SingleInstance"'` で確かめた）。

### D3. 「既知の逸脱」から 2 行を消す（A10・A11）

スキル `update-architecture-doc` の手順で、`docs/architecture.md` の「既知の逸脱」から A10 と A11 の行を消す。消えるメンバー `pendingRefreshCount` がバッククォート付きで書かれているのはこの行だけなので、`scripts/check-architecture.sh` の「コードの名前」の検査は止まらない。原則の本文・適用外・根拠は変えない。

## Risks / Trade-offs

- [テストの待ちの条件が、本体の判断のためのプロパティに依存する] → `refreshWaitsForNextFetch` の意味が変われば、テストの待ちも変わる。待ちが切れる方向に変われば、`RefreshNowTests` と `ThreadDetailsPollingTests` が失敗して気づく。再読み込みが待ちに入る前に true になる方向に変わると、確かめたい状態に入る前に待ちを抜け、確かめていないのに通りうる。プロパティの意味を変える change では、`waitForPendingRefresh()` も見直す。
- [`waitForPendingRefresh()` を、取得を止めていない場面で使うと待ちが切れる] → 新しい条件は、次の試みが始まると false に戻る（前の条件は、待ちが起こされるまで true だった）。ヘルパーの doc コメントに、取得を止めている間に押した再読み込みにだけ使うことを書く。
- [Console でカテゴリ `SingleInstance` を指定して絞っていた人は、ログが見えなくなる] → 配布物で決まったカテゴリを約束してはいない。ほかのモジュールと同じく `App` で絞れるようになる。

## セキュリティ

トークンの流れは変えない。トークンは `gh auth token` の標準出力から取得し、actor の中にだけ持つ。`AccountPoller` は取得のたびに `TokenProviding` から受け取って `GitHubAPIClient` に渡し、アカウントの削除と終了時に捨てる。この change はそのどこにも触れない。

`.claude/rules/security.md` の項目への対応: ログはカテゴリだけを変え、メッセージと可変値の伏せ方（既定の `.private`）は変えない。`print` も使わない。トークンの扱い・gh サブプロセス・ネットワーク・URL を開く処理・アプリとビルドの設定・依存には触れないので、該当しない。
