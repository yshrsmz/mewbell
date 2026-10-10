## Purpose

うまく動かないときにユーザーが原因を探せるよう、Mewbell が使っている gh と設定ディレクトリ、アカウントごとのトークンと通知の取得の状態を、設定ウィンドウの Diagnostics タブに出す。出す項目、出してはならないもの、表示の更新、コピーの中身を定める。

## ADDED Requirements

### Requirement: Diagnostics タブの gh の項目

設定ウィンドウの Diagnostics タブには、gh について次の項目を表示しなければならない（SHALL）。値がまだ分からない項目（読み直しの前、gh が見つからないときのバージョンなど）は、分からないことが分かる表示にしなければならない（SHALL）。

- 全体の状態（accounts「全体の状態」: 確認中、gh が見つからない、gh が古い、gh を実行できない、`hosts.yml` を読めない、未ログイン、アカウントあり）
- 使っている gh の実体のパスと、その見つけ方（設定の上書き、既定の場所、ログインシェル）（gh-cli「検出の結果の記録」）
- gh のバージョン（`X.Y.Z`）と、対応するバージョン以上かどうか
- gh の設定ディレクトリのパスと、その決め方（設定の上書き、`GH_CONFIG_DIR`、`XDG_CONFIG_HOME`、既定の `~/.config/gh`）

#### Scenario: Homebrew の gh を使っている

- **GIVEN** gh のパスと設定ディレクトリを上書きしておらず、`/opt/homebrew/bin/gh`（2.62.0）が見つかり、環境に `GH_CONFIG_DIR` も `XDG_CONFIG_HOME` も無い
- **WHEN** ユーザーが Diagnostics タブを開く
- **THEN** gh のパスに `/opt/homebrew/bin/gh` の実体のパスと「既定の場所」が表示される
- **AND** バージョンに `2.62.0` と、対応していることが表示される
- **AND** 設定ディレクトリに `~/.config/gh` の絶対パスと「既定」が表示される

#### Scenario: gh が見つからない

- **GIVEN** 全体の状態が「gh が見つからない」
- **WHEN** ユーザーが Diagnostics タブを開く
- **THEN** 全体の状態に gh が見つからないことが表示される
- **AND** gh のパスとバージョンには、分からないことが分かる表示が出る

#### Scenario: 設定ディレクトリを上書きしている

- **GIVEN** gh の設定ディレクトリを `/Users/me/gh-work` に上書きしている
- **WHEN** ユーザーが Diagnostics タブを開く
- **THEN** 設定ディレクトリに `/Users/me/gh-work` の実体のパスと「設定の上書き」が表示される

### Requirement: Diagnostics タブのアカウントの項目

Diagnostics タブには、gh にログイン済みのアカウント（「無効」を含む）ごとに、accounts の並び順で次の項目を表示しなければならない（SHALL）。

- `<host>/<user>`、ホスト種別、gh のアクティブなアカウントかどうか
- トークンの状態（取得中、使える、トークンを取れない、無効）
- 「参加しているスレッドだけにする」と「macOS の通知を出す」の設定の値
- 通知の取得の状態（polling「取得の状態」）、最後に取得できた時刻、次の取得の予定時刻
- 使っているポーリングの間隔（秒）と、それが API の `X-Poll-Interval` によるものかどうか
- トークンのスコープの名前（`X-OAuth-Scopes` の値。まだ取得していなければ分からないことが分かる表示）
- 一覧の件数と、10 ページで打ち切ったかどうか
- 最後の取得の失敗の種類と時刻（polling「取得の状態」の分類）
- 最後の操作（既読・Done・すべて既読）の失敗の種類と時刻（polling「操作の失敗の記録」の分類）

ポーリングしていないアカウント（無効、トークンを取れない、トークンの取得中）の取得の項目は、ポーリングしていないことが分かる表示にしなければならない（SHALL）。

#### Scenario: 取得できているアカウント

- **GIVEN** `github.com/alice` が 12:00 に取得でき、`X-Poll-Interval: 60` と `X-OAuth-Scopes: repo, read:org` が返り、一覧が 3 件
- **WHEN** ユーザーが 12:00:30 に Diagnostics タブを開く
- **THEN** `alice` の項目に、取得できたこと、最後に取得できた時刻 12:00、次の取得の予定時刻 12:01、間隔 60 秒、スコープ `read:org` と `repo`、件数 3 件、打ち切っていないことが表示される

#### Scenario: 無効のアカウント

- **GIVEN** `github.com/bob` を設定で無効にしている
- **WHEN** ユーザーが Diagnostics タブを開く
- **THEN** `bob` の項目が表示され、トークンの状態は「無効」、取得の項目はポーリングしていないことが分かる表示になる

#### Scenario: 操作が失敗した後

- **GIVEN** `github.com/alice` で 12:05 にスレッドを Done にし、Done のリクエストが `500` になった
- **WHEN** ユーザーが Diagnostics タブを開く
- **THEN** `alice` の最後の操作の失敗に、Done が失敗したこと、種類が「HTTP 500」、時刻 12:05 が表示される

### Requirement: Diagnostics の表示の更新

Diagnostics タブを開いている間に、gh の検出の結果、アカウントの状態、通知の取得の状態、設定が変わったときは、タブを開き直さなくても表示をすぐに変えなければならない（SHALL）。Diagnostics タブを開いたことや表示していることで、アカウントの読み直し、gh の実行、通知の取得をしてはならない（MUST NOT）。

#### Scenario: 開いている間に取得する

- **GIVEN** Diagnostics タブを開いていて、`alice` の最後に取得できた時刻が 12:00 と表示されている
- **WHEN** 12:01 に `alice` の取得が成功する
- **THEN** タブを開き直さなくても、最後に取得できた時刻が 12:01 に変わる

#### Scenario: 開いても gh を実行しない

- **GIVEN** Mewbell が起動していて、アカウントの読み直しは終わっている
- **WHEN** ユーザーが Diagnostics タブを開く
- **THEN** gh のサブプロセスは起動されず、通知の取得のリクエストも送られない

### Requirement: Diagnostics のコピー

Diagnostics タブには、表示している内容をプレーンテキストでクリップボードにコピーするボタンがなければならない（SHALL）。コピーするテキストには、Mewbell のバージョン、macOS のバージョン、タブに表示している項目だけを入れなければならない（MUST）。コピーするテキストは、クリップボードに入れる前に、トークンらしい文字列を、gh-cli「トークンと gh の出力を漏らさない」と同じ規則（`gh` に英小文字 1 文字と `_` が続く文字列、`github_pat_` で始まる文字列、40 桁の 16 進数）で伏せ字にしなければならない（MUST）。

#### Scenario: コピーする

- **GIVEN** `github.com/alice` と `acme.ghe.com/dave` があり、Diagnostics タブを開いている
- **WHEN** ユーザーがコピーのボタンを押す
- **THEN** クリップボードに、Mewbell と macOS のバージョン、gh の項目、`alice` と `dave` の項目がテキストで入る

#### Scenario: 上書きしたパスにトークンらしい文字列がある

- **GIVEN** gh の設定ディレクトリの上書きのパスに `ghp_` で始まる文字列が含まれている
- **WHEN** ユーザーがコピーのボタンを押す
- **THEN** クリップボードのテキストでは、その文字列が伏せ字になっている

### Requirement: Diagnostics に出してはならないもの

Diagnostics タブの表示とコピーするテキストには、トークンの値・長さ・接頭辞、API の URL（ベース URL を含む）、HTTP のヘッダーの生の値（`Authorization`、`Link` など）、API のレスポンスボディ、gh の標準出力・標準エラー出力の生の文字列、通知のスレッドの件名を入れてはならない（MUST NOT）。取得と操作の失敗は、polling で定めた分類と HTTP の状態コードの数字だけで表さなければならない（MUST）。Diagnostics の値はメモリにだけ持ち、ディスク・UserDefaults に保存してはならない（MUST NOT）。

#### Scenario: 認証エラーのアカウント

- **GIVEN** `ghe.example.com/erin` が「認証エラー」で止まっている
- **WHEN** ユーザーが Diagnostics タブを開き、コピーのボタンを押す
- **THEN** 表示とクリップボードのどちらにも、`erin` のトークンの値やその一部、`https://ghe.example.com/api/v3` などの API の URL、API のレスポンスボディは含まれない
