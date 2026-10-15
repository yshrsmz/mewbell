## ADDED Requirements

### Requirement: ワークフローの実行の検索のリクエスト

Mewbell は、種類が `WorkflowRun` か `CheckSuite` のスレッド（polling「スレッドのイベントの取得」の条件を満たすもの）についてだけ、そのスレッドのワークフローの実行（run）を探すために、次のリクエストを送らなければならない（SHALL）。リクエストの URL は、`subject.url` を使わず、検証済みのリポジトリの `owner/name`、検証済みの run の ID（1〜20 桁の数字）、件名から読んだ値から組み立てなければならない（MUST）。件名から読んだ値はクエリの値としてエスケープし、`+` も `%2B` にエスケープしなければならない（MUST。`&` や `=` でクエリの意味が変わらないように、`+` が空白として読まれないように）。組み立てた URL にも「トークンを送る相手の制限」の確認をしなければならず（MUST）、「トークンをリクエストごとに付ける」「リダイレクトとキャッシュ」「通信の内容をログに出さない」を同じく適用しなければならない（MUST）。

種類が `WorkflowRun` のスレッド（デプロイの承認リクエスト）は、次のように run を決めなければならない（MUST）。1 つのスレッドについて送るリクエストは最大 6 回にしなければならない（MUST）。

1. `GET <API ベース URL>/repos/{owner}/{name}/actions/runs?status=waiting&per_page=20` で、承認を待っている run を取る
2. 1 件も無ければ、run は「無い」
3. 1 件なら、その run にする
4. 2〜5 件なら、それぞれの `GET <API ベース URL>/repos/{owner}/{name}/actions/runs/{run の ID}/pending_deployments` を取り、`current_user_can_approve` が true の待ちを 1 つでも持つ run が 1 件だけなら、その run にする。そうでなければ run は「無い」
5. 6 件以上（`total_count` が 6 以上のときを含む）なら、run は「無い」

種類が `CheckSuite` のスレッド（ワークフローの実行の結果）は、件名を `<ワークフロー名> workflow run[, Attempt #<数字>] <結果> for <ブランチ> branch` の形として読まなければならない（MUST）。`<結果>` は `failed`、`failed at startup`、`cancelled`、`skipped`、`succeeded` のいずれかでなければならず、ワークフロー名とブランチは空でなく、UTF-8 で 255 バイト以下で、制御文字を含まないものでなければならない（MUST）。読めなければ、リクエストを送らずに run は「無い」としなければならない（MUST）。読めたら、`GET <API ベース URL>/repos/{owner}/{name}/actions/runs?branch=<ブランチ>&per_page=30` を 1 回だけ送り、`name` がワークフロー名と一致し、`updated_at` とスレッドの `updated_at` の差が 10 分以内の run のうち、差が最も小さいものにしなければならない（MUST）。当たる run が無いとき、差が最も小さいものが 2 件以上あるときは、run は「無い」としなければならない（MUST）。

レスポンスのうち、使ってよいのは run の `id`・`name`・`updated_at`・`total_count` と、待ちの `current_user_can_approve` だけで、`html_url` などの URL を保持・表示・ログ出力してはならない（MUST NOT）。`id` は 1〜20 桁の数字として読めるものだけを受け付けなければならない（MUST）。

レスポンスは、スレッドのイベントの取得のリクエスト（「スレッドのイベントの取得のリクエスト」）と同じく次のように扱わなければならない（MUST）。`pending_deployments` のリクエストも同じに扱い、どれか 1 つでも一時的な失敗・認証の失敗・レート制限になったら、そのスレッドの結果をそれにしなければならない（MUST）。

- `200`: ボディを読む。JSON のオブジェクト（`pending_deployments` は配列）でない、`workflow_runs` が配列でないなど形が崩れていれば一時的な失敗として扱う
- `404` / `410`: run の一覧のリクエストなら run は「無い」として扱う。`pending_deployments` のリクエストなら、その run は承認できないものとして扱う
- `401`: 認証の失敗として扱う
- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、制限が解ける時刻を返す（「ステータスコードの扱い」と同じ判定）。待ち時間のヘッダーが無くても、本文の `message` が二次レート制限（`secondary rate limit`）を示すときはレート制限として扱う。それ以外の `403` と `422` は `404` と同じに扱う（トークンに Actions を読む権限が無いときなど）
- `429`: レート制限として扱う
- それ以外の状態コード、リダイレクト、通信の失敗、タイムアウト、レスポンスが大きすぎる: 一時的な失敗として扱う

#### Scenario: 承認を待っている run が 1 件

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドのリポジトリが `octo/app`
- **WHEN** Mewbell がそのスレッドの run を探し、API が `200` と、`id: 38692691414` の run 1 件を返す
- **THEN** リクエストは `https://api.github.com/repos/octo/app/actions/runs?status=waiting&per_page=20` に `alice` のトークンを付けて送られる
- **AND** `pending_deployments` のリクエストは送られず、そのスレッドの run は `38692691414` になる

#### Scenario: 承認を待っている run が複数

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドのリポジトリが `octo/app` で、承認を待っている run が `101` と `102` の 2 件
- **WHEN** `GET /repos/octo/app/actions/runs/101/pending_deployments` が `current_user_can_approve: false` の待ちを、`.../102/pending_deployments` が `current_user_can_approve: true` の待ちを返す
- **THEN** そのスレッドの run は `102` になる

#### Scenario: 承認できる run が決まらない

- **GIVEN** 承認を待っている run が 2 件あり、どちらにも `current_user_can_approve: true` の待ちがある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は「無い」になる

#### Scenario: 承認を待っている run が多い

- **GIVEN** `GET /repos/octo/app/actions/runs?status=waiting&per_page=20` が `total_count: 8` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** `pending_deployments` のリクエストは送られず、そのスレッドの run は「無い」になる

#### Scenario: 失敗したワークフローの run を探す

- **GIVEN** `github.com/alice` の種類が `CheckSuite` のスレッドのリポジトリが `octo/app`、件名が `CI workflow run failed for main branch`、`updated_at` が 12:05
- **WHEN** `GET https://api.github.com/repos/octo/app/actions/runs?branch=main&per_page=30` が、`name: CI` で `updated_at` 12:04 の run `201`、`name: CI` で `updated_at` 11:30 の run `200`、`name: Release` で `updated_at` 12:05 の run `202` を返す
- **THEN** そのスレッドの run は `201` になる

#### Scenario: 試行の回数が付いた件名

- **GIVEN** 種類が `CheckSuite` のスレッドの件名が `Build and test workflow run, Attempt #2 failed for feat/a+b branch`
- **WHEN** Mewbell がそのスレッドの run を探す
- **THEN** リクエストは `https://api.github.com/repos/octo/app/actions/runs?branch=feat/a%2Bb&per_page=30` に送られ、`name` が `Build and test` の run から選ぶ

#### Scenario: 読めない件名

- **GIVEN** 種類が `CheckSuite` のスレッドの件名が `Something happened`
- **WHEN** Mewbell がそのスレッドの run を探す
- **THEN** リクエストは送られず、そのスレッドの run は「無い」になる

#### Scenario: Actions を読めないトークン

- **GIVEN** run の一覧のリクエストに API が `404` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は「無い」になる

#### Scenario: html_url は使わない

- **GIVEN** run の一覧の `200` のレスポンスの run に `html_url: https://evil.example.com/octo/app/actions/runs/1` がある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** `evil.example.com` の URL は覚えない
