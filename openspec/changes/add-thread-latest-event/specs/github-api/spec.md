## ADDED Requirements

### Requirement: スレッドのイベントの取得のリクエスト

Mewbell は、番号を持つスレッド（ui「アカウント一覧の表示」の条件を満たして `#<番号>` を出すスレッド。Issue と Pull request）についてだけ、イベントを求めるために次のリクエストを送らなければならない（SHALL）。番号を持たないスレッド（Commit・Release・Discussion・CheckSuite、`subject.url` が検証を通らないものなど）には、これらのリクエストを送ってはならない（MUST NOT）。

- `GET <API ベース URL>/repos/{owner}/{name}/issues/{番号}`（件名の作成日時・作成者・状態を得る）
- `GET <API ベース URL>/repos/{owner}/{name}/issues/{番号}/timeline?per_page=100`（1 ページ目）

リクエストの URL は、`subject.url` をそのまま使わず、検証済みのリポジトリの `owner/name` と番号から組み立てなければならない（MUST）。Timeline の 1 ページ目の `Link` ヘッダーに `rel="last"` があり、それが 2 ページ目以降を指すときは、その最後のページを取得しなければならない（MUST）。最後のページにイベントの候補（「スレッドのイベントの決定」）が無く、その前のページが 2 ページ目以降のときは、その前のページも取得しなければならない（MUST）。1 つのスレッドについて Timeline を 3 ページより多く取得してはならない（MUST NOT）。`Link` ヘッダーの URL にも、「トークンを送る相手の制限」の確認をしなければならない（MUST）。これらのリクエストにも、「トークンをリクエストごとに付ける」「リダイレクトとキャッシュ」「通信の内容をログに出さない」を同じく適用しなければならない（MUST）。Timeline のレスポンスにはコメントの本文が含まれるので、本文を保持・表示・ログ出力してはならない（MUST NOT）。

レスポンスは次のように扱わなければならない（MUST）。

- `200`: ボディを読む。形が崩れていれば一時的な失敗として扱う
- `404` / `410`: そのスレッドのイベントは「無い」として扱う（削除された、見られなくなったなど）
- `401`: 認証の失敗として扱う
- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、制限が解ける時刻を返す（「ステータスコードの扱い」と同じ判定）。それ以外の `403` と `422` はイベントが「無い」として扱う
- `429`: レート制限として扱う
- それ以外の状態コード、リダイレクト、通信の失敗、タイムアウト、レスポンスが大きすぎる: 一時的な失敗として扱う

1 つのスレッドについて送るリクエストのどれかが「無い」以外の失敗になったら、そのスレッドの結果はその失敗にしなければならない（MUST）。

#### Scenario: Issue のイベントを取る

- **GIVEN** `github.com/alice` のスレッドのリポジトリが `octo/app`、`subject.url` が `https://api.github.com/repos/octo/app/issues/7`
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** `https://api.github.com/repos/octo/app/issues/7` と `https://api.github.com/repos/octo/app/issues/7/timeline?per_page=100` に `alice` のトークンを付けたリクエストが送られる

#### Scenario: Pull request も issues のパスで取る

- **GIVEN** `ghe.example.com/dave` のスレッドの `subject.url` が `https://ghe.example.com/api/v3/repos/team/svc/pulls/42`
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** リクエストは `https://ghe.example.com/api/v3/repos/team/svc/issues/42` と `.../issues/42/timeline?per_page=100` に送られる

#### Scenario: 番号を持たないスレッド

- **GIVEN** `github.com/alice` に、種類が Release のスレッドと、`subject.url` が `https://evil.example.com/repos/octo/app/issues/7` のスレッドがある
- **WHEN** Mewbell がイベントを取るスレッドを選ぶ
- **THEN** どちらのスレッドにもイベントのリクエストは送られない

#### Scenario: 最後のページを取る

- **GIVEN** Timeline の 1 ページ目の `Link` に `rel="last"` で `https://api.github.com/repositories/1/issues/7/timeline?per_page=100&page=5` がある
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** 5 ページ目を取得し、2〜4 ページ目は、5 ページ目に候補が無いときの 4 ページ目を除いて取得しない

#### Scenario: 最後のページが別のホストを指している

- **GIVEN** Timeline の 1 ページ目の `rel="last"` が `https://evil.example.com/timeline?page=5` を指している
- **WHEN** Mewbell が最後のページを取ろうとする
- **THEN** `evil.example.com` へのリクエストは送られず、そのスレッドの結果は一時的な失敗になる

#### Scenario: 削除された Issue

- **GIVEN** `GET /repos/octo/app/issues/7` が `404` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのイベントは「無い」になる

#### Scenario: レート制限

- **GIVEN** Timeline の取得に API が `403` と `X-RateLimit-Remaining: 0`、`X-RateLimit-Reset: <10 分後の時刻>` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの結果は「レート制限」になり、10 分後の時刻が得られる

### Requirement: スレッドの状態の決定

Mewbell は、イベントを取るときに得た Issue のレスポンスから、スレッドの件名の今の状態を次の規則で決めなければならない（MUST）。Issue のレスポンスを得られなかったスレッドの状態は「分からない」にしなければならない（MUST）。

- Pull request（`pull_request` がある）: `pull_request.merged_at` があれば Merged、`state` が `closed` なら Closed、`draft` が `true` なら Draft、それ以外の `open` なら Open
- Issue: `state` が `open` なら Open、`closed` で `state_reason` が `not_planned` なら Closed as not planned、それ以外の `closed` なら Closed as completed
- 上のどれにも当たらない値（知らない `state` など）は「分からない」

#### Scenario: マージした Pull request

- **GIVEN** `GET /repos/cli/cli/issues/14634` が `state: closed`、`pull_request.merged_at: 2026-10-09T14:47:45Z` を返す
- **WHEN** Mewbell が状態を決める
- **THEN** 状態は Merged になる

#### Scenario: 対応しないで閉じた Issue

- **GIVEN** Issue のレスポンスが `state: closed`、`state_reason: not_planned` で、`pull_request` が無い
- **WHEN** Mewbell が状態を決める
- **THEN** 状態は Closed as not planned になる

#### Scenario: 下書きの Pull request

- **GIVEN** Issue のレスポンスが `state: open`、`draft: true` で、`pull_request.merged_at` が `null`
- **WHEN** Mewbell が状態を決める
- **THEN** 状態は Draft になる

### Requirement: スレッドのイベントの決定

Mewbell は、Issue と Timeline のレスポンスから、スレッドの `updated_at` を更新したイベントを次の規則で 1 つ決めなければならない（MUST）。スレッドの `updated_at` は、きっかけになったイベントの時刻より数十秒遅れることがあるので、その分の幅を取る。

Timeline の項目のうち、次の `event` だけを候補にしなければならない（MUST）。ほかの `event`（`labeled`、`cross-referenced`、`referenced`、`mentioned`、`subscribed`、知らない値など）は候補にしてはならない（MUST NOT）。

| `event` | イベント | 時刻 | 実行者 |
|---|---|---|---|
| `commented` | Commented | `created_at` | `actor.login` |
| `reviewed`（`state: approved`） | Approved | `submitted_at` | `user.login` |
| `reviewed`（`state: changes_requested`） | Requested changes | `submitted_at` | `user.login` |
| `reviewed`（`state: commented`） | Reviewed | `submitted_at` | `user.login` |
| `closed` | Closed | `created_at` | `actor.login` |
| `reopened` | Reopened | `created_at` | `actor.login` |
| `merged` | Merged | `created_at` | `actor.login` |
| `ready_for_review` | Marked ready for review | `created_at` | `actor.login` |
| `convert_to_draft` | Converted to draft | `created_at` | `actor.login` |
| `review_requested` | Requested review | `created_at` | `actor.login` |
| `assigned` | Assigned | `created_at` | `actor.login` |
| `committed` | Pushed commits | `committer.date` | なし |
| `head_ref_force_pushed` | Force-pushed | `created_at` | `actor.login` |

- 候補は、時刻が「件名の作成日時 + 60 秒」より後で（作成と同時に起きる `review_requested` や、作成前のコミットを除くため）、かつ「スレッドの `updated_at` − 180 秒」から「スレッドの `updated_at` + 60 秒」までの幅（以下「近さの幅」）に入るものに限らなければならない（MUST）。時刻を読めない項目は候補にしてはならない（MUST NOT）。近さの幅に入らない候補を、近いものが無いからといって代わりに使ってはならない（MUST NOT）（作成から時間がたってから push したコミットのように、時刻が `updated_at` を表さない項目で、古い別のイベントを拾わないため）
- 候補があれば、時刻がスレッドの `updated_at` にいちばん近い候補をイベントにしなければならない（MUST）。近さが同じ候補が複数あれば、取得したページを古い順につなげたときに後ろにあるものにしなければならない（MUST）。それが `closed` で、その時刻の 60 秒前からその時刻までに `merged` があるときは、`merged` の実行者で Merged にしなければならない（MUST）
- 候補が無く、件名の作成日時が近さの幅に入るときは、件名の作成者（Issue の `user.login`）で Opened にしなければならない（MUST）
- それ以外のときは、イベントは「無い」にしなければならない（MUST）

実行者のログイン名は、GitHub のログイン名として妥当な値（gh-cli のユーザー名の検証と同じ規則）か、それに `[bot]` を付けた値のときだけ使わなければならない（MUST）。ログイン名が無い（`null`、削除されたユーザーなど）か妥当でないときは、イベントは実行者なしにしなければならない（MUST）。

#### Scenario: コメント

- **GIVEN** Issue `octo/app#7` の作成日時が 10:00、スレッドの `updated_at` が 12:00:30 で、Timeline の作成より後の候補が 11:30 の `labeled`（候補にしない）と 12:00 の `commented`（`actor.login: bob`）
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Commented、実行者は `bob` になる

#### Scenario: マージ

- **GIVEN** Pull request の Timeline の最後が、14:47:45 の `merged`（`williammartin`）、14:47:45 の `closed`（`williammartin`）、14:47:47 の `head_ref_deleted` で、スレッドの `updated_at` が 14:47:45
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Merged、実行者は `williammartin` になる

#### Scenario: updated_at の後の出来事は使わない

- **GIVEN** スレッドの `updated_at` が 12:00 で、Timeline に 11:59 の `closed`（`alice`）と 15:00 の `commented`（`bob`）がある
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Closed、実行者は `alice` になる

#### Scenario: 開かれた Pull request

- **GIVEN** Pull request の作成日時が 19:39:42、作成者が `BagToad`、スレッドの `updated_at` が 19:39:42 で、Timeline には作成前のコミットの `committed` と 19:39:43 の `review_requested` しか無い
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Opened、実行者は `BagToad` になる

#### Scenario: いちばん近い候補を選ぶ

- **GIVEN** Pull request の作成日時が 16:12:06、スレッドの `updated_at` が 16:18:08 で、Timeline に 16:17:15 の `commented`（`github-actions[bot]`）、16:17:32 の `merged` と `closed`（`yshrsmz`）、16:17:46 の `commented`（`sincetimer-android-app[bot]`）がある
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Commented、実行者は `sincetimer-android-app[bot]` になる

#### Scenario: 遠い候補は使わない

- **GIVEN** Pull request の作成日時が 09:00、スレッドの `updated_at` が 12:00 で、Timeline の作成より後の候補は 10:00 の `commented`（`bob`）と、`committer.date` が 11:00 の `committed`（12:00 に push された）だけ
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは「無い」になる（Commented by `bob` も Pushed commits も出さない）

#### Scenario: 候補にしないイベントだけ

- **GIVEN** Issue の作成日時が 10:00、スレッドの `updated_at` が 12:00 で、Timeline の 10:00 より後の項目は 12:00 の `labeled` と `cross-referenced` だけ
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは「無い」になる（`labeled` や `cross-referenced` は出さない）

#### Scenario: ボットの実行者

- **GIVEN** 最後の候補が `commented` で、`actor.login` が `dependabot[bot]`
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Commented、実行者は `dependabot[bot]` になる

#### Scenario: 妥当でない実行者

- **GIVEN** 最後の候補が `closed` で、`actor` が `null`
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは実行者なしの Closed になる
