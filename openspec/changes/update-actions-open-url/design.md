# Design

## Context

スレッドを開く URL は `ThreadWebURL.make(for:endpoints:)` が決め、一覧のクリック（`NotificationStore.open`）と macOS の通知（`ThreadNotificationContent`）の両方が使う。Release は、`ThreadWebURL.detailsSubject` が `DetailsSubject.release(id:)` を決め、`ThreadDetailsFetcher` → `GitHubAPIClient.fetchDetails` → `fetchReleaseTag` で取ったタグを `ThreadDetails.releaseTag` に入れ、`ThreadDetailsCache` がスレッドの ID と `updated_at` の組ごとに覚え、`ThreadWebURL.target` がタグを見て個別のページにする。新着は一覧を知らせる前に取る（`prefetchNewDetails`）ので、macOS の通知の URL にも間に合うことが多い。

`SubjectKind` は `CheckSuite` を持つが、`WorkflowRun` は `.other("WorkflowRun")` になる。どちらも `ThreadWebURL.target` が nil を返すので、リポジトリのページが開く。

確かめたこと:

- `GET /repos/{owner}/{repo}/actions/runs` の run は、`name` がワークフロー名、`display_title` が実行の表示名（自分のリポジトリで確かめた）。`status` には `waiting` があり、Actions だけが付ける（REST のドキュメント）。
- `pending_deployments` の要素は `current_user_can_approve`（必須の真偽値）を持つ（REST のドキュメント）。
- Foundation の `URLQueryItem` は `&` と `=` をエスケープするが、`+` はそのまま残す（手元で確かめた）。

## Goals / Non-Goals

**Goals:**

- `WorkflowRun` と `CheckSuite` のスレッドを、run が決まれば run のページで、決まらなければ絞り込んだ Actions の一覧で開く。
- Release のタグと同じ仕組みに乗せ、取得の上限・隠す・止める・レート制限の扱いを今と同じにする。

**Non-Goals:**

- 一覧の行に run の状態（成功・失敗）や承認待ちを出すこと。
- `WorkflowRun` と `CheckSuite` のアイコンを変えること。
- 件名の言語が英語以外になる場合への対応（GitHub は英語で送る）。

## Decisions

### D1. 種類と詳細の行き先（A1・A9）

`SubjectKind` に `.workflowRun`（API の値 `WorkflowRun`）を足す。`DetailsSubject` に `.waitingWorkflowRun`（承認を待っている run を探す）と `.checkSuite(CheckSuiteTitle)`（件名から探す）を足す。`ThreadDetails` に `workflowRunID: String?`（1〜20 桁の数字）を足す。

`ThreadWebURL.detailsSubject` に `title` の引数を足す。種類が `.workflowRun` なら `.waitingWorkflowRun`、`.checkSuite` で件名を読めれば `.checkSuite(...)` にする。どちらも `subject.url` を見ない（proposal の前提）。リポジトリのページを開けない（`url(...)` が nil）ときは、今までどおり nil にする。

`ThreadIcon` は網羅の `switch` なので、`.workflowRun` の記号は `.other` と同じ `bell`、名前は「Workflow run」にする。

採らなかった案:

- `.other("WorkflowRun")` のまま文字列で見分ける: 開く URL・詳細の行き先・名前の 3 か所で同じ文字列を比べることになる。

### D2. 件名を読む型（A7・A9）

`Mewbell/GitHubAPI/CheckSuiteTitle.swift` に `struct CheckSuiteTitle: Hashable, Sendable` を置く。`init?(_ title: String)` が件名を読み、`workflowName`・`result`（`enum Result { case failed, failedAtStartup, cancelled, skipped, succeeded }`）・`branch` を持つ。試行の回数は読むが持たない（run を選ぶのにも開く URL にも使わない）。リクエストのクエリ（D4）と、決まらないときの絞り込みの一覧（D5）の 2 か所が使うので、どちらからも見える `GitHubAPI` に置く（A1）。

採らなかった案:

- 正規表現の文字列を `GitHubAPIClient` と `ThreadWebURL` の両方に書く: 同じ形の検証が 2 か所に分かれる。

### D3. クエリの値のエスケープ（A6）

`+` を `%2B` にエスケープしてクエリを付ける処理を、`Mewbell/GitHubAPI/URL+QueryValue.swift` の `extension URL { func appending(queryValue value: String, for name: String) -> URL }` の 1 か所に置く。API のリクエスト（ブランチ）と Web の URL（絞り込み）の両方がこれを使う。`URLComponents.percentEncodedQueryItems` に、`URLQueryItem` と同じエスケープに `+` を加えた値を入れる。

### D4. run を探す（A5・A7）

`GitHubAPIClient.fetchDetails` の `switch` に 2 つの場合を足し、`fetchReleaseTag` と同じ並びに `private func fetchWaitingWorkflowRun` と `private func fetchCheckSuiteRun` を置く。状態コードの扱いは今の `get(_:endpoints:token:)` をそのまま使う（`404` / `410` / `422` と、レート制限でない `403` は「無い」）。`pending_deployments` は候補ごとに順に送り、どれかが一時的な失敗・認証の失敗・レート制限になったら、その結果で終える。`404` などで「無い」なら、その run は承認できないものとして数える。

レスポンスは `Decodable` の `private struct` で、使うフィールドだけを持つ（`WorkflowRunsPage { totalCount: Int; workflowRuns: [WorkflowRunSummary] }`、`WorkflowRunSummary { id: Int64; name: String?; updatedAt: Date }`、`PendingDeployment { currentUserCanApprove: Bool }`）。`id` は文字列にして `ThreadID.isValid` を通す。

`CheckSuite` の run の選び方（名前が一致し、`updated_at` の差が 10 分以内で最も近いもの。同じ差が 2 件なら決めない）は、`WorkflowRunSummary` の配列とスレッドの `updated_at` を受け取る `static` の純粋な関数にし、単体でテストする（A7）。

テストは今の `FakeHTTPTransport`（`HTTPTransport` のプロトコルの偽物）で API を差し替える（A5）。

### D5. 開く URL（A6）

`ThreadWebURL.Target` に `.workflowRun(String)`（`["actions", "runs", id]`）と `.actions(query: String?)`（`["actions"]` と、あれば `query`）を足す。`url(repository:target:endpoints:)` は、パスを足した後に `query` があれば D3 の関数で付ける。`isOpenable` の検査は今と同じ。

`target` は、種類が `.workflowRun` なら `details?.workflowRunID` があれば `.workflowRun`、無ければ `.actions(query: "is:waiting")`。`.checkSuite` なら `workflowRunID` があれば `.workflowRun`、無ければ `CheckSuiteTitle` から作った絞り込み（ui の delta spec の順）で `.actions(query:)`、件名を読めなければ `.actions(query: nil)`。`make(for:)` に `workflowRunID` と件名を渡す（今の `releaseTag` と同じ）。

### D6. 動く場所（A2）

run を探すのは、今のイベントの取得と同じく `AccountPoller`（actor）の `prefetchNewDetails` と `fillDetails` から呼ぶ `ThreadDetailsFetcher` の中で、`GitHubAPIClient`（`Sendable` な struct）が行う。`@MainActor` の `NotificationStore` と View は、今までどおり `FeedState` のスレッドに付いた `ThreadDetails` を読むだけ。1 アカウントで同時に取るスレッドは 4 件のままで、1 つのスレッドの中のリクエストは順に送る。

## Risks / Trade-offs

- 承認を待っている run を見つけた後に承認されても、覚えた run の ID はそのスレッドの `updated_at` が変わるまで使う。開くページはその run なので、結果を確かめられて困らない。
- 承認を待っている run が複数あって決まらないとき、承認者が自分でない run が 1 件だけ待っているとき（`pending_deployments` を見ないので、その run を開く）は、目的と違う run か一覧を開く。一覧の絞り込み（`is:waiting`）で探せる。
- `CheckSuite` の通知の `updated_at` が run の `updated_at` と 10 分より離れている（再実行の後など）と、run は決まらず絞り込みの一覧を開く。ブランチの run が多くて最新の 30 件に入らないときも同じ。
- 件名の形は GitHub が決めていて、文書は無い。形が変わったら読めずに、`CheckSuite` は `/actions` を開く（今のリポジトリのトップより悪くはならない）。
- API の呼び出しが、Actions の通知 1 件につき最大 6 回（`WorkflowRun`）か 1 回（`CheckSuite`）増える。`updated_at` が変わるまで取り直さない。

## セキュリティ

- トークンの流れ: 今のイベントの取得と同じく、`AccountPoller` が `tokens.currentToken(for:)` で取り、`ThreadDetailsFetcher` から `GitHubAPIClient` に渡し、`send` がリクエストごとに `Authorization` に付ける。新しく保持・永続化する箇所は無く、アカウントが止まったら今までどおり捨てる。
- 送り先: リクエストの URL は `endpoints.apiURL(path:)` で、検証済みのリポジトリ名と、`ThreadID.isValid` を通した run の ID から組み立てる。件名から読んだブランチはクエリの値として D3 でエスケープするだけで、パスには入れない。送る前のオリジン検査（`send` の中）、リダイレクトの拒否、キャッシュを使わないことは今と同じ。テストで、組み立てた URL、`+`・`&`・`=` を含むブランチのエスケープ、別のオリジンへのリダイレクトを拒むことを確かめる。
- レスポンス: `id`・`name`・`updated_at`・`total_count`・`current_user_can_approve` だけをデコードし、`html_url` などの URL は型に載せない。本文をログに出さない。
- 開く URL: Web ベース URL に検証済みのリポジトリ名・run の ID・エスケープしたクエリを足し、`isOpenable`（`https` でホストが一致）を通したものだけを開く。テストで、`html_url` が別のホストを指していても開かないこと、件名に `"`・`&`・`#` が入っても URL の意味が変わらないことを確かめる。
- gh サブプロセス・`hosts.yml`・環境変数には触れない。
