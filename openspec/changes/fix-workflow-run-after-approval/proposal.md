# Proposal

## Why

種類が `WorkflowRun`（デプロイの承認リクエスト）のスレッドの run は、今は承認を待っている run（`actions/runs?status=waiting`）の中からだけ探す。このため、Mewbell が初めてそのスレッドを見たときに run がもう承認されていると、run は「無い」になり、承認待ちの一覧（`/actions?query=is:waiting`）を開く。一覧は空になる。Mewbell が起動していなかった間に届いた通知や、一覧に出る前に Web で承認された通知は、いつもこうなる。

実物（GHE Cloud のリポジトリ）で確かめた。

- 通知の `subject.url` は null。
- 通知の `updated_at`（07:16:58Z、06:34:23Z）は、承認を待った run（`cloudformation-apply`）の `run_started_at`（07:16:53Z、06:34:18Z）の 5 秒後。その run の `updated_at` は、承認の後に終わった時刻（07:22:14Z、07:14:59Z）。
- 直前の別の run（`cloudformation-plan`、07:15:49Z〜07:16:27Z と 06:33:21Z〜06:34:00Z）は、通知の前に終わっている。

通知の時刻を、run が始まってから終わるまでの間に挟む run は、どちらの通知でも承認を待った run の 1 件だけになる。

## What Changes

- 種類が `WorkflowRun` のスレッドで、承認を待っている run から run が決まらない（「無い」になる）ときは、`GET /repos/{owner}/{name}/actions/runs?created=<=<スレッドの updated_at>&per_page=30` で、通知より前に作られた run を取る。
- そのうち、承認を待っていない（`status` が `waiting` でない）run で、`run_started_at` がスレッドの `updated_at` 以前で、終わった時刻（`status` が `completed` なら `updated_at`、終わっていなければ今）がスレッドの `updated_at` 以降の run（通知の時刻を挟む run）が 1 件だけなら、その run にする。0 件か 2 件以上なら、今までどおり「無い」（承認待ちの一覧を開く）。
- 承認を待っている run から決まったときと、一時的な失敗・認証の失敗・レート制限のときは、このリクエストを送らない。
- 1 つのスレッドについて送るリクエストは、最大 6 回から最大 7 回になる。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

- `github-api`: 「ワークフローの実行の検索のリクエスト」の、種類が `WorkflowRun` のスレッドの run の決め方に、承認待ちの run から決まらないときの探し方を足す。

ui「通知のスレッドを開く」は、run の ID を覚えていれば run のページ、無ければ承認待ちの一覧を開く決まりのままで、文は変えない。

## Impact

- マイルストーン: M4（設定と操作）以降の保守の change。update-actions-open-url の続き。
- 変更するもの: `Mewbell/GitHubAPI/GitHubAPIClient.swift`（承認を待っている run から決まらないときのリクエスト）、`Mewbell/GitHubAPI/WorkflowRunSummary.swift`（`run_started_at` と `status` を読む、通知の時刻を挟む run を選ぶ関数）、そのテスト。
- API の呼び出し: 種類が `WorkflowRun` のスレッドで run が承認を待っていないとき、`updated_at` が変わるまでに 1 回増える。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: ネットワーク（新しい API のリクエスト）に触れるので、`.claude/rules/security.md` が適用される。リクエストの URL は検証済みのリポジトリ名と、スレッドの `updated_at`（API が返した日時を読み直して書いた値）から組み立て、送る前のオリジン検査を通す。レスポンスからは run の ID・`run_started_at`・`status`・`updated_at` だけを読み、`html_url` などの URL は使わない。開く URL の組み立ては変えない。トークンは今までどおりメモリにだけ持ち、永続化しない。gh サブプロセスには触れない。
