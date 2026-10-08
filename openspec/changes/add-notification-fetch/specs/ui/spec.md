# Spec Delta

## MODIFIED Requirements

### Requirement: アカウント一覧の表示

全体の状態が「アカウントあり」のとき、ポップオーバーはアカウントごとの区画を、accounts の並び順で表示しなければならない（SHALL）。区画の見出しにはユーザー名、ホスト名、ホスト種別（GitHub.com / GHE Cloud / Enterprise Server）、トークンの状態（取得中 / 使える / トークンを取れない）を出し、gh のアクティブなアカウントにはそうと分かる印を付けなければならない（SHALL）。トークンが「使える」アカウントの区画には、見出しに通知の取得の状態を出し、その下に未読の通知をリポジトリ（`owner/name`）ごとにまとめて表示しなければならない（SHALL）。リポジトリは含まれるスレッドの最新の更新日時が新しい順に、スレッドは更新日時が新しい順に並べなければならない（SHALL）。スレッドの行には、種類（Pull request / Issue / Commit / Release / Discussion など）を表すアイコン、件名、理由（`reason`）、更新日時を出さなければならない（SHALL）。未読の通知が 0 件のときは、そうと分かる表示を出さなければならない（SHALL）。一覧がポップオーバーに収まらないときは、見出しの「Mewbell」と Quit ボタンを残したまま一覧だけをスクロールできなければならない（SHALL）。トークンの値やその一部、API の URL を表示してはならない（MUST NOT）。

#### Scenario: 2 つのホストのアカウントを表示する

- **GIVEN** `github.com/alice`（使える、アクティブ）と `acme.ghe.com/dave`（使える）がある
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `alice` の区画の見出しに「github.com — GitHub.com」とアクティブの印が、`dave` の区画の見出しに「acme.ghe.com — GHE Cloud」が表示される
- **AND** どちらも「使える」状態として表示される

#### Scenario: 2 つのアカウントの通知を表示する

- **GIVEN** `github.com/alice`（使える、アクティブ）に `octo/app` の通知が 2 件と `octo/lib` の通知が 1 件あり、`acme.ghe.com/dave`（使える）に `acme/web` の通知が 1 件ある
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `alice` の区画（github.com — GitHub.com、アクティブの印付き）の下に `octo/app` と `octo/lib` の見出しと、それぞれのスレッドが表示される
- **AND** `dave` の区画（acme.ghe.com — GHE Cloud）の下に `acme/web` の見出しとスレッドが表示される

#### Scenario: 未読が無い

- **GIVEN** `github.com/alice` の取得ができていて、未読の通知が 0 件
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `alice` の区画に、未読の通知が無いことを示す表示が出る

#### Scenario: トークンを取れないアカウント

- **GIVEN** `ghe.example.com/dave` が「トークンを取れない」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `dave` の区画に警告と、実行すべきコマンド `gh auth login --hostname ghe.example.com` が表示される
- **AND** コマンドをクリップボードにコピーするボタンがある

### Requirement: 再読み込みボタン

ポップオーバーには、gh の検出とアカウントの読み取りをやり直す「再読み込み」ボタンがなければならない（SHALL）。「再読み込み」を押すと、通知の取得が「スコープ不足」か「認証エラー」で止まっているアカウントの取得も再開しなければならない（SHALL）。読み直している間はボタンを押せないようにしなければならない（SHALL）。

#### Scenario: gh をインストールした後に再読み込みする

- **GIVEN** 全体の状態が「gh が見つからない」で、ユーザーがその後 `brew install gh` と `gh auth login` を済ませた
- **WHEN** ユーザーが「再読み込み」を押す
- **THEN** 確認中の表示を経て、アカウントの区画が表示される

#### Scenario: スコープ不足からの再開

- **GIVEN** `github.com/alice` が「スコープ不足」で、ユーザーがその後スコープを足した
- **WHEN** ユーザーが「再読み込み」を押す
- **THEN** `alice` の区画は最初の取得中の表示を経て、通知の一覧になる

## ADDED Requirements

### Requirement: 通知の取得の状態の表示

ポップオーバーは、アカウントの区画に通知の取得の状態を次のように表示しなければならない（SHALL）。案内に出すコマンドにはクリップボードへのコピーボタンを付けなければならない（SHALL）。API のエラーボディや状態コードの説明文をそのまま表示してはならない（MUST NOT）。

- 最初の取得中: 進行中であることを示す表示
- 取得できた: 最後に成功した時刻
- 失敗して待っている: 取得に失敗していることと次の取得の時刻。最後に取得できた通知の一覧は残す。レート制限のときはそうと分かる表示にする
- スコープ不足: トークンに `repo` も `notifications` も無いこと、`gh auth refresh --hostname <host> --scopes repo` を実行してから再読み込みを押すよう促す文。gh のアクティブでないアカウントには、その前に `gh auth switch --hostname <host> --user <user>` を実行するよう案内する
- 認証エラー: gh のトークンが使えないこと、`gh auth login --hostname <host>` を実行してから再読み込みを押すよう促す文

#### Scenario: アクティブなアカウントのスコープ不足

- **GIVEN** `github.com/alice`（アクティブ）が「スコープ不足」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `alice` の区画に `gh auth refresh --hostname github.com --scopes repo` とコピーボタンが表示される

#### Scenario: アクティブでないアカウントのスコープ不足

- **GIVEN** `github.com/bob`（アクティブでない）が「スコープ不足」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `bob` の区画に `gh auth switch --hostname github.com --user bob` と `gh auth refresh --hostname github.com --scopes repo` が、この順にそれぞれのコピーボタン付きで表示される

#### Scenario: 認証エラー

- **GIVEN** `ghe.example.com/dave` が「認証エラー」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `dave` の区画に `gh auth login --hostname ghe.example.com` とコピーボタンが表示される

### Requirement: 通知のスレッドを開く

ポップオーバーの一覧でスレッドをクリックすると、Mewbell はそのスレッドの Web ページを既定のブラウザで開かなければならない（SHALL）。開く URL は、API のレスポンスに含まれる URL をそのまま使わず、アカウントの Web ベース URL、リポジトリの `owner/name`、`subject.url` のパスから次のように組み立てなければならない（MUST）。

- `subject.url` が API ベース URL と同じオリジンで、パスが API ベース URL のパスに続く `repos/<owner>/<name>/pulls/<番号>` のとき: `<Web ベース>/<owner>/<name>/pull/<番号>`
- 同じく `.../issues/<番号>` のとき: `<Web ベース>/<owner>/<name>/issues/<番号>`
- 同じく `.../commits/<16 進の SHA>` のとき: `<Web ベース>/<owner>/<name>/commit/<SHA>`
- 種類が Release のとき: `<Web ベース>/<owner>/<name>/releases`
- 種類が Discussion のとき: `<Web ベース>/<owner>/<name>/discussions`
- それ以外（`subject.url` が無い、形が合わない、`subject.url` の `<owner>/<name>` がスレッドのリポジトリと一致しない、などを含む）: `<Web ベース>/<owner>/<name>`

開く前に、組み立てた URL のスキームが `https` で、ホストがアカウントのホストと一致することを確かめ、一致しなければ開いてはならない（MUST NOT）。この change では、スレッドを開いても既読にしてはならない（MUST NOT）。

#### Scenario: Pull request を開く

- **GIVEN** `github.com/alice` のスレッドのリポジトリが `octo/app`、`subject.url` が `https://api.github.com/repos/octo/app/pulls/42`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/pull/42` が開く
- **AND** スレッドは一覧に未読のまま残る

#### Scenario: GHES の Issue を開く

- **GIVEN** `ghe.example.com/dave` のスレッドのリポジトリが `team/svc`、`subject.url` が `https://ghe.example.com/api/v3/repos/team/svc/issues/7`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://ghe.example.com/team/svc/issues/7` が開く

#### Scenario: subject.url が別のホストを指している

- **GIVEN** `github.com/alice` のスレッドのリポジトリが `octo/app`、`subject.url` が `https://evil.example.com/repos/octo/app/pulls/42`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app` が開く
- **AND** `evil.example.com` の URL は開かない

#### Scenario: subject.url が無い

- **GIVEN** スレッドの種類が CheckSuite で、`subject.url` が無い
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** リポジトリのページが開く
