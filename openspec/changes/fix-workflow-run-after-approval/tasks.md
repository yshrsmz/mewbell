# Tasks

## 1. 通知の時刻を挟む run を選ぶ

- [x] 1.1 `Mewbell/GitHubAPI/WorkflowRunSummary.swift` の `WorkflowRunSummary` に `status` と `runStartedAt` を足し、`static func runSpanning(_ date: Date, in runs: [WorkflowRunSummary], now: Date) -> String?` を置く（design.md D1・D2）。`MewbellTests` の run の選び方のテストに、挟む 1 件（終わった run、動いている run）、挟む 2 件、0 件（通知の前に終わった run、通知の後に始まった run）、日時を読めない run、境界（`run_started_at` と通知が同じ時刻、終わった時刻と通知が同じ時刻）を足す。

## 2. リクエスト

- [x] 2.1 `GitHubAPIClient.fetchApprovalRequestRun` で、承認を待っている run から決まらないときに `fetchRuns(of:query:)` で `created=<=<スレッドの updated_at>&per_page=30` を取り、`runSpanning` で選ぶ（D1・D3）。失敗・認証の失敗・レート制限のときは送らない。
- [x] 2.2 リクエストのテスト（`ThreadDetailsRequestTests+Actions.swift`）: 承認を待っている run が 0 件のとき、`https://api.github.com/repos/octo/app/actions/runs?created=%3C%3D2026-10-08T12:00:00Z&per_page=30` を送り、挟む run を選ぶこと（delta spec の「承認された後の通知」の形）。挟む run が 2 件なら「無い」。承認を待っている run から決まったとき、承認を待っている run の一覧が `502`・`401`・レート制限のときは送らないこと。承認を待っている run の一覧が `404` のときは送ること。`xcodebuild ... test -only-testing:` で該当のスイートを通し、スイート数を確かめる。

## 3. 確認

- [x] 3.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [x] 3.2 `bash scripts/run.sh` で起動し、ログにエラーが無いことを確かめる。（ポーリングが始まり、エラーのログが無いことを確かめた）
- [ ] 3.3 ユーザーが実物で確かめる: すでに承認された承認リクエストの通知（既読にしたものは Web で未読に戻す）をクリックし、承認を待った run のページが開くこと。

## 4. レビュー

- [x] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。（2 件を取り込んだ: run の ID から結果を作る 3 か所を `workflowRunResult` にまとめた、`runStartedAt` に doc コメントを付けた。あわせて、承認待ちの run の後に通知の時刻に動いていた run も探すようになった `fetchWaitingWorkflowRun` を `fetchApprovalRequestRun` に改めた）
- [x] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。（6 件。承認を待っている run を代わりの探し方で拾い直す不具合を直し、実際の形のデータのテストを足した。日時の書き方を明示した。2 件を design の Risks に書いた。1 件は直し方で解消した。理由は PR 本文）
- [ ] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する。
