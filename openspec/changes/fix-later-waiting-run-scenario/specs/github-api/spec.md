## MODIFIED Requirements

### Requirement: ワークフローの実行の検索の承認できる run

種類が `WorkflowRun` のスレッド（デプロイの承認リクエスト）は、次のように run を決めなければならない（MUST）。

- 承認を待っている run が 1〜5 件なら（「ワークフローの実行の検索の通知より前に作られた run」に当たらないとき）、それぞれの `GET <API ベース URL>/repos/{owner}/{name}/actions/runs/{run の ID}/pending_deployments` を取り、`current_user_can_approve` が true の待ちを 1 つでも持つ run のうち、`updated_at`（承認を待ち始めた時刻）とスレッドの `updated_at` の差が 10 分以内で、差が最も小さいものにする。当たる run が無いとき、差が最も小さいものが 2 件以上あるときは、run は「無い」

#### Scenario: 承認を待っている run が複数

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドのリポジトリが `octo/app` で、承認を待っている run が `101` と `102` の 2 件
- **WHEN** `GET /repos/octo/app/actions/runs/101/pending_deployments` が `current_user_can_approve: false` の待ちを、`.../102/pending_deployments` が `current_user_can_approve: true` の待ちを返す
- **THEN** そのスレッドの run は `102` になる

#### Scenario: 承認できる run が複数ある

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run が `101`（`updated_at` 11:50:30）と `102`（12:01）の 2 件あり、どちらにも `current_user_can_approve: true` の待ちがある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は `102` になる

#### Scenario: 後から待ち始めた run は選ばない

- **GIVEN** スレッドの `updated_at` が 12:00 で、承認を待っている run が `102`（`updated_at` 11:59）と `103`（12:20）の 2 件
- **WHEN** `102` の `pending_deployments` が `current_user_can_approve: false` の待ちだけを、`103` の `pending_deployments` が `current_user_can_approve: true` の待ちを返す
- **THEN** 通知より前に作られた run の一覧のリクエストは送られず、そのスレッドの run は「無い」になる

#### Scenario: 承認できる run が決まらない

- **GIVEN** 承認を待っている run が 2 件あり、`updated_at` がスレッドの `updated_at` の 2 分前と 2 分後で、どちらにも `current_user_can_approve: true` の待ちがある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は「無い」になる
