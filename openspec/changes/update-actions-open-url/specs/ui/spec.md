## MODIFIED Requirements

### Requirement: 通知のスレッドを開く

ポップオーバーの一覧でスレッドをクリックすると、Mewbell はそのスレッドの Web ページを既定のブラウザで開き、続けてそのスレッドを既読にしなければならない（SHALL。polling「スレッドの既読化」）。開く URL は、API のレスポンスに含まれる URL や文字列をそのまま使わず、アカウントの Web ベース URL、リポジトリの `owner/name`、`subject.url` のパス、覚えたリリースのタグと run の ID（polling「スレッドのイベントの取得」）、件名から次のように組み立てなければならない（MUST）。

- `subject.url` が API ベース URL と同じオリジンで、パスが API ベース URL のパスに続く `repos/<owner>/<name>/pulls/<番号>` のとき: `<Web ベース>/<owner>/<name>/pull/<番号>`
- 同じく `.../issues/<番号>` のとき: `<Web ベース>/<owner>/<name>/issues/<番号>`
- 同じく `.../commits/<16 進の SHA>` のとき: `<Web ベース>/<owner>/<name>/commit/<SHA>`
- 種類が Discussion で、`subject.url` が同じく `.../discussions/<番号>` のとき: `<Web ベース>/<owner>/<name>/discussions/<番号>`
- 種類が Discussion で、上に当たらないとき: `<Web ベース>/<owner>/<name>/discussions`
- 種類が Release で、そのスレッドのリリースのタグを覚えているとき: `<Web ベース>/<owner>/<name>/releases/tag/<タグ>`
- 種類が Release で、タグを覚えていないとき（取る前、取れなかった、タグが検証を通らなかったなど）: `<Web ベース>/<owner>/<name>/releases`
- 種類が `WorkflowRun` か `CheckSuite` で（`subject.url` が上の Pull request・Issue・Commit に当たらないとき。以下の 2 つも同じ）、そのスレッドの run の ID を覚えているとき: `<Web ベース>/<owner>/<name>/actions/runs/<run の ID>`
- 種類が `WorkflowRun` で、run の ID を覚えていないとき（取る前、取れなかった、決まらなかったなど）: `<Web ベース>/<owner>/<name>/actions?query=is:waiting`
- 種類が `CheckSuite` で、run の ID を覚えていないとき: `<Web ベース>/<owner>/<name>/actions` に、件名（github-api「ワークフローの実行の検索のリクエスト」の形）から作った絞り込みを `query` に付けたもの。絞り込みは、ワークフロー名が `"` を含まなければ `workflow:"<ワークフロー名>"`、結果が `failed` か `failed at startup` なら `is:failure`、`cancelled` なら `is:cancelled`、`skipped` なら `is:skipped`、`succeeded` なら `is:success`、`branch:<ブランチ>` を、この順に空白でつなげたもの。件名が読めなければ `query` を付けない
- それ以外（`subject.url` が無い、形が合わない、`subject.url` の `<owner>/<name>` がスレッドのリポジトリと一致しない、などを含む）: `<Web ベース>/<owner>/<name>`

番号と run の ID は 1〜20 桁の数字だけを受け付けなければならない（MUST）。`query` の値は URL のクエリの値としてエスケープし、`+` も `%2B` にエスケープしなければならない（MUST）。タグは `/` で区切った要素ごとに、URL のパスの要素としてエスケープして足さなければならない（MUST）（`?` や `#` で URL の意味が変わらないように）。

開く前に、組み立てた URL のスキームが `https` で、ホストがアカウントのホストと一致することを確かめ、一致しなければ開いてはならない（MUST NOT）。開かなかったときは、既読にもしてはならない（MUST NOT）。

#### Scenario: Pull request を開く

- **GIVEN** `github.com/alice` のスレッドのリポジトリが `octo/app`、`subject.url` が `https://api.github.com/repos/octo/app/pulls/42`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/pull/42` が開く
- **AND** スレッドは一覧から消え、既読化のリクエストが送られる

#### Scenario: GHES の Issue を開く

- **GIVEN** `ghe.example.com/dave` のスレッドのリポジトリが `team/svc`、`subject.url` が `https://ghe.example.com/api/v3/repos/team/svc/issues/7`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://ghe.example.com/team/svc/issues/7` が開く

#### Scenario: Discussion を開く

- **GIVEN** `github.com/alice` の種類が Discussion のスレッドのリポジトリが `octo/app`、`subject.url` が `https://api.github.com/repos/octo/app/discussions/2045`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/discussions/2045` が開く

#### Scenario: Discussion の subject.url が無い

- **GIVEN** `github.com/alice` の種類が Discussion のスレッドのリポジトリが `octo/app` で、`subject.url` が無い
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/discussions` が開く

#### Scenario: タグを覚えた Release を開く

- **GIVEN** `github.com/alice` の種類が Release のスレッドのリポジトリが `openai/codex`、`subject.url` が `https://api.github.com/repos/openai/codex/releases/413167889` で、そのリリースのタグ `rust-v0.163.0-alpha.10.1` を覚えている
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/openai/codex/releases/tag/rust-v0.163.0-alpha.10.1` が開く

#### Scenario: タグに / を含む Release を開く

- **GIVEN** `github.com/alice` の種類が Release のスレッドのリポジトリが `octo/app` で、そのリリースのタグ `cli/v1.2.0` を覚えている
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/releases/tag/cli/v1.2.0` が開く

#### Scenario: タグをまだ覚えていない Release を開く

- **GIVEN** `github.com/alice` の種類が Release のスレッドのリポジトリが `octo/app` で、そのリリースのタグをまだ取っていない
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** タグを取るのを待たずに、既定のブラウザで `https://github.com/octo/app/releases` が開く

#### Scenario: subject.url が別のホストを指している

- **GIVEN** `github.com/alice` のスレッドのリポジトリが `octo/app`、`subject.url` が `https://evil.example.com/repos/octo/app/pulls/42`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app` が開く
- **AND** `evil.example.com` の URL は開かない

#### Scenario: Discussion の subject.url が別のリポジトリを指している

- **GIVEN** `github.com/alice` の種類が Discussion のスレッドのリポジトリが `octo/app`、`subject.url` が `https://api.github.com/repos/other/repo/discussions/9`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/discussions` が開く

#### Scenario: subject.url が無い

- **GIVEN** スレッドの種類が Issue で、`subject.url` が無い
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** リポジトリのページが開く

#### Scenario: 承認リクエストの run を開く

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドのリポジトリが `octo/app` で、その run の ID `38692691414` を覚えている
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/actions/runs/38692691414` が開く

#### Scenario: run が決まらない承認リクエストを開く

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドのリポジトリが `octo/app` で、その run の ID を覚えていない
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** run を探すのを待たずに、既定のブラウザで `https://github.com/octo/app/actions?query=is:waiting` が開く

#### Scenario: 失敗したワークフローの run を開く

- **GIVEN** `github.com/alice` の種類が `CheckSuite` のスレッドのリポジトリが `octo/app` で、その run の ID `201` を覚えている
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/actions/runs/201` が開く

#### Scenario: run が決まらない失敗の通知を開く

- **GIVEN** `github.com/alice` の種類が `CheckSuite` のスレッドのリポジトリが `octo/app`、件名が `Build and test workflow run, Attempt #2 failed for feat/a+b branch` で、その run の ID を覚えていない
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/actions?query=workflow:%22Build%20and%20test%22%20is:failure%20branch:feat/a%2Bb` が開く

#### Scenario: 件名を読めない CheckSuite を開く

- **GIVEN** `github.com/alice` の種類が `CheckSuite` のスレッドのリポジトリが `octo/app`、件名が `Something happened` で、その run の ID を覚えていない
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/actions` が開く
