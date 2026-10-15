# Proposal

## Why

GitHub Actions の通知は、種類が 2 つある。どちらも件名に run の ID を含まず、Mewbell はどちらも種類として扱っていないので、クリックするとリポジトリのトップが開く。ユーザーは目的の run を探し直すことになる。Discussion と Release は個別のページを開くようにしたので、Actions の通知も目的の run のページを開きたい。

- `WorkflowRun`: environment にデプロイの承認者を決めておくと、承認を待つワークフローの実行（run）について承認者に届く。件名は `<user> requested your review to deploy to an environment` だけで、ワークフロー名も run の ID も含まない（Gitify の実装とテストで確かめた）。
- `CheckSuite`: ワークフローの実行が終わったとき（失敗など）に届く。件名は `<ワークフロー名> workflow run failed for <ブランチ> branch` の形で、`, Attempt #<回数>` が付くこともある。結果の部分は `failed` のほかに `failed at startup`、`cancelled`、`skipped`、`succeeded` がある（Gitify の実装で確かめた）。

## What Changes

- 通知の種類 `WorkflowRun` を、ほかの種類（`other`）から分けて扱う。`CheckSuite` は今も種類として持っているが、開く URL では扱っていないので、扱うようにする。
- Release のタグと同じく「スレッドのイベントの取得」の仕組みで、スレッドの run を API で探し、その ID を覚える。
  - `WorkflowRun`: `GET /repos/{owner}/{name}/actions/runs?status=waiting` で承認を待っている run を取る。1〜5 件なら、それぞれの `GET /repos/{owner}/{name}/actions/runs/{run_id}/pending_deployments` を取り、ユーザーが承認できる（`current_user_can_approve`）run が 1 件だけならその run にする。それ以外は「決まらない」にする。
  - `CheckSuite`: 件名からワークフロー名・結果・ブランチ・試行の回数を読み、`GET /repos/{owner}/{name}/actions/runs?branch=<ブランチ>` で取った run から、ワークフロー名と結果（と試行の回数）が合い、更新日時がスレッドの `updated_at` に最も近い（前後 10 分以内）ものにする。当たらなければ「決まらない」にする。
- 開く URL:
  - run が決まっていれば、どちらも `<Web ベース>/<owner>/<name>/actions/runs/<run の ID>`。
  - 決まっていなければ、`WorkflowRun` は承認待ちの一覧 `<Web ベース>/<owner>/<name>/actions?query=is:waiting`。`CheckSuite` は件名から作った絞り込みの一覧（Gitify と同じ。例: `actions?query=workflow:"CI" is:failure branch:main`）で、件名を読めなければ `<Web ベース>/<owner>/<name>/actions`。
  - macOS の通知のクリックも同じ URL を開く。
- 一覧の行のアイコンは今と同じもの（種類によらない記号）のままにし、VoiceOver で読ませる `WorkflowRun` の種類の名前を「Workflow run」にする（`CheckSuite` は今の「Check suite」のまま）。

前提: `WorkflowRun` と `CheckSuite` の通知の run を探すのに `subject.url` は使わない（Gitify も使っていない。手元に実物が無く、null かどうかを確かめられなかった）。種類・件名・検証済みのリポジトリだけで決める。`subject.url` が Pull request・Issue・Commit を指すときだけは、今までどおりそのページを開く（番号は種類ではなく `subject.url` で決める今の決まりを保つ）。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

- `github-api`: スレッドの run を探すリクエスト（「ワークフローの実行の検索のリクエスト」）を足す。
- `polling`: 「スレッドのイベントの取得」の対象に、種類が `WorkflowRun` と `CheckSuite` のスレッドを足し、イベントの代わりに run の ID を取る。
- `ui`: 「通知のスレッドを開く」に、種類が `WorkflowRun` と `CheckSuite` のスレッドの URL を足す。

notifications の「通知のクリック」は ui の URL の決まりで開くので、文は変えない。

## Impact

- マイルストーン: M4（設定と操作）以降の保守の change。update-thread-open-url（Discussion と Release の個別のページ）の続き。
- 変更するもの: `Mewbell/GitHubAPI/NotificationThread.swift`（`SubjectKind` と `DetailsSubject`）、件名を読む処理、`Mewbell/GitHubAPI/ThreadEvent.swift`（`ThreadDetails` の Release のタグと run の ID を 1 つの enum にまとめる）、`Mewbell/GitHubAPI/GitHubAPIClient.swift`（run を探すリクエスト）、`Mewbell/GitHubAPI/ThreadWebURL.swift`（開く URL）、`Mewbell/UI/ThreadIcon.swift`（種類の名前）、そのテスト。
- API の呼び出し: `updated_at` が変わるまでに、`WorkflowRun` のスレッド 1 件で最大 6 回（一覧 1 回と承認できるかの確認 5 回）、`CheckSuite` のスレッド 1 件で 1 回。ほかの種類の呼び出しは変えない。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: ネットワーク（新しい API のリクエスト）と URL を開く処理に触れるので、`.claude/rules/security.md` が適用される。リクエストの URL は検証済みのリポジトリ名・検証済みの run の ID・クエリの値としてエスケープした件名の値から組み立て、送る前のオリジン検査を通す。レスポンスからは run の ID・ワークフロー名・結果・試行の回数・更新日時と、承認できるかだけを読み、`html_url` などの URL は使わない。トークンは今までどおりメモリにだけ持ち、永続化しない。gh サブプロセスには触れない。
- 手元に Actions の通知が無いので、実物の確認はユーザーが行う（environment の承認を 1 回起こす、ワークフローを 1 回失敗させる）。
