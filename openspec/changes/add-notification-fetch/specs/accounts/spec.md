# Spec Delta

## MODIFIED Requirements

### Requirement: 読み直しのタイミング

Mewbell は、アプリの起動時、ポップオーバーを開いたとき、ユーザーが「再読み込み」を押したときに、gh の検出と `hosts.yml` の読み取りをやり直さなければならない（MUST）。読み直しのとき、すでに「使える」アカウントのために `gh auth token` を実行し直してはならず（MUST NOT）、新しく現れたアカウントと「トークンを取れない」アカウントだけトークンを取得しなければならない（MUST）。ただし次のときは、「使える」アカウントでもトークンを捨てて gh から取り直さなければならない（MUST）: API がそのアカウントのリクエストに `401` を返したとき、通知の取得が「スコープ不足」か「認証エラー」で止まっているアカウントについてユーザーが「再読み込み」を押したとき。同じアカウントのトークン取得を同時に 2 つ以上走らせてはならない（MUST NOT）。読み直しとトークンの取り直しが重なったときは、走っている取得の結果を共有しなければならない（MUST）。gh のパスが前回と同じなら、`gh --version` を実行し直さなくてよい（MAY）。

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

Mewbell は、アカウントが `hosts.yml` から消えたとき、全体の状態が「アカウントあり」以外になったとき、API がそのアカウントのリクエストに `401` を返したとき、アプリが終了するときに、該当するトークンをメモリから捨てなければならない（MUST）。

#### Scenario: gh auth logout したアカウント

- **GIVEN** `github.com/alice` と `github.com/bob` が「使える」
- **WHEN** ユーザーが `gh auth logout --user bob` を実行し、Mewbell がアカウントを読み直す
- **THEN** `github.com/bob` は一覧から消え、そのトークンはメモリから捨てられる
- **AND** `github.com/alice` は「使える」のまま

#### Scenario: 401 を返したトークン

- **GIVEN** `github.com/alice` が「使える」
- **WHEN** `alice` の取得で API が `401` を返す
- **THEN** `alice` のそれまでのトークンはメモリから捨てられ、二度と送られない
