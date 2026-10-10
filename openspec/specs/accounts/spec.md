# accounts Specification

## Purpose
gh にログイン済みのアカウントを Mewbell のアカウントとして扱うための約束を定める。アカウントの識別と並び順、ホスト種別、アカウントごとの状態、読み直しのタイミング、トークンをメモリにだけ持ち必要がなくなったら破棄することを対象とする。

## Requirements

### Requirement: アカウントの識別と並び順

Mewbell は `hosts.yml` から得たホストとユーザー名の組を 1 つのアカウントとして扱い、`<host>/<user>` で識別しなければならない（MUST）。ホスト名は小文字にそろえて比較しなければならない（MUST）。アカウントは、`github.com` を先頭に残りのホストを名前順に並べ、同じホストの中ではアクティブなユーザーを先頭に残りをユーザー名順に並べなければならない（SHALL）。

#### Scenario: 複数ホストと複数ユーザーの並び

- **GIVEN** `hosts.yml` に `ghe.example.com` の `dave`、`github.com` の `bob` と `alice`（アクティブは `bob`）がある
- **WHEN** Mewbell がアカウントを列挙する
- **THEN** `github.com/bob`、`github.com/alice`、`ghe.example.com/dave` の順になる

### Requirement: ホスト種別の判定

Mewbell はアカウントのホストを次のように分類しなければならない（MUST）: `github.com` は GitHub.com、`.ghe.com` で終わるホストは GHE Cloud（データレジデンシー）、それ以外は GitHub Enterprise Server。

#### Scenario: 3 種類のホスト

- **GIVEN** `github.com`、`acme.ghe.com`、`github.example.com` のアカウントがある
- **WHEN** Mewbell がホスト種別を判定する
- **THEN** それぞれ GitHub.com、GHE Cloud、GitHub Enterprise Server になる

### Requirement: 全体の状態

Mewbell は gh とアカウントの状態を次のいずれか 1 つにまとめなければならない（MUST）: 確認中、gh が見つからない、gh が古い、gh を実行できない、`hosts.yml` を読めない、未ログイン（アカウントが 0 件）、アカウントあり。

#### Scenario: gh が見つからない

- **GIVEN** どの候補にも使える gh が無い
- **WHEN** Mewbell がアカウントを読み込む
- **THEN** 全体の状態は「gh が見つからない」になる

#### Scenario: 未ログイン

- **GIVEN** 使える gh があり、`hosts.yml` が無い、または検証を通るアカウントが 1 つも無い
- **WHEN** Mewbell がアカウントを読み込む
- **THEN** 全体の状態は「未ログイン」になる

### Requirement: アカウントごとの状態

Mewbell はアカウントごとに、トークンの取得中、使える（トークンをメモリに持っている）、トークンを取れない、無効（ユーザーが設定で無効にした）、のいずれかの状態を持たなければならない（MUST）。無効のアカウントは、トークンをメモリに持ってはならない（MUST NOT）。1 つのアカウントでトークンを取れなくても、ほかのアカウントの状態に影響してはならない（MUST NOT）。

#### Scenario: 一部のアカウントだけトークンを取れない

- **GIVEN** `github.com/alice` と `ghe.example.com/dave` があり、`dave` の `gh auth token` が失敗する
- **WHEN** Mewbell がトークンを取得する
- **THEN** `github.com/alice` は「使える」、`ghe.example.com/dave` は「トークンを取れない」になる

#### Scenario: 無効にしたアカウント

- **GIVEN** `github.com/alice` と `github.com/bob` があり、ユーザーが設定で `bob` を無効にしている
- **WHEN** Mewbell がアカウントを読み込む
- **THEN** `github.com/alice` は「使える」、`github.com/bob` は「無効」になる

### Requirement: 読み直しのタイミング

Mewbell は、アプリの起動時、ポップオーバーを開いたとき、ユーザーが「再読み込み」を押したとき、ユーザーが設定で gh の実行ファイルのパスか gh の設定ディレクトリの上書きを変えたときに、gh の検出と `hosts.yml` の読み取りをやり直さなければならない（MUST）。読み直しのとき、すでに「使える」アカウントのために `gh auth token` を実行し直してはならず（MUST NOT）、新しく現れたアカウントと「トークンを取れない」アカウントだけトークンを取得しなければならない（MUST）。ただし次のときは、「使える」アカウントでもトークンを捨てて gh から取り直さなければならない（MUST）: API がそのアカウントのリクエストに `401` を返したとき、通知の取得が「スコープ不足」か「認証エラー」で止まっているアカウントについてユーザーが「再読み込み」を押したとき。無効のアカウントのために `gh auth token` を実行してはならない（MUST NOT）。ユーザーが設定でアカウントを有効にし直したときは、読み直しを待たずにそのアカウントのトークンを取得しなければならない（MUST）。同じアカウントのトークン取得を同時に 2 つ以上走らせてはならない（MUST NOT）。読み直しとトークンの取り直しが重なったときは、走っている取得の結果を共有しなければならない（MUST）。gh のパスが前回と同じなら、`gh --version` を実行し直さなくてよい（MAY）。

#### Scenario: ログイン後にポップオーバーを開く

- **GIVEN** 全体の状態が「未ログイン」で、ユーザーがターミナルで `gh auth login` を済ませた
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 新しいアカウントが一覧に現れ、トークンを取得する

#### Scenario: 使えるアカウントに gh を呼び直さない

- **GIVEN** `github.com/alice` が「使える」で、通知の取得もできている
- **WHEN** ユーザーがポップオーバーを開き直す
- **THEN** `github.com/alice` のための `gh auth token` は実行されない

#### Scenario: 401 の後の取り直しと読み直しが重なる

- **GIVEN** `github.com/alice` の取得で API が `401` を返し、Mewbell が `alice` のトークンを取り直している
- **WHEN** その間にユーザーがポップオーバーを開いて読み直しが始まる
- **THEN** `alice` のための `gh auth token` は 1 回だけ実行される

#### Scenario: 無効のアカウントに gh を呼ばない

- **GIVEN** ユーザーが設定で `github.com/bob` を無効にしている
- **WHEN** Mewbell を起動し、その後ユーザーが「再読み込み」を押す
- **THEN** `bob` のための `gh auth token` は一度も実行されない

#### Scenario: 有効にし直す

- **GIVEN** `github.com/bob` が「無効」
- **WHEN** ユーザーが設定で `bob` を有効にする
- **THEN** すぐに `bob` のための `gh auth token` が実行され、`bob` は「トークンの取得中」を経て「使える」になる

### Requirement: トークンをメモリにだけ持つ

Mewbell は、gh から受け取ったトークンをメモリにだけ持たなければならない（MUST）。トークンをファイル、UserDefaults、Keychain、キャッシュに書いてはならない（MUST NOT）。トークンは取得に使ったアカウント（ホストとユーザーの組）にだけ結びつけ、ほかのアカウントのために使ってはならない（MUST NOT）。Mewbell がトークンを送ってよいのは、そのアカウントのホストから導いた API ベース URL へのリクエストだけで（MUST）、それ以外の相手（Web ベース URL、ほかのホスト、ほかのアカウントの API ベース URL）に送ってはならない（MUST NOT）。

#### Scenario: 再起動するとトークンは残っていない

- **GIVEN** `github.com/alice` が「使える」
- **WHEN** Mewbell を終了して起動し直す
- **THEN** 起動直後の `github.com/alice` は「トークンの取得中」で始まり、gh からトークンを取得し直す
- **AND** Mewbell のコンテナ・`~/Library/Application Support/com.codingfeline.mewbell`・UserDefaults にトークンの値は無い

#### Scenario: トークンの送り先

- **GIVEN** `github.com/alice` と `acme.ghe.com/dave` が「使える」
- **WHEN** Mewbell が通知を取得する
- **THEN** `alice` のトークンは `https://api.github.com` へのリクエストにだけ付く
- **AND** `dave` のトークンは `https://api.acme.ghe.com` へのリクエストにだけ付く

### Requirement: 不要になったトークンの破棄

Mewbell は、アカウントが `hosts.yml` から消えたとき、全体の状態が「アカウントあり」以外になったとき、API がそのアカウントのリクエストに `401` を返したとき、ユーザーが設定でそのアカウントを無効にしたとき、アプリが終了するときに、該当するトークンをメモリから捨てなければならない（MUST）。ユーザーが設定で gh の設定ディレクトリの上書きを変えたとき（消したときを含む）は、すべてのアカウントのトークンを捨てなければならない（MUST。別の `hosts.yml` では、同じ `<host>/<user>` でも gh の別のログインを指していることがあるため）。

#### Scenario: gh auth logout したアカウント

- **GIVEN** `github.com/alice` と `github.com/bob` が「使える」
- **WHEN** ユーザーが `gh auth logout --user bob` を実行し、Mewbell がアカウントを読み直す
- **THEN** `github.com/bob` は一覧から消え、そのトークンはメモリから捨てられる
- **AND** `github.com/alice` は「使える」のまま

#### Scenario: 401 を返したトークン

- **GIVEN** `github.com/alice` が「使える」
- **WHEN** `alice` の取得で API が `401` を返す
- **THEN** `alice` のそれまでのトークンはメモリから捨てられ、二度と送られない

#### Scenario: 無効にしたアカウント

- **GIVEN** `github.com/alice` と `github.com/bob` が「使える」
- **WHEN** ユーザーが設定で `bob` を無効にする
- **THEN** `bob` のトークンはすぐにメモリから捨てられ、以後 `bob` のリクエストは送られない
- **AND** `github.com/alice` は「使える」のまま

#### Scenario: 設定ディレクトリの上書きを変える

- **GIVEN** `github.com/alice` が「使える」
- **WHEN** ユーザーが設定で gh の設定ディレクトリを `/Users/me/.gh-work` に上書きする
- **THEN** `alice` のそれまでのトークンはメモリから捨てられる
- **AND** `/Users/me/.gh-work/hosts.yml` に `alice` があれば、上書きした設定ディレクトリを渡した gh から取り直す
