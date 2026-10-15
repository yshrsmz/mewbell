# Design

## Context

`GitHubAPIClient.fetchApprovalRequestRun` は、`fetchRuns(of:query:endpoints:token:)` で `status=waiting&per_page=6` の run を取り、`approvableRuns` で `pending_deployments` を確かめ、`WorkflowRunSummary.closestRun(updatedNear:in:)` で通知の時刻に最も近い run を選ぶ。決まらなければ `.unavailable` を返し、`ThreadWebURL` は承認待ちの一覧を開く。`WorkflowRunSummary` は `id`・`name`・`conclusion`・`updatedAt`（文字列）を読む。

GitHub の振る舞い（確かめたこと）:

- `GET /repos/{owner}/{repo}/actions/runs?created=<=<日時>` は、その日時以前に作られた run を、新しい順に返す（自分のリポジトリで確かめた）。
- 実物の承認リクエストでは、通知の `updated_at` は承認を待った run の `run_started_at` の数秒後で、その run の `updated_at` は承認の後に終わった時刻だった。

## Goals / Non-Goals

**Goals:**

- Mewbell が初めて見たときにもう承認されていた承認リクエストでも、通知の run を開く。
- 承認を待っている run から決まるときの振る舞いと、リクエストの数は変えない。

**Non-Goals:**

- `CheckSuite` の run の選び方を変えること。
- 承認された run かどうかを確かめること（承認の後は `pending_deployments` が空になり、API で確かめる手段が無い）。
- 開く URL の決まりを変えること。

## Decisions

### D1. 承認を待っている run から決まらないときだけ、通知の時刻を挟む run を探す（A7）

`fetchApprovalRequestRun` の終わりで、承認を待っている run から run が決まらなかった（今 `.unavailable` を返している 3 か所: 0 件、6 件以上か ID が検証を通らない、承認できて近い run が無い）ときに、`fetchRuns(of:query:)` で `created=<=<T>&per_page=30` を取る（`T` はスレッドの `updated_at`）。一時的な失敗・認証の失敗・レート制限のときは、今までどおりその結果で終え、このリクエストは送らない。承認を待っている run の一覧が「無い」（`404` など）だったときは送る（どちらも Actions を読めなければ、同じく「無い」になる）。

承認を待っている run（`status == "waiting"`）は、承認できるかと時刻を 1〜4 で調べて外したものなので、`runSpanning` に渡す前に除く（code-review の指摘で足した。除かないと、ユーザーが承認できない run や、通知の後に待ち始めた run を拾い直してしまう）。選び方は `WorkflowRunSummary` の `static func runSpanning(_ date: Date, in runs: [WorkflowRunSummary], now: Date) -> String?` にする（A7。純粋な関数として単体でテストする）。`run_started_at` が `date` 以前で、終わった時刻（`status == "completed"` なら `updated_at`、そうでなければ `now`）が `date` 以降の run が 1 件だけならその ID、そうでなければ nil。日時を読めない run は数えない。`now` は `GitHubAPIClient` が持つ `now`（テストで差し替えている時計）を渡す。

採らなかった案:

- 承認を待っている run を探さずに、いつも通知の時刻を挟む run だけで決める: 承認を待っている間は、ユーザーが承認できるかを確かめられる今の探し方のほうが確か。リクエストの数も、承認を待っているときは増えない。
- `created` を `<T-24h>..<T>` のように下限も付けて絞る: 下限を決める根拠が無い。`per_page=30` の新しい順で足りる。
- 通知の時刻に `run_started_at` が最も近い run を選ぶ: 長い run の途中で承認を待つ（前のジョブの後に承認のジョブがある）と、近い run が別の run になる。「挟む」なら、承認を待った run が通知の時刻に動いていたことだけを使う。

### D2. 読むフィールドを足す（A1・A9）

`WorkflowRunSummary` に `status: String?` と `runStartedAt: String?` を足す（`updatedAt` と同じく文字列で読み、比べるときに `Date(_:strategy: .iso8601)` で読む）。`closestRun` と同じファイルに置く。

### D3. クエリの日時の書き方（A6）

`T` は `Date.ISO8601FormatStyle(includingFractionalSeconds: false, timeZone: .gmt)`（すべて既読の `last_read_at` と同じ書き方。UTC、秒まで、`Z`）で書き、`<=` とあわせて `URL.appending(queryValue:for:)` でクエリの値にする（`<` と `=` はエスケープされる）。値は API が返した `updated_at` を読み直したものなので、件名のような外からの文字列は入らない。

### D4. 動く場所とテスト（A2・A5）

今の `fetchApprovalRequestRun` と同じく、`AccountPoller`（actor）から呼ぶ `ThreadDetailsFetcher` の中で `GitHubAPIClient` が行う。テストは、`runSpanning` の単体のテスト（挟む 1 件、挟む 2 件、0 件、終わっていない run、日時を読めない run、境界の時刻）と、`FakeHTTPTransport` でリクエストの URL と、承認を待っている run から決まったときと失敗のときに送らないことを確かめるテストにする。

## Risks / Trade-offs

- 同じ時刻に長く走るほかのワークフローがあると、挟む run が 2 件以上になり、承認待ちの一覧を開く（今と同じ）。
- 承認を待った run が、通知の前に作られた最新の 30 件に入らないとき（通知の後ではなく前に、30 件より多くの run が作られた）は見つからない。
- 承認リクエストではない run（同じ時刻にたまたま動いていた 1 件だけの run）を選ぶことがある。承認を待った run も同じ時刻に動いていたはずなので、その run が 1 件だけになることは、承認を待った run が一覧に入っていないときに限られる。
- `status` が `completed` でない run は今を終わりとするので、取ったときに動いている run（承認を待っている run を除く）は、通知の時刻の後に始まっていなければ挟む run に入る。通知の run のほかに、通知の前から動き続けている run があると、決まらずに承認待ちの一覧を開く。
- 承認された run が後で再実行されると、`run_started_at` と `updated_at` は新しい試行の時刻になり、通知の時刻を挟まなくなる。そのときは決まらないか、たまたま挟むほかの run が 1 件だけならその run を開く。

## セキュリティ

- トークンの流れは今の run の検索と同じ。`AccountPoller` が取ったトークンを `GitHubAPIClient` がリクエストごとに `Authorization` に付ける。新しく保持・永続化・ログ出力する箇所は無い。
- 送り先: `endpoints.apiURL(path:)` に検証済みのリポジトリ名を足し、クエリには API が返した日時を書き直した値だけを入れる（D3）。送る前のオリジン検査、リダイレクトの拒否、キャッシュを使わないことは `send` のまま。テストでリクエストの URL を確かめる。
- レスポンス: `id`・`name`・`conclusion`・`status`・`run_started_at`・`updated_at`・`total_count` だけをデコードし、`html_url` などの URL は型に載せない。
- 開く URL の組み立ては変えない（run の ID は今までどおり `ThreadWebURL` が検証してから使う）。
- gh サブプロセス・`hosts.yml`・環境変数には触れない。
