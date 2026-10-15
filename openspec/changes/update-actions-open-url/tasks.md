# Tasks

## 1. 種類と件名

- [x] 1.1 `SubjectKind` に `.workflowRun`（API の値 `WorkflowRun`）を足し、`ThreadIcon` の記号を `bell`、名前を「Workflow run」にする（design.md D1）。`MewbellTests` の `SubjectKind` の読み取りと `ThreadIcon` の名前のテストに `WorkflowRun` を足す。
- [x] 1.2 `Mewbell/GitHubAPI/CheckSuiteTitle.swift` に `CheckSuiteTitle` を置く（D2）。`MewbellTests/CheckSuiteTitleTests.swift` で、5 つの結果、`, Attempt #2` 付き、`/` と `+` を含むブランチ、空白を含むワークフロー名、読めない件名（形が違う、知らない結果、空のワークフロー名やブランチ、255 バイトを超える値、制御文字）を確かめる。
- [x] 1.3 `Mewbell/GitHubAPI/URL+QueryValue.swift` に `appending(queryValue:for:)` を置く（D3）。`+`・`&`・`=`・`#`・`"`・空白・`/`・`:` を含む値で、手元で確かめた形（`:` と `/` はそのまま、空白は `%20`、`"` は `%22`、`+` は `%2B`）になることをテストする。

## 2. run を探す

- [x] 2.1 `DetailsSubject` に `.waitingWorkflowRun` と `.checkSuite(CheckSuiteTitle)` を、`ThreadDetails` に `workflowRunID` を足す。`ThreadWebURL.detailsSubject` に `title` を足し、種類で決める（D1）。`ThreadDTO.thread(endpoints:)` から件名を渡す。`subject.url` が無いか別のリポジトリを指していても、`WorkflowRun` と `CheckSuite`（件名を読めるもの）は詳細の行き先を持つことをテストする。
- [x] 2.2 `GitHubAPIClient` に `fetchWaitingWorkflowRun` を置く（D4）。`MewbellTests` の詳細のリクエストのテストに足す: run が 0 件・1 件（`pending_deployments` を送らない）・2 件で承認できるのが 1 件・2 件とも承認できる・`total_count` が 6、`pending_deployments` の `404` と `502` とレート制限の `403`、一覧の `404` と `403`（レート制限でない）と `401`、形の崩れたボディ、`id` が 21 桁。リクエストの URL（`status=waiting&per_page=20`、`pending_deployments` のパス）と、別のオリジンへのリダイレクトを拒むことも確かめる。
- [x] 2.3 `GitHubAPIClient` に `fetchCheckSuiteRun` と、run を選ぶ `static` の関数を置く（D4）。選ぶ関数のテスト: 名前が一致する最も近い run、10 分を超える run は選ばない、同じ差が 2 件なら決めない、`name` が無い run。リクエストのテスト: `branch=feat/a%2Bb&per_page=30` の URL、`&` と `=` を含むブランチのエスケープ、`html_url` が別のホストでも覚えないこと（デコードした結果に URL が無いこと）、一覧の `404`。
- [x] 2.4 ポーラーのテスト（`ThreadDetailsPollingTests` に近い形）: 新着の `WorkflowRun` のスレッドの run を、一覧を知らせる前に取って付けること。同じ `updated_at` の間は取り直さないこと。`xcodebuild ... test -only-testing:` で該当のスイートを通し、スイート数を確かめる。

## 3. 開く URL

- [x] 3.1 `ThreadWebURL.Target` に `.workflowRun` と `.actions(query:)` を足し、`url(...)` でクエリを付ける。`target` を D5 のとおりにする。
- [x] 3.2 `ThreadWebURL` のテストに、ui の delta spec の 5 つのシナリオ（run を覚えた `WorkflowRun` と `CheckSuite`、覚えていない `WorkflowRun`、絞り込みの一覧、件名を読めない `CheckSuite`）の URL を、spec に書いた文字列と一致させて足す。GHES（`https://ghe.example.com/team/svc/actions/runs/1`）、ワークフロー名に `"` を含む件名（`workflow:` を付けない）、`#` や `&` を含むブランチ（URL の意味が変わらない）も確かめる。macOS の通知の URL（`ThreadNotificationContent`）が run のページになることも 1 つ確かめる。

## 4. 確認

- [x] 4.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [x] 4.2 `bash scripts/run.sh` で起動し、手元のアカウントで今までの種類の通知が今までどおり開くこと、ログにエラーが無いことを確かめる。（起動後のログでエラーが無いことを確かめた。今までの種類の開く URL は、既存の `ThreadWebURLTests` が変わらず通ることで確かめた）
- [ ] 4.3 ユーザーが実物で確かめる（手元に Actions の通知が無いので、起こしてもらう）: environment の承認を 1 回起こし、その通知（一覧と macOS の通知）から承認する run のページが開くこと。ワークフローを 1 回失敗させ、その通知から失敗した run のページが開くこと。ポップオーバーのアイコンが今までと同じで、VoiceOver で「Workflow run」と読まれること。

## 5. レビュー

- [ ] 5.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 5.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 5.3 ロジックの変更を含む修正が多ければ、5.2 を新しいサブエージェントでもう一度実行する。
