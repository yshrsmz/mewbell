## ADDED Requirements

### Requirement: Diagnostics タブのアカウントの取得の項目

Diagnostics タブには、gh にログイン済みのアカウント（「無効」を含む）ごとに、accounts の並び順で次の項目を表示しなければならない（SHALL）。

- 通知の取得の状態（polling「取得の状態」）、最後に取得できた時刻、次の取得の予定時刻
- 使っているポーリングの間隔（秒）と、それが API の `X-Poll-Interval` によるものかどうか
- トークンのスコープの名前（`X-OAuth-Scopes` の値。まだ取得していなければ分からないことが分かる表示）
- 一覧の件数と、10 ページで打ち切ったかどうか
- 最後の取得の失敗の種類と時刻（polling「取得の状態」の分類）

ポーリングしていないアカウント（無効、トークンを取れない、トークンの取得中）の取得の項目は、ポーリングしていないことが分かる表示にしなければならない（SHALL）。

#### Scenario: 取得できているアカウント

- **GIVEN** `github.com/alice` が 12:00 に取得でき、`X-Poll-Interval: 60` と `X-OAuth-Scopes: repo, read:org` が返り、一覧が 3 件
- **WHEN** ユーザーが 12:00:30 に Diagnostics タブを開く
- **THEN** `alice` の項目に、取得できたこと、最後に取得できた時刻 12:00、次の取得の予定時刻 12:01、間隔 60 秒、スコープ `read:org` と `repo`、件数 3 件、打ち切っていないことが表示される

#### Scenario: 無効のアカウント

- **GIVEN** `github.com/bob` を設定で無効にしている
- **WHEN** ユーザーが Diagnostics タブを開く
- **THEN** `bob` の項目が表示され、トークンの状態は「無効」、取得の項目はポーリングしていないことが分かる表示になる

## MODIFIED Requirements

### Requirement: Diagnostics タブのアカウントの項目

Diagnostics タブには、gh にログイン済みのアカウント（「無効」を含む）ごとに、accounts の並び順で次の項目を表示しなければならない（SHALL）。

- `<host>/<user>`、ホスト種別、gh のアクティブなアカウントかどうか
- トークンの状態（取得中、使える、トークンを取れない、無効）
- 「参加しているスレッドだけにする」と「macOS の通知を出す」の設定の値
- 最後の操作（既読・Done・すべて既読）の失敗の種類と時刻（polling「操作の失敗の記録」の分類）

#### Scenario: 操作が失敗した後

- **GIVEN** `github.com/alice` で 12:05 にスレッドを Done にし、Done のリクエストが `500` になった
- **WHEN** ユーザーが Diagnostics タブを開く
- **THEN** `alice` の最後の操作の失敗に、Done が失敗したこと、種類が「HTTP 500」、時刻 12:05 が表示される

#### Scenario: 取得できているアカウント

- **GIVEN** `github.com/alice` が 12:00 に取得でき、`X-Poll-Interval: 60` と `X-OAuth-Scopes: repo, read:org` が返り、一覧が 3 件
- **WHEN** ユーザーが 12:00:30 に Diagnostics タブを開く
- **THEN** `alice` の項目に、取得できたこと、最後に取得できた時刻 12:00、次の取得の予定時刻 12:01、間隔 60 秒、スコープ `read:org` と `repo`、件数 3 件、打ち切っていないことが表示される

#### Scenario: 無効のアカウント

- **GIVEN** `github.com/bob` を設定で無効にしている
- **WHEN** ユーザーが Diagnostics タブを開く
- **THEN** `bob` の項目が表示され、トークンの状態は「無効」、取得の項目はポーリングしていないことが分かる表示になる
