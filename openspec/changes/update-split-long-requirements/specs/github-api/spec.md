## ADDED Requirements

### Requirement: 通知の取得の participating と続きのページ

`participating` は、そのアカウントの設定「参加しているスレッドだけにする」がオンなら `true`、オフなら `false` にしなければならない（MUST）。ページネーションの続きのページ（`Link` の `rel="next"` の URL）にも、同じ `participating` の値が付いていなければならない（MUST。GitHub は `Link` にクエリを引き継いで返す）。レスポンスの `Link` ヘッダーに `rel="next"` があるときは、そのページを順にたどらなければならない（SHALL）。

#### Scenario: 2 ページの通知

- **GIVEN** 1 ページ目の 200 のレスポンスに 50 件のスレッドと `rel="next"` があり、2 ページ目に 3 件のスレッドがある
- **WHEN** Mewbell が通知を取得する
- **THEN** 53 件のスレッドが得られる
- **AND** 結果は「打ち切っていない」

#### Scenario: 参加しているスレッドだけにしたアカウント

- **GIVEN** `acme.ghe.com/dave` は「参加しているスレッドだけにする」がオンで、`github.com/alice` はオフ
- **WHEN** Mewbell が両方の通知を取得する
- **THEN** `dave` の 1 ページ目は `GET https://api.acme.ghe.com/notifications?all=false&participating=true&per_page=50` になる
- **AND** `alice` の 1 ページ目は `GET https://api.github.com/notifications?all=false&participating=false&per_page=50` になる

### Requirement: 通知の取得のスレッドの読み取り

ページの間で同じ ID のスレッドが返ったときは、最初のものだけを残さなければならない（MUST）。スレッドからは ID、理由（`reason`）、更新日時（`updated_at`）、件名（`subject.title`）、種類（`subject.type`）、件名の API URL（`subject.url`、無いこともある）、リポジトリの `owner/name`（`repository.full_name`）を読み取り、必須の値が欠けているか `full_name` が `owner/name` の形でないスレッドは読み飛ばさなければならない（MUST）。1 ページのレスポンスボディが上限のサイズ（5 MiB）を超えたら、その回の取得は失敗として扱わなければならない（MUST）。

#### Scenario: 形の崩れたスレッドを読み飛ばす

- **GIVEN** 200 のレスポンスに 3 件のスレッドがあり、1 件は `repository.full_name` が無い
- **WHEN** Mewbell がレスポンスを読む
- **THEN** 2 件のスレッドが得られ、残りの取得は続く

### Requirement: ステータスコードの扱いの成功と一時的な失敗

Mewbell は `GET /notifications` のレスポンスを次のように扱わなければならない（MUST）。

- `200`: スレッドを読み、`Last-Modified` と `X-Poll-Interval` の値を返す
- `304`: 変化なしとして扱う（1 ページ目に `If-Modified-Since` を付けたときだけ起こる）
- 上と「ステータスコードの扱い」に無い状態コード、通信の失敗、タイムアウト（30 秒）: 一時的な失敗として扱う

#### Scenario: 304

- **GIVEN** 1 ページ目に `If-Modified-Since` を付けた `GET /notifications` に、API が `304` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「変化なし」になる

### Requirement: ステータスコードの扱いの本文

本文で二次レート制限を見分ける判定は、操作（「スレッドの既読化のリクエストのレスポンス」「スレッドを Done にするリクエストのレスポンス」「すべて既読のリクエストのレスポンス」）とスレッドのイベントの取得（「スレッドのイベントの取得のリクエストのレスポンス」）と同じにしなければならない（MUST）。見分けるために読んだ本文は、保持・ログ出力してはならない（MUST NOT）。

Mewbell は API のエラーレスポンスのボディを UI に出してはならない（MUST NOT）。

#### Scenario: 二次レート制限を見分けるために読んだ本文

- **GIVEN** API が `403` を返し、本文の `message` が二次レート制限を示す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** 見分けるために読んだ本文は保持されず、ログにも UI にも出ない

### Requirement: スレッドの既読化のリクエストのレスポンス

レスポンスは次のように扱わなければならない（MUST）。

- `205`: 既読にできた
- `304`: すでに既読だったとして、既読にできたものと同じに扱う
- `404`: スレッドがもう無い（Done にした、など）として、既読にできたものと同じに扱う
- `401`: 認証の失敗
- `403`: レート制限（`X-RateLimit-Remaining: 0` か `Retry-After` があるとき、またはそれらが無くても本文の `message` が二次レート制限を示すとき。「ステータスコードの扱い」と同じ判定）か拒否
- `429`: レート制限
- `422`、それ以外の状態コード、リダイレクト、通信の失敗、タイムアウト: 失敗

既読化のリクエストが失敗しても、トークンを取り直してはならず（MUST NOT）、そのアカウントのポーリングを止めてはならない（MUST NOT）。

#### Scenario: Done にしたスレッド

- **GIVEN** スレッド `123` は Web で Done にされている
- **WHEN** Mewbell がスレッド `123` を既読にし、API が `404` を返す
- **THEN** 既読にできたものとして扱う

#### Scenario: 既読化が二次レート制限になる

- **GIVEN** `PATCH /notifications/threads/123` に API が `403` を返し、待ち時間のヘッダーが無く、本文の `message` が二次レート制限を示す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は状態コードの失敗ではなく「レート制限」になり、トークンは取り直さず、ポーリングも止めない

### Requirement: スレッドを Done にするリクエストのレスポンス

レスポンスは次のように扱わなければならない（MUST）。

- `204`: Done にできた
- `404`: スレッドがもう無い（すでに Done にした、など）として、Done にできたものと同じに扱う
- `401`: 認証の失敗
- `403`: レート制限（`X-RateLimit-Remaining: 0` か `Retry-After` があるとき、またはそれらが無くても本文の `message` が二次レート制限を示すとき。「ステータスコードの扱い」と同じ判定）か拒否
- `429`: レート制限
- それ以外の状態コード、リダイレクト、通信の失敗、タイムアウト: 失敗

Done のリクエストが失敗しても、トークンを取り直してはならず（MUST NOT）、そのアカウントのポーリングを止めてはならない（MUST NOT）。

#### Scenario: Done の 401

- **GIVEN** `DELETE /notifications/threads/123` に API が `401` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は「認証の失敗」になり、トークンは取り直さず、ポーリングも止めない

### Requirement: すべて既読のリクエストのレスポンス

レスポンスは次のように扱わなければならない（MUST）。

- `205`: 既読にできた
- `202`: 受け付けられた（GitHub が後から非同期に既読にする）。既読にできたものと同じに扱う
- `304`: 既読にするものが無かったとして、既読にできたものと同じに扱う
- `401`: 認証の失敗
- `403`: レート制限（`X-RateLimit-Remaining: 0` か `Retry-After` があるとき、またはそれらが無くても本文の `message` が二次レート制限を示すとき。「ステータスコードの扱い」と同じ判定）か拒否
- `429`: レート制限
- それ以外の状態コード（`422` を含む）、リダイレクト、通信の失敗、タイムアウト: 失敗

すべて既読のリクエストが失敗しても、トークンを取り直してはならず（MUST NOT）、そのアカウントのポーリングを止めてはならない（MUST NOT）。

#### Scenario: 非同期に受け付けられる

- **GIVEN** `alice` の未読が多い
- **WHEN** Mewbell がすべて既読のリクエストを送り、API が `202` を返す
- **THEN** 既読にできたものとして扱う

#### Scenario: すべて既読のレート制限

- **GIVEN** `PUT /notifications` に API が `403` と `X-RateLimit-Remaining: 0` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は「レート制限」になり、ポーリングの待ち時間は変わらない

#### Scenario: すべて既読が二次レート制限になる

- **GIVEN** `PUT /notifications` に API が `403` を返し、待ち時間のヘッダーが無く、本文の `message` が二次レート制限を示す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は「レート制限」になり、ポーリングの待ち時間は変わらない

### Requirement: スレッドのイベントの取得のリクエストの URL

リクエストの URL は、`subject.url` をそのまま使わず、検証済みのリポジトリの `owner/name` と番号から組み立てなければならない（MUST）。組み立てた URL にも、「トークンを送る相手の制限」の確認をしなければならない（MUST）。「スレッドのイベントの取得のリクエスト」のリクエストにも、「トークンをリクエストごとに付ける」「リダイレクトとキャッシュ」「通信の内容をログに出さない」を同じく適用しなければならない（MUST）。Timeline のレスポンスにはコメントの本文が含まれるので、本文を保持・表示・ログ出力してはならない（MUST NOT）。

1 つのスレッドについて送るリクエストのどれかが「無い」以外の失敗になったら、そのスレッドの結果はその失敗にしなければならない（MUST）。

#### Scenario: Pull request も issues のパスで取る

- **GIVEN** `ghe.example.com/dave` のスレッドの `subject.url` が `https://ghe.example.com/api/v3/repos/team/svc/pulls/42`
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** リクエストは `https://ghe.example.com/api/v3/repos/team/svc/issues/42` と `.../issues/42/timeline?per_page=100` に送られる

### Requirement: スレッドのイベントの取得のリクエストの最後のページ

Timeline の 1 ページ目の `Link` ヘッダーに `rel="last"` があり、それが 2 ページ目以降を指すときは、その最後のページを取得しなければならない（MUST）。`Link` からはページ番号だけを読み、最後のページとその前のページの URL は 1 ページ目と同じ規則で組み立てなければならない（MUST）（API が返した URL にはトークンを送らない）。

#### Scenario: 最後のページを取る

- **GIVEN** Timeline の 1 ページ目の `Link` に `rel="last"` で `https://api.github.com/repositories/1/issues/7/timeline?per_page=100&page=5` がある
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** 5 ページ目を取得し、2〜4 ページ目は、5 ページ目が近さの幅の始まりより前まで届いていないときの 4 ページ目を除いて取得しない

#### Scenario: 最後のページが別のホストを指している

- **GIVEN** Timeline の 1 ページ目の `rel="last"` が `https://evil.example.com/timeline?page=5` を指している
- **WHEN** Mewbell が最後のページを取ろうとする
- **THEN** `evil.example.com` へのリクエストは送られず、5 ページ目は `https://api.github.com/repos/octo/app/issues/7/timeline?per_page=100&page=5` から取る

### Requirement: スレッドのイベントの取得のリクエストの前のページ

最後のページに、時刻（`created_at` か `submitted_at`。コミットの `committer.date` は Timeline の並びと合わないので使わない）が近さの幅（「スレッドのイベントの決定の近さの幅」）の始まりより前の項目が無いとき（近さの幅が前のページにかかりうるとき）は、その前のページも使わなければならない（MUST）。その前のページが 1 ページ目なら取得済みの 1 ページ目を使い、2 ページ目以降なら取得しなければならない（MUST）。1 つのスレッドについて Timeline を 3 ページより多く取得してはならない（MUST NOT）。

最後のページの前のページが「無い」ときは、取得済みのページだけでイベントを決めなければならない（MUST）。

#### Scenario: 最後のページの前のページも使う

- **GIVEN** Timeline の 1 ページ目の `Link` の `rel="last"` が 5 ページ目を指し、5 ページ目には時刻が近さの幅の始まりより前の項目が無い
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** 4 ページ目も取得して使い、Timeline の取得は 1・4・5 ページ目の 3 ページになる

### Requirement: スレッドのイベントの取得のリクエストのレスポンス

レスポンスは次のように扱わなければならない（MUST）。

- `200`: ボディを読む。形が崩れていれば一時的な失敗として扱う
- `404` / `410`: そのスレッドのイベントは「無い」として扱う（削除された、見られなくなったなど）
- `401`: 認証の失敗として扱う
- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、制限が解ける時刻を返す（「ステータスコードの扱い」と同じ判定）。待ち時間のヘッダーが無くても、本文の `message` が二次レート制限（`secondary rate limit`）を示すときはレート制限として扱う。それ以外の `403` と `422` はイベントが「無い」として扱う
- `429`: レート制限として扱う
- それ以外の状態コード、リダイレクト、通信の失敗、タイムアウト、レスポンスが大きすぎる: 一時的な失敗として扱う

#### Scenario: 削除された Issue

- **GIVEN** `GET /repos/octo/app/issues/7` が `404` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのイベントは「無い」になる

#### Scenario: レート制限

- **GIVEN** Timeline の取得に API が `403` と `X-RateLimit-Remaining: 0`、`X-RateLimit-Reset: <10 分後の時刻>` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの結果は「レート制限」になり、10 分後の時刻が得られる

### Requirement: スレッドのイベントの決定の候補のコメントとレビュー

次の `event` の項目を候補にするときは、表のイベント・時刻・実行者を使わなければならない（MUST）。

| `event` | イベント | 時刻 | 実行者 |
|---|---|---|---|
| `commented` | Commented | `created_at` | `actor.login` |
| `reviewed`（`state: approved`） | Approved | `submitted_at` | `user.login` |
| `reviewed`（`state: changes_requested`） | Requested changes | `submitted_at` | `user.login` |
| `reviewed`（`state: commented`） | Reviewed | `submitted_at` | `user.login` |

#### Scenario: 承認のレビュー

- **GIVEN** Pull request の作成日時が 10:00、スレッドの `updated_at` が 12:00 で、Timeline に `submitted_at` が 12:00 の `reviewed`（`state: approved`、`user.login: bob`）がある
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Approved、実行者は `bob` になる

### Requirement: スレッドのイベントの決定の候補の状態の変化

次の `event` の項目を候補にするときは、表のイベント・時刻・実行者を使わなければならない（MUST）。

| `event` | イベント | 時刻 | 実行者 |
|---|---|---|---|
| `closed` | Closed | `created_at` | `actor.login` |
| `reopened` | Reopened | `created_at` | `actor.login` |
| `merged` | Merged | `created_at` | `actor.login` |
| `ready_for_review` | Marked ready for review | `created_at` | `actor.login` |
| `convert_to_draft` | Converted to draft | `created_at` | `actor.login` |

#### Scenario: 下書きに戻した Pull request

- **GIVEN** Pull request の作成日時が 10:00、スレッドの `updated_at` が 12:00 で、Timeline に `created_at` が 12:00 の `convert_to_draft`（`actor.login: alice`）がある
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Converted to draft、実行者は `alice` になる

### Requirement: スレッドのイベントの決定の候補のそのほか

次の `event` の項目を候補にするときは、表のイベント・時刻・実行者を使わなければならない（MUST）。

| `event` | イベント | 時刻 | 実行者 |
|---|---|---|---|
| `review_requested` | Requested review | `created_at` | `actor.login` |
| `assigned` | Assigned | `created_at` | `actor.login` |
| `committed` | Pushed commits | `committer.date` | なし |
| `head_ref_force_pushed` | Force-pushed | `created_at` | `actor.login` |

#### Scenario: push したコミット

- **GIVEN** Pull request の作成日時が 10:00、スレッドの `updated_at` が 12:00 で、Timeline に `committer.date` が 12:00 の `committed` がある
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは実行者なしの Pushed commits になる

### Requirement: スレッドのイベントの決定の近さの幅

スレッドの `updated_at` は、きっかけになったイベントの時刻より数十秒遅れることがあるので、その分の幅を取る。

- 候補は、時刻が「件名の作成日時 + 60 秒」より後で（作成と同時に起きる `review_requested` や、作成前のコミットを除くため）、かつ「スレッドの `updated_at` − 180 秒」から「スレッドの `updated_at` + 60 秒」までの幅（「近さの幅」）に入るものに限らなければならない（MUST）。時刻を読めない項目は候補にしてはならない（MUST NOT）。近さの幅に入らない候補を、近いものが無いからといって代わりに使ってはならない（MUST NOT）（作成から時間がたってから push したコミットのように、時刻が `updated_at` を表さない項目で、古い別のイベントを拾わないため）

#### Scenario: updated_at の後の出来事は使わない

- **GIVEN** スレッドの `updated_at` が 12:00 で、Timeline に 11:59 の `closed`（`alice`）と 15:00 の `commented`（`bob`）がある
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Closed、実行者は `alice` になる

#### Scenario: 遠い候補は使わない

- **GIVEN** Pull request の作成日時が 09:00、スレッドの `updated_at` が 12:00 で、Timeline の作成より後の候補は 10:00 の `commented`（`bob`）と、`committer.date` が 11:00 の `committed`（12:00 に push された）だけ
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは「無い」になる（Commented by `bob` も Pushed commits も出さない）

### Requirement: スレッドのイベントの決定の選び方

- 候補があれば、時刻がスレッドの `updated_at` にいちばん近い候補をイベントにしなければならない（MUST）。近さが同じ候補が複数あれば、取得したページを古い順につなげたときに後ろにあるものにしなければならない（MUST）。それが `closed` で、その時刻の 60 秒前からその時刻までに `merged` があるときは、`merged` の実行者で Merged にしなければならない（MUST）。取得したページに `merged` が無くても、Issue の `pull_request.merged_at` がその幅に入るときは、`closed` の実行者で Merged にしなければならない（MUST）
- 候補が無く、件名の作成日時が近さの幅（「スレッドのイベントの決定の近さの幅」）に入るときは、件名の作成者（Issue の `user.login`）で Opened にしなければならない（MUST）
- それ以外のときは、イベントは「無い」にしなければならない（MUST）

#### Scenario: マージ

- **GIVEN** Pull request の Timeline の最後が、14:47:45 の `merged`（`williammartin`）、14:47:45 の `closed`（`williammartin`）、14:47:47 の `head_ref_deleted` で、スレッドの `updated_at` が 14:47:45
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Merged、実行者は `williammartin` になる

#### Scenario: 開かれた Pull request

- **GIVEN** Pull request の作成日時が 19:39:42、作成者が `BagToad`、スレッドの `updated_at` が 19:39:42 で、Timeline には作成前のコミットの `committed` と 19:39:43 の `review_requested` しか無い
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Opened、実行者は `BagToad` になる

#### Scenario: いちばん近い候補を選ぶ

- **GIVEN** Pull request の作成日時が 16:12:06、スレッドの `updated_at` が 16:18:08 で、Timeline に 16:17:15 の `commented`（`github-actions[bot]`）、16:17:32 の `merged` と `closed`（`yshrsmz`）、16:17:46 の `commented`（`sincetimer-android-app[bot]`）がある
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Commented、実行者は `sincetimer-android-app[bot]` になる

### Requirement: スレッドのイベントの決定の実行者

実行者のログイン名は、GitHub のログイン名として妥当な値（gh-cli のユーザー名の検証と同じ規則）か、それに `[bot]` を付けた値のときだけ使わなければならない（MUST）。ログイン名が無い（`null`、削除されたユーザーなど）か妥当でないときは、イベントは実行者なしにしなければならない（MUST）。

#### Scenario: ボットの実行者

- **GIVEN** 最後の候補が `commented` で、`actor.login` が `dependabot[bot]`
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Commented、実行者は `dependabot[bot]` になる

#### Scenario: 妥当でない実行者

- **GIVEN** 最後の候補が `closed` で、`actor` が `null`
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは実行者なしの Closed になる

### Requirement: リリースのタグの取得の tag_name

レスポンスのうち、使ってよいのは `tag_name` だけで、`html_url` などの URL や本文（`body`）を保持・表示・ログ出力してはならない（MUST NOT）。

`tag_name` は、次のすべてを満たすときだけタグとして受け付けなければならない（MUST）。満たさなければ、そのスレッドのタグは「無い」として扱わなければならない（MUST）。

- 空でなく、UTF-8 で 255 バイト以下
- 空白と制御文字を含まない
- `/` で区切った要素に、空のもの・`.`・`..` が無い

#### Scenario: 検証を通らないタグ

- **GIVEN** `GET /repos/octo/app/releases/12` が `200` と `tag_name: ../../settings` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのタグは「無い」になる

#### Scenario: html_url は使わない

- **GIVEN** `GET /repos/octo/app/releases/12` が `200` と `tag_name: v1.0.0`、`html_url: https://evil.example.com/octo/app/releases/tag/v1.0.0` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのタグは `v1.0.0` になり、`evil.example.com` の URL は覚えない

### Requirement: リリースのタグの取得のレスポンス

レスポンスは、スレッドのイベントの取得のリクエスト（「スレッドのイベントの取得のリクエストのレスポンス」）と同じく次のように扱わなければならない（MUST）。

- `200`: ボディを読む。JSON のオブジェクトでない、`tag_name` が文字列でないなど形が崩れていれば一時的な失敗として扱う
- `404` / `410`: そのスレッドのタグは「無い」として扱う（削除された、見られなくなったなど）
- `401`: 認証の失敗として扱う

#### Scenario: 削除されたリリース

- **GIVEN** `GET /repos/octo/app/releases/12` が `404` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのタグは「無い」になる

### Requirement: リリースのタグの取得のレート制限と失敗

レスポンスは、スレッドのイベントの取得のリクエスト（「スレッドのイベントの取得のリクエストのレスポンス」）と同じく次のように扱わなければならない（MUST）。

- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、制限が解ける時刻を返す（「ステータスコードの扱い」と同じ判定）。待ち時間のヘッダーが無くても、本文の `message` が二次レート制限（`secondary rate limit`）を示すときはレート制限として扱う。それ以外の `403` と `422` はタグが「無い」として扱う
- `429`: レート制限として扱う
- 上と「リリースのタグの取得のレスポンス」に無い状態コード、リダイレクト、通信の失敗、タイムアウト、レスポンスが大きすぎる: 一時的な失敗として扱う

#### Scenario: リリースのタグの取得のレート制限

- **GIVEN** リリースのタグの取得に API が `403` と `X-RateLimit-Remaining: 0`、`X-RateLimit-Reset: <10 分後の時刻>` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの結果は「レート制限」になり、10 分後の時刻が得られる

### Requirement: ワークフローの実行の検索の承認を待っている run の一覧

種類が `WorkflowRun` のスレッド（デプロイの承認リクエスト）は、次のように run を決めなければならない（MUST）。1 つのスレッドについて送るリクエストは最大 6 回にしなければならない（MUST。「ワークフローの実行の検索の通知より前に作られた run」のリクエストは「ワークフローの実行の検索の承認できる run」の `pending_deployments` と同じ回には送らない）。

1. `GET <API ベース URL>/repos/{owner}/{name}/actions/runs?status=waiting&per_page=6` で、承認を待っている run を取る
2. 1 件も無ければ、run は「無い」

#### Scenario: 承認を待っている 1 件の run を承認できない

- **GIVEN** 承認を待っている run が `103` の 1 件だけで、その `pending_deployments` が `current_user_can_approve: false` の待ちだけを返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は「無い」になる

### Requirement: ワークフローの実行の検索の承認できる run

種類が `WorkflowRun` のスレッド（デプロイの承認リクエスト）は、次のように run を決めなければならない（MUST）。

3. 承認を待っている run が 1〜5 件なら、それぞれの `GET <API ベース URL>/repos/{owner}/{name}/actions/runs/{run の ID}/pending_deployments` を取り、`current_user_can_approve` が true の待ちを 1 つでも持つ run のうち、`updated_at`（承認を待ち始めた時刻）とスレッドの `updated_at` の差が 10 分以内で、差が最も小さいものにする。当たる run が無いとき、差が最も小さいものが 2 件以上あるときは、run は「無い」

1 件のときも `pending_deployments` で確かめ、時刻も照らさなければならない（MUST）。通知の run がほかの人に承認された後に、ユーザーが承認できない別の run や、後から待ち始めた別の run だけが待っていることがあるため。

#### Scenario: 承認を待っている run が複数

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドのリポジトリが `octo/app` で、承認を待っている run が `101` と `102` の 2 件
- **WHEN** `GET /repos/octo/app/actions/runs/101/pending_deployments` が `current_user_can_approve: false` の待ちを、`.../102/pending_deployments` が `current_user_can_approve: true` の待ちを返す
- **THEN** そのスレッドの run は `102` になる

#### Scenario: 承認できる run が複数ある

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run が `101`（`updated_at` 11:50:30）と `102`（12:01）の 2 件あり、どちらにも `current_user_can_approve: true` の待ちがある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は `102` になる

#### Scenario: 後から待ち始めた run は選ばない

- **GIVEN** スレッドの `updated_at` が 12:00 で、承認を待っている run が `103`（`updated_at` 12:20）の 1 件だけで、`current_user_can_approve: true` の待ちがある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は「無い」になる

#### Scenario: 承認できる run が決まらない

- **GIVEN** 承認を待っている run が 2 件あり、`updated_at` がスレッドの `updated_at` の 2 分前と 2 分後で、どちらにも `current_user_can_approve: true` の待ちがある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は「無い」になる

### Requirement: ワークフローの実行の検索の承認を待っている run が多いとき

種類が `WorkflowRun` のスレッド（デプロイの承認リクエスト）は、次のように run を決めなければならない（MUST）。

4. 承認を待っている run が 6 件以上（`total_count` が 6 以上のときを含む）なら、run は「無い」

#### Scenario: 承認を待っている run が多い

- **GIVEN** `GET /repos/octo/app/actions/runs?status=waiting&per_page=6` が `total_count: 8` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** `pending_deployments` のリクエストは送られず、そのスレッドの run は「無い」になる

### Requirement: ワークフローの実行の検索の通知より前に作られた run

種類が `WorkflowRun` のスレッド（デプロイの承認リクエスト）は、次のように run を決めなければならない（MUST）。

5. 「ワークフローの実行の検索の承認を待っている run の一覧」の一覧の run をすべて見られて（`total_count` が一覧の件数以下）、そのどれも `updated_at`（承認を待ち始めた時刻）とスレッドの `updated_at` の差が 10 分以内でないとき（0 件を含む。通知の run はもう承認を待っていない）と、「ワークフローの実行の検索の承認を待っている run の一覧」の一覧が「無い」（`404` など）になったときは、「ワークフローの実行の検索の承認できる run」「ワークフローの実行の検索の承認を待っている run が多いとき」の代わりに、`GET <API ベース URL>/repos/{owner}/{name}/actions/runs?created=<=<スレッドの updated_at>&per_page=30` で、通知より前に作られた run を取る。

#### Scenario: 通知から離れた時刻に待ち始めた run だけが承認を待っている

- **GIVEN** 種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run は 15:00 に待ち始めた `201` の 1 件だけ
- **WHEN** 通知より前に作られた run の一覧が、`run_started_at` 11:59:55・`status: completed`・`updated_at` 12:05:16 の run `14190806` を返す
- **THEN** `201` の `pending_deployments` のリクエストは送られず、そのスレッドの run は `14190806` になる

### Requirement: ワークフローの実行の検索の日時の書き方

「ワークフローの実行の検索の通知より前に作られた run」の URL の `<スレッドの updated_at>` は、次のように書かなければならない（MUST）。

`<スレッドの updated_at>` は UTC の `YYYY-MM-DDTHH:MM:SSZ` の形で書き、`<=` とあわせてクエリの値としてエスケープする。

#### Scenario: 承認された後の通知

- **GIVEN** `acme.ghe.com/dave` の種類が `WorkflowRun` のスレッドのリポジトリが `team/infra`、`updated_at` が 07:16:58Z
- **AND** 承認を待っている run は 0 件
- **WHEN** `GET https://api.acme.ghe.com/repos/team/infra/actions/runs?created=%3C%3D2026-10-15T07:16:58Z&per_page=30` が、`run_started_at` 07:16:53Z・`status: completed`・`updated_at` 07:22:14Z の run `14190806` と、`run_started_at` 07:15:49Z・`status: completed`・`updated_at` 07:16:27Z の run `14190661` を返す
- **THEN** そのスレッドの run は `14190806` になる

### Requirement: ワークフローの実行の検索の通知の時刻を挟む run

種類が `WorkflowRun` のスレッド（デプロイの承認リクエスト）は、次のように run を決めなければならない（MUST）。

「ワークフローの実行の検索の通知より前に作られた run」で取った run のうち、`status` が `waiting` でなく（「ワークフローの実行の検索の承認を待っている run の一覧」の後に承認を待ち始めた run は数えない）、`run_started_at` がスレッドの `updated_at` 以前で、終わっていない（`status` が `completed` でない）か、`updated_at` がスレッドの `updated_at` 以降のもの（通知の時刻を挟む run）が 1 件だけなら、その run にする。0 件か 2 件以上なら、run は「無い」。

#### Scenario: 通知の時刻を挟む run が複数ある

- **GIVEN** 種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run は 0 件
- **WHEN** 通知より前に作られた run に、11:50〜12:10 の run と、11:55 に始まってまだ終わっていない run がある
- **THEN** そのスレッドの run は「無い」になる

#### Scenario: 一覧を取るまでに承認を待ち始めた run は数えない

- **GIVEN** 種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run は 0 件
- **WHEN** 通知より前に作られた run の一覧が、`status: waiting`・`run_started_at` 11:55 の run `104` だけを返す
- **THEN** そのスレッドの run は「無い」になる

### Requirement: ワークフローの実行の検索の通知より前に作られた run を探さないとき

通知の前後 10 分以内に承認を待ち始めた run があるとき（「ワークフローの実行の検索の承認できる run」「ワークフローの実行の検索の承認を待っている run が多いとき」で決める）と、「ワークフローの実行の検索の承認を待っている run の一覧」の一覧の run をすべては見られないときは、通知の run がまだ待っているかもしれないので、「ワークフローの実行の検索の通知より前に作られた run」のリクエストを送ってはならない（MUST NOT）。「ワークフローの実行の検索の通知より前に作られた run」のリクエストは、Mewbell がスレッドを初めて見たときに通知の run がもう承認されていた（Mewbell が起動していなかった間に届いた、一覧に出る前に Web で承認されたなど）ときのためにある。

#### Scenario: 承認を待っている run があるのに決まらない

- **GIVEN** 種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run は 11:59 に待ち始めた `103` の 1 件だけで、その `pending_deployments` が `current_user_can_approve: false` の待ちだけを返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** 通知より前に作られた run の一覧のリクエストは送られず、そのスレッドの run は「無い」になる

### Requirement: ワークフローの実行の検索の承認を待っている run を取れなかったとき

「ワークフローの実行の検索の承認を待っている run の一覧」「ワークフローの実行の検索の承認できる run」「ワークフローの実行の検索の承認を待っている run が多いとき」が一時的な失敗・認証の失敗・レート制限になったときは、「ワークフローの実行の検索の通知より前に作られた run」のリクエストを送ってはならない（MUST NOT）。

#### Scenario: 承認を待っている run の一覧が一時的に失敗した

- **GIVEN** 種類が `WorkflowRun` のスレッドの、承認を待っている run の一覧のリクエストが `502` になった
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** 通知より前に作られた run の一覧のリクエストは送られず、そのスレッドの結果は一時的な失敗になる

### Requirement: ワークフローの実行の検索の CheckSuite の件名

種類が `CheckSuite` のスレッド（ワークフローの実行の結果）は、件名を `<ワークフロー名> workflow run[, Attempt #<数字>] <結果> for <ブランチ> branch` の形として読まなければならない（MUST）。`<結果>` は `failed`、`failed at startup`、`cancelled`、`skipped`、`succeeded` のいずれかでなければならず、ワークフロー名とブランチは空でなく、UTF-8 で 255 バイト以下で、制御文字を含まないものでなければならない（MUST）。読めなければ、リクエストを送らずに run は「無い」としなければならない（MUST）。

件名から読んだ値はクエリの値としてエスケープし、`+` も `%2B` にエスケープしなければならない（MUST。`&` や `=` でクエリの意味が変わらないように、`+` が空白として読まれないように）。

#### Scenario: 試行の回数が付いた件名

- **GIVEN** 種類が `CheckSuite` のスレッドの件名が `Build and test workflow run, Attempt #2 failed for feat/a+b branch`
- **WHEN** Mewbell がそのスレッドの run を探す
- **THEN** リクエストは `https://api.github.com/repos/octo/app/actions/runs?branch=feat/a%2Bb&per_page=30` に送られ、`name` が `Build and test` の run から選ぶ

#### Scenario: 読めない件名

- **GIVEN** 種類が `CheckSuite` のスレッドの件名が `Something happened`
- **WHEN** Mewbell がそのスレッドの run を探す
- **THEN** リクエストは送られず、そのスレッドの run は「無い」になる

### Requirement: ワークフローの実行の検索の CheckSuite の run

件名を読めたら、`GET <API ベース URL>/repos/{owner}/{name}/actions/runs?branch=<ブランチ>&per_page=30` を 1 回だけ送り、`name` がワークフロー名と一致し、`conclusion` が件名の結果（`failed` は `failure`、`failed at startup` は `startup_failure`、`cancelled` は `cancelled`、`skipped` は `skipped`、`succeeded` は `success`）と一致し、`updated_at` とスレッドの `updated_at` の差が 10 分以内の run のうち、差が最も小さいものにしなければならない（MUST）。再実行で結果が変わった run は選ばない。当たる run が無いとき、差が最も小さいものが 2 件以上あるときは、run は「無い」としなければならない（MUST）。

#### Scenario: 失敗したワークフローの run を探す

- **GIVEN** `github.com/alice` の種類が `CheckSuite` のスレッドのリポジトリが `octo/app`、件名が `CI workflow run failed for main branch`、`updated_at` が 12:05
- **WHEN** `GET https://api.github.com/repos/octo/app/actions/runs?branch=main&per_page=30` が、`name: CI`・`conclusion: failure` で `updated_at` 12:04 の run `201`、`name: CI`・`conclusion: failure` で `updated_at` 11:30 の run `200`、`name: Release` で `updated_at` 12:05 の run `202`、`name: CI`・`conclusion: success` で `updated_at` 12:05 の run `203` を返す
- **THEN** そのスレッドの run は `201` になる

### Requirement: ワークフローの実行の検索のレスポンスの値

レスポンスのうち、使ってよいのは run の `id`・`name`・`conclusion`・`status`・`run_started_at`・`updated_at`・`total_count` と、待ちの `current_user_can_approve` だけで、`html_url` などの URL を保持・表示・ログ出力してはならない（MUST NOT）。`id` は 1〜20 桁の数字として読めるものだけを受け付けなければならない（MUST）。

#### Scenario: html_url は使わない

- **GIVEN** run の一覧の `200` のレスポンスの run に `html_url: https://evil.example.com/octo/app/actions/runs/1` がある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** `evil.example.com` の URL は覚えない

### Requirement: ワークフローの実行の検索のレスポンス

レスポンスは、スレッドのイベントの取得のリクエスト（「スレッドのイベントの取得のリクエストのレスポンス」）と同じく次のように扱わなければならない（MUST）。`pending_deployments` のリクエストも同じに扱い、どれか 1 つでも一時的な失敗・認証の失敗・レート制限になったら、そのスレッドの結果をそれにしなければならない（MUST）。

- `200`: ボディを読む。JSON のオブジェクト（`pending_deployments` は配列）でない、`workflow_runs` が配列でないなど形が崩れていれば一時的な失敗として扱う
- `404` / `410`: run の一覧のリクエストなら run は「無い」として扱う（承認を待っている run の一覧で「無い」になったときも、「ワークフローの実行の検索の通知より前に作られた run」のリクエストは送る）。`pending_deployments` のリクエストなら、その run は承認できないものとして扱う
- `401`: 認証の失敗として扱う

#### Scenario: Actions を読めないトークン

- **GIVEN** run の一覧のリクエストに API が `404` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は「無い」になる

### Requirement: ワークフローの実行の検索のレート制限と失敗

レスポンスは、スレッドのイベントの取得のリクエスト（「スレッドのイベントの取得のリクエストのレスポンス」）と同じく次のように扱わなければならない（MUST）。

- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、制限が解ける時刻を返す（「ステータスコードの扱い」と同じ判定）。待ち時間のヘッダーが無くても、本文の `message` が二次レート制限（`secondary rate limit`）を示すときはレート制限として扱う。それ以外の `403` と `422` は `404` と同じに扱う（トークンに Actions を読む権限が無いときなど）
- `429`: レート制限として扱う
- 上と「ワークフローの実行の検索のレスポンス」に無い状態コード、リダイレクト、通信の失敗、タイムアウト、レスポンスが大きすぎる: 一時的な失敗として扱う

#### Scenario: run の一覧が二次レート制限になる

- **GIVEN** run の一覧のリクエストに API が `403` を返し、待ち時間のヘッダーが無く、本文の `message` が二次レート制限を示す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの結果は「レート制限」になる

## MODIFIED Requirements

### Requirement: 通知の取得

Mewbell は `GET <API ベース URL>/notifications` に `all=false`、`participating`、`per_page=50` を付けて、未読の通知スレッドを取得しなければならない（SHALL）。1 回の取得でたどるのは 10 ページまでとし、それを超える分は取得しなくてよい（MAY）。10 ページ目のレスポンスにも `rel="next"` があったときは、取得の結果に「打ち切った」ことを含めなければならない（MUST）。10 ページ目までに `rel="next"` が無くなったときは「打ち切っていない」としなければならない（MUST）。打ち切ったかどうかは、ページの数とスレッドの件数ではなく、`rel="next"` の有無で決めなければならない（MUST。読み飛ばしたスレッドや重複で件数が 500 件より少なくても、続きがあれば打ち切りになる）。

#### Scenario: 10 ページで打ち切る

- **GIVEN** 1 ページ目から 10 ページ目までの 200 のレスポンスに、それぞれ 50 件のスレッドと `rel="next"` がある
- **WHEN** Mewbell が通知を取得する
- **THEN** 10 ページ目までの 500 件のスレッドが得られ、11 ページ目は要求されない
- **AND** 結果は「打ち切った」

#### Scenario: ちょうど 10 ページで終わる

- **GIVEN** 1 ページ目から 9 ページ目までに `rel="next"` があり、10 ページ目には `rel="next"` が無い
- **WHEN** Mewbell が通知を取得する
- **THEN** 結果は「打ち切っていない」

#### Scenario: 2 ページの通知

- **GIVEN** 1 ページ目の 200 のレスポンスに 50 件のスレッドと `rel="next"` があり、2 ページ目に 3 件のスレッドがある
- **WHEN** Mewbell が通知を取得する
- **THEN** 53 件のスレッドが得られる
- **AND** 結果は「打ち切っていない」

#### Scenario: 形の崩れたスレッドを読み飛ばす

- **GIVEN** 200 のレスポンスに 3 件のスレッドがあり、1 件は `repository.full_name` が無い
- **WHEN** Mewbell がレスポンスを読む
- **THEN** 2 件のスレッドが得られ、残りの取得は続く

#### Scenario: 参加しているスレッドだけにしたアカウント

- **GIVEN** `acme.ghe.com/dave` は「参加しているスレッドだけにする」がオンで、`github.com/alice` はオフ
- **WHEN** Mewbell が両方の通知を取得する
- **THEN** `dave` の 1 ページ目は `GET https://api.acme.ghe.com/notifications?all=false&participating=true&per_page=50` になる
- **AND** `alice` の 1 ページ目は `GET https://api.github.com/notifications?all=false&participating=false&per_page=50` になる

### Requirement: ステータスコードの扱い

Mewbell は `GET /notifications` のレスポンスを次のように扱わなければならない（MUST）。

- `401`: 認証の失敗（トークンが無効）として扱う
- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、`Retry-After` の秒数か `X-RateLimit-Reset` の時刻を返す。待ち時間のヘッダーが無くても、本文の `message` が二次レート制限（`secondary rate limit`。大文字と小文字は区別しない）を示すときは、待ち時間が分からないレート制限として扱う。それ以外は拒否として扱う
- `429`: レート制限（二次レート制限）として扱い、`Retry-After` があればその秒数を返す。待ち時間のヘッダーが無ければ、待ち時間が分からないレート制限として扱う
- `422`: リクエストの誤りとして扱う

#### Scenario: 401

- **GIVEN** API が `401` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「認証の失敗」になる

#### Scenario: レート制限の 403

- **GIVEN** API が `403` と `X-RateLimit-Remaining: 0`、`X-RateLimit-Reset: <10 分後の時刻>` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「レート制限」になり、10 分後の時刻が得られる

#### Scenario: 429

- **GIVEN** API が `429` と `Retry-After: 600` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「レート制限」になり、600 秒後の時刻が得られる

#### Scenario: 待ち時間のヘッダーが無い二次レート制限の 403

- **GIVEN** API が `403` を返し、`X-RateLimit-Remaining: 0` も `Retry-After` も無く、本文の `message` が `You have exceeded a secondary rate limit. Please wait a few minutes before you try again.` で、`X-OAuth-Scopes: repo, read:org` がある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「拒否」ではなく、待ち時間が分からない「レート制限」になる
- **AND** 本文はログにも結果にも残らない

#### Scenario: 待ち時間のヘッダーが無い 429

- **GIVEN** API が `429` を返し、`Retry-After` も `X-RateLimit-Remaining: 0` も無い
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は、待ち時間が分からない「レート制限」になる

#### Scenario: 二次レート制限でない 403

- **GIVEN** API が `403` を返し、待ち時間のヘッダーが無く、本文の `message` が `Resource not accessible by integration` である
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「拒否」になる

#### Scenario: 422

- **GIVEN** API が `422` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「リクエストの誤り」になる

### Requirement: スレッドの既読化のリクエスト

Mewbell は、スレッドを既読にするとき、`PATCH <API ベース URL>/notifications/threads/<threadId>` をそのスレッドのアカウントのトークンを付けて送らなければならない（SHALL）。リクエストのヘッダーとオリジン検査は `GET /notifications` と同じにしなければならない（MUST。「トークンをリクエストごとに付ける」「トークンを送る相手の制限」「リダイレクトとキャッシュ」）。`threadId` は 1〜20 桁の数字でなければならず、それ以外のときはリクエストを送らずに失敗として扱わなければならない（MUST）。

#### Scenario: 既読にする

- **GIVEN** `github.com/alice` のスレッド `123`
- **WHEN** Mewbell がスレッド `123` を既読にする
- **THEN** `PATCH https://api.github.com/notifications/threads/123` が `Authorization: Bearer <alice のトークン>` 付きで送られる
- **AND** API が `205` を返したら、既読にできたものとして扱う

#### Scenario: GHES のスレッドを既読にする

- **GIVEN** `ghe.example.com/dave` のスレッド `77`
- **WHEN** Mewbell がスレッド `77` を既読にする
- **THEN** `PATCH https://ghe.example.com/api/v3/notifications/threads/77` が `dave` のトークンで送られる

#### Scenario: スレッド ID が数字でない

- **GIVEN** スレッド ID が `123/../../user`
- **WHEN** Mewbell がそのスレッドを既読にしようとする
- **THEN** リクエストは送られず、失敗として扱う

#### Scenario: 既読化でリダイレクトされる

- **GIVEN** `PATCH /notifications/threads/123` に API が `307` と `Location: https://evil.example.com/` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** `evil.example.com` にはリクエストを送らず、失敗として扱う

#### Scenario: Done にしたスレッド

- **GIVEN** スレッド `123` は Web で Done にされている
- **WHEN** Mewbell がスレッド `123` を既読にし、API が `404` を返す
- **THEN** 既読にできたものとして扱う

#### Scenario: 既読化が二次レート制限になる

- **GIVEN** `PATCH /notifications/threads/123` に API が `403` を返し、待ち時間のヘッダーが無く、本文の `message` が二次レート制限を示す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は状態コードの失敗ではなく「レート制限」になり、トークンは取り直さず、ポーリングも止めない

### Requirement: スレッドを Done にするリクエスト

Mewbell は、スレッドを Done にするとき、`DELETE <API ベース URL>/notifications/threads/<threadId>` をそのスレッドのアカウントのトークンを付けて送らなければならない（SHALL）。リクエストのヘッダーとオリジン検査は `GET /notifications` と同じにしなければならない（MUST。「トークンをリクエストごとに付ける」「トークンを送る相手の制限」「リダイレクトとキャッシュ」）。`threadId` は 1〜20 桁の数字でなければならず、それ以外のときはリクエストを送らずに失敗として扱わなければならない（MUST）。

#### Scenario: Done にする

- **GIVEN** `github.com/alice` のスレッド `123`
- **WHEN** Mewbell がスレッド `123` を Done にする
- **THEN** `DELETE https://api.github.com/notifications/threads/123` が `Authorization: Bearer <alice のトークン>` 付きで送られる
- **AND** API が `204` を返したら、Done にできたものとして扱う

#### Scenario: GHE Cloud のスレッドを Done にする

- **GIVEN** `acme.ghe.com/dave_acme` のスレッド `77`
- **WHEN** Mewbell がスレッド `77` を Done にする
- **THEN** `DELETE https://api.acme.ghe.com/notifications/threads/77` が `dave_acme` のトークンで送られる

#### Scenario: Done でスレッド ID が数字でない

- **GIVEN** スレッド ID が `123/../../user`
- **WHEN** Mewbell がそのスレッドを Done にしようとする
- **THEN** リクエストは送られず、失敗として扱う

#### Scenario: Done でリダイレクトされる

- **GIVEN** `DELETE /notifications/threads/123` に API が `307` と `Location: https://evil.example.com/` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** `evil.example.com` にはリクエストを送らず、失敗として扱う

#### Scenario: Done の 401

- **GIVEN** `DELETE /notifications/threads/123` に API が `401` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は「認証の失敗」になり、トークンは取り直さず、ポーリングも止めない

### Requirement: すべて既読のリクエスト

Mewbell は、アカウントの通知をすべて既読にするとき、`PUT <API ベース URL>/notifications` をそのアカウントのトークンを付けて送らなければならない（SHALL）。ボディは `Content-Type: application/json` の `{"last_read_at": "<日時>", "read": true}` にしなければならない（MUST）。`<日時>` は UTC の ISO 8601（`YYYY-MM-DDTHH:MM:SSZ`）で、呼び出し元が渡した時刻にしなければならない（MUST）。ボディにトークンを入れてはならない（MUST NOT）。リクエストのヘッダーとオリジン検査は `GET /notifications` と同じにしなければならない（MUST）。

#### Scenario: すべて既読にする

- **GIVEN** `github.com/alice`
- **WHEN** Mewbell が `alice` の通知を `2026-10-09T12:34:56Z` まで既読にする
- **THEN** `PUT https://api.github.com/notifications` が `Authorization: Bearer <alice のトークン>` 付きで送られる
- **AND** ボディは `{"last_read_at": "2026-10-09T12:34:56Z", "read": true}` で、トークンを含まない
- **AND** API が `205` を返したら、既読にできたものとして扱う

#### Scenario: GHES ですべて既読にする

- **GIVEN** `ghe.example.com/dave`
- **WHEN** Mewbell が `dave` の通知をすべて既読にする
- **THEN** `PUT https://ghe.example.com/api/v3/notifications` が `dave` のトークンで送られる

#### Scenario: すべて既読でリダイレクトされる

- **GIVEN** `PUT /notifications` に API が `302` と `Location: https://evil.example.com/` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** `evil.example.com` にはリクエストを送らず、失敗として扱う

#### Scenario: 非同期に受け付けられる

- **GIVEN** `alice` の未読が多い
- **WHEN** Mewbell がすべて既読のリクエストを送り、API が `202` を返す
- **THEN** 既読にできたものとして扱う

#### Scenario: すべて既読のレート制限

- **GIVEN** `PUT /notifications` に API が `403` と `X-RateLimit-Remaining: 0` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は「レート制限」になり、ポーリングの待ち時間は変わらない

#### Scenario: すべて既読が二次レート制限になる

- **GIVEN** `PUT /notifications` に API が `403` を返し、待ち時間のヘッダーが無く、本文の `message` が二次レート制限を示す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は「レート制限」になり、ポーリングの待ち時間は変わらない

### Requirement: スレッドのイベントの取得のリクエスト

Mewbell は、番号を持つスレッド（ui「アカウント一覧の表示のスレッドの番号」の条件を満たして `#<番号>` を出すスレッド。Issue と Pull request）についてだけ、イベントを求めるために次のリクエストを送らなければならない（SHALL）。番号を持たないスレッド（Commit・Release・Discussion・CheckSuite、`subject.url` が検証を通らないものなど）には、これらのリクエストを送ってはならない（MUST NOT）。

- `GET <API ベース URL>/repos/{owner}/{name}/issues/{番号}`（件名の作成日時・作成者・状態を得る）
- `GET <API ベース URL>/repos/{owner}/{name}/issues/{番号}/timeline?per_page=100`（1 ページ目）

#### Scenario: Issue のイベントを取る

- **GIVEN** `github.com/alice` のスレッドのリポジトリが `octo/app`、`subject.url` が `https://api.github.com/repos/octo/app/issues/7`
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** `https://api.github.com/repos/octo/app/issues/7` と `https://api.github.com/repos/octo/app/issues/7/timeline?per_page=100` に `alice` のトークンを付けたリクエストが送られる

#### Scenario: 番号を持たないスレッド

- **GIVEN** `github.com/alice` に、種類が Release のスレッドと、`subject.url` が `https://evil.example.com/repos/octo/app/issues/7` のスレッドがある
- **WHEN** Mewbell がイベントを取るスレッドを選ぶ
- **THEN** どちらのスレッドにもイベントのリクエストは送られない

#### Scenario: Pull request も issues のパスで取る

- **GIVEN** `ghe.example.com/dave` のスレッドの `subject.url` が `https://ghe.example.com/api/v3/repos/team/svc/pulls/42`
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** リクエストは `https://ghe.example.com/api/v3/repos/team/svc/issues/42` と `.../issues/42/timeline?per_page=100` に送られる

#### Scenario: 最後のページを取る

- **GIVEN** Timeline の 1 ページ目の `Link` に `rel="last"` で `https://api.github.com/repositories/1/issues/7/timeline?per_page=100&page=5` がある
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** 5 ページ目を取得し、2〜4 ページ目は、5 ページ目が近さの幅の始まりより前まで届いていないときの 4 ページ目を除いて取得しない

#### Scenario: 最後のページが別のホストを指している

- **GIVEN** Timeline の 1 ページ目の `rel="last"` が `https://evil.example.com/timeline?page=5` を指している
- **WHEN** Mewbell が最後のページを取ろうとする
- **THEN** `evil.example.com` へのリクエストは送られず、5 ページ目は `https://api.github.com/repos/octo/app/issues/7/timeline?per_page=100&page=5` から取る

#### Scenario: 削除された Issue

- **GIVEN** `GET /repos/octo/app/issues/7` が `404` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのイベントは「無い」になる

#### Scenario: レート制限

- **GIVEN** Timeline の取得に API が `403` と `X-RateLimit-Remaining: 0`、`X-RateLimit-Reset: <10 分後の時刻>` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの結果は「レート制限」になり、10 分後の時刻が得られる

### Requirement: スレッドのイベントの決定

Mewbell は、Issue と Timeline のレスポンスから、スレッドの `updated_at` を更新したイベントを「スレッドのイベントの決定の候補のコメントとレビュー」「スレッドのイベントの決定の候補の状態の変化」「スレッドのイベントの決定の候補のそのほか」「スレッドのイベントの決定の近さの幅」「スレッドのイベントの決定の選び方」「スレッドのイベントの決定の実行者」で 1 つ決めなければならない（MUST）。

Timeline の項目のうち、「スレッドのイベントの決定の候補のコメントとレビュー」「スレッドのイベントの決定の候補の状態の変化」「スレッドのイベントの決定の候補のそのほか」の表の `event` だけを候補にしなければならない（MUST）。ほかの `event`（`labeled`、`cross-referenced`、`referenced`、`mentioned`、`subscribed`、知らない値など）は候補にしてはならない（MUST NOT）。

#### Scenario: コメント

- **GIVEN** Issue `octo/app#7` の作成日時が 10:00、スレッドの `updated_at` が 12:00:30 で、Timeline の作成より後の候補が 11:30 の `labeled`（候補にしない）と 12:00 の `commented`（`actor.login: bob`）
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Commented、実行者は `bob` になる

#### Scenario: 候補にしないイベントだけ

- **GIVEN** Issue の作成日時が 10:00、スレッドの `updated_at` が 12:00 で、Timeline の 10:00 より後の項目は 12:00 の `labeled` と `cross-referenced` だけ
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは「無い」になる（`labeled` や `cross-referenced` は出さない）

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

#### Scenario: ボットの実行者

- **GIVEN** 最後の候補が `commented` で、`actor.login` が `dependabot[bot]`
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Commented、実行者は `dependabot[bot]` になる

#### Scenario: 妥当でない実行者

- **GIVEN** 最後の候補が `closed` で、`actor` が `null`
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは実行者なしの Closed になる

### Requirement: リリースのタグの取得のリクエスト

Mewbell は、リリースの ID を持つ Release のスレッド（polling「スレッドのイベントの取得のリリースのタグ」の条件を満たすもの）についてだけ、タグを求めるために `GET <API ベース URL>/repos/{owner}/{name}/releases/{ID}` を送らなければならない（SHALL）。リクエストの URL は、`subject.url` をそのまま使わず、検証済みのリポジトリの `owner/name` と検証済みの ID（1〜20 桁の数字）から組み立てなければならない（MUST）。組み立てた URL にも「トークンを送る相手の制限」の確認をしなければならず（MUST）、「トークンをリクエストごとに付ける」「リダイレクトとキャッシュ」「通信の内容をログに出さない」を同じく適用しなければならない（MUST）。1 つのスレッドについて送るリクエストは、この 1 回だけにしなければならない（MUST）。

#### Scenario: リリースのタグを取る

- **GIVEN** `github.com/alice` の種類が Release のスレッドのリポジトリが `openai/codex`、`subject.url` が `https://api.github.com/repos/openai/codex/releases/413167889`
- **WHEN** Mewbell がそのスレッドのタグを取り、API が `200` と `tag_name: rust-v0.163.0-alpha.10.1` を返す
- **THEN** リクエストは `https://api.github.com/repos/openai/codex/releases/413167889` に `alice` のトークンを付けて送られる
- **AND** そのスレッドのタグは `rust-v0.163.0-alpha.10.1` になる

#### Scenario: GHES のリリースのタグを取る

- **GIVEN** `ghe.example.com/dave` の種類が Release のスレッドのリポジトリが `team/svc`、`subject.url` が `https://ghe.example.com/api/v3/repos/team/svc/releases/12`
- **WHEN** Mewbell がそのスレッドのタグを取る
- **THEN** リクエストは `https://ghe.example.com/api/v3/repos/team/svc/releases/12` に送られる

#### Scenario: 削除されたリリース

- **GIVEN** `GET /repos/octo/app/releases/12` が `404` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのタグは「無い」になる

#### Scenario: 検証を通らないタグ

- **GIVEN** `GET /repos/octo/app/releases/12` が `200` と `tag_name: ../../settings` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのタグは「無い」になる

#### Scenario: html_url は使わない

- **GIVEN** `GET /repos/octo/app/releases/12` が `200` と `tag_name: v1.0.0`、`html_url: https://evil.example.com/octo/app/releases/tag/v1.0.0` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのタグは `v1.0.0` になり、`evil.example.com` の URL は覚えない

#### Scenario: リリースのタグの取得のレート制限

- **GIVEN** リリースのタグの取得に API が `403` と `X-RateLimit-Remaining: 0`、`X-RateLimit-Reset: <10 分後の時刻>` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの結果は「レート制限」になり、10 分後の時刻が得られる

### Requirement: ワークフローの実行の検索のリクエスト

Mewbell は、種類が `WorkflowRun` か `CheckSuite` のスレッド（polling「スレッドのイベントの取得の run の ID」の条件を満たすもの）についてだけ、そのスレッドのワークフローの実行（run）を探すために、次のリクエストを送らなければならない（SHALL）。リクエストの URL は、`subject.url` を使わず、検証済みのリポジトリの `owner/name`、検証済みの run の ID（1〜20 桁の数字）、件名から読んだ値から組み立てなければならない（MUST）。組み立てた URL にも「トークンを送る相手の制限」の確認をしなければならず（MUST）、「トークンをリクエストごとに付ける」「リダイレクトとキャッシュ」「通信の内容をログに出さない」を同じく適用しなければならない（MUST）。

#### Scenario: 承認を待っている run が 1 件

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドのリポジトリが `octo/app`
- **WHEN** Mewbell がそのスレッドの run を探し、API が `200` と、`id: 38692691414` の run 1 件を返す
- **AND** `GET /repos/octo/app/actions/runs/38692691414/pending_deployments` が `current_user_can_approve: true` の待ちを返す
- **THEN** リクエストは `https://api.github.com/repos/octo/app/actions/runs?status=waiting&per_page=6` に `alice` のトークンを付けて送られる
- **AND** そのスレッドの run は `38692691414` になる

#### Scenario: 承認を待っている 1 件の run を承認できない

- **GIVEN** 承認を待っている run が `103` の 1 件だけで、その `pending_deployments` が `current_user_can_approve: false` の待ちだけを返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は「無い」になる

#### Scenario: 承認を待っている run が複数

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドのリポジトリが `octo/app` で、承認を待っている run が `101` と `102` の 2 件
- **WHEN** `GET /repos/octo/app/actions/runs/101/pending_deployments` が `current_user_can_approve: false` の待ちを、`.../102/pending_deployments` が `current_user_can_approve: true` の待ちを返す
- **THEN** そのスレッドの run は `102` になる

#### Scenario: 承認できる run が複数ある

- **GIVEN** `github.com/alice` の種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run が `101`（`updated_at` 11:50:30）と `102`（12:01）の 2 件あり、どちらにも `current_user_can_approve: true` の待ちがある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は `102` になる

#### Scenario: 後から待ち始めた run は選ばない

- **GIVEN** スレッドの `updated_at` が 12:00 で、承認を待っている run が `103`（`updated_at` 12:20）の 1 件だけで、`current_user_can_approve: true` の待ちがある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は「無い」になる

#### Scenario: 承認できる run が決まらない

- **GIVEN** 承認を待っている run が 2 件あり、`updated_at` がスレッドの `updated_at` の 2 分前と 2 分後で、どちらにも `current_user_can_approve: true` の待ちがある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの run は「無い」になる

#### Scenario: 承認を待っている run が多い

- **GIVEN** `GET /repos/octo/app/actions/runs?status=waiting&per_page=6` が `total_count: 8` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** `pending_deployments` のリクエストは送られず、そのスレッドの run は「無い」になる

#### Scenario: 失敗したワークフローの run を探す

- **GIVEN** `github.com/alice` の種類が `CheckSuite` のスレッドのリポジトリが `octo/app`、件名が `CI workflow run failed for main branch`、`updated_at` が 12:05
- **WHEN** `GET https://api.github.com/repos/octo/app/actions/runs?branch=main&per_page=30` が、`name: CI`・`conclusion: failure` で `updated_at` 12:04 の run `201`、`name: CI`・`conclusion: failure` で `updated_at` 11:30 の run `200`、`name: Release` で `updated_at` 12:05 の run `202`、`name: CI`・`conclusion: success` で `updated_at` 12:05 の run `203` を返す
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

#### Scenario: 承認された後の通知

- **GIVEN** `acme.ghe.com/dave` の種類が `WorkflowRun` のスレッドのリポジトリが `team/infra`、`updated_at` が 07:16:58Z
- **AND** 承認を待っている run は 0 件
- **WHEN** `GET https://api.acme.ghe.com/repos/team/infra/actions/runs?created=%3C%3D2026-10-15T07:16:58Z&per_page=30` が、`run_started_at` 07:16:53Z・`status: completed`・`updated_at` 07:22:14Z の run `14190806` と、`run_started_at` 07:15:49Z・`status: completed`・`updated_at` 07:16:27Z の run `14190661` を返す
- **THEN** そのスレッドの run は `14190806` になる

#### Scenario: 通知の時刻を挟む run が複数ある

- **GIVEN** 種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run は 0 件
- **WHEN** 通知より前に作られた run に、11:50〜12:10 の run と、11:55 に始まってまだ終わっていない run がある
- **THEN** そのスレッドの run は「無い」になる

#### Scenario: 承認を待っている run があるのに決まらない

- **GIVEN** 種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run は 11:59 に待ち始めた `103` の 1 件だけで、その `pending_deployments` が `current_user_can_approve: false` の待ちだけを返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** 通知より前に作られた run の一覧のリクエストは送られず、そのスレッドの run は「無い」になる

#### Scenario: 通知から離れた時刻に待ち始めた run だけが承認を待っている

- **GIVEN** 種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run は 15:00 に待ち始めた `201` の 1 件だけ
- **WHEN** 通知より前に作られた run の一覧が、`run_started_at` 11:59:55・`status: completed`・`updated_at` 12:05:16 の run `14190806` を返す
- **THEN** `201` の `pending_deployments` のリクエストは送られず、そのスレッドの run は `14190806` になる

#### Scenario: 一覧を取るまでに承認を待ち始めた run は数えない

- **GIVEN** 種類が `WorkflowRun` のスレッドの `updated_at` が 12:00 で、承認を待っている run は 0 件
- **WHEN** 通知より前に作られた run の一覧が、`status: waiting`・`run_started_at` 11:55 の run `104` だけを返す
- **THEN** そのスレッドの run は「無い」になる

#### Scenario: 承認を待っている run の一覧が一時的に失敗した

- **GIVEN** 種類が `WorkflowRun` のスレッドの、承認を待っている run の一覧のリクエストが `502` になった
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** 通知より前に作られた run の一覧のリクエストは送られず、そのスレッドの結果は一時的な失敗になる
