## MODIFIED Requirements

### Requirement: gh 実行ファイルの検出

Mewbell は gh の実行ファイルを、`/opt/homebrew/bin/gh`、`/usr/local/bin/gh` の順に探さなければならない（MUST）。どちらにも使える gh が無いときに限り、ユーザーのログインシェル（ユーザーアカウントに登録されたシェルで、`/etc/shells` に載っているもの）を対話モードのログインシェルとして起動して（`~/.zshrc` などで通した PATH も拾うため）`command -v gh` を実行し、その出力の最後の空でない行をパスの候補にしなければならない（MUST）。ログインシェルでの検索は、自動では（起動時やポップオーバーを開いたときは）アプリを起動してから終了するまでに 1 回だけでなければならない（MUST）。ユーザーが「再読み込み」を押したときは、前回の検索で使える gh が見つかっていない場合に限り、もう一度検索してよい（MAY）。

ユーザーが設定（settings「設定項目と既定値」）で gh の実行ファイルのパスを上書きしているときは、そのパスだけを候補にしなければならない（MUST）。そのパスが「gh 実行ファイルの検証」を通らないときは、既定の場所やログインシェルで探し直さずに「gh が見つからない」状態にしなければならない（MUST。ユーザーが指定した gh と別の gh を黙って使わないため）。上書きを変えたとき、または消したときは、アカウントを読み直して、新しい候補で gh を確かめ直さなければならない（MUST）。

#### Scenario: Homebrew（Apple Silicon）の gh を見つける

- **GIVEN** `/opt/homebrew/bin/gh` に使える gh がある
- **WHEN** Mewbell が gh を探す
- **THEN** `/opt/homebrew/bin/gh` を使う
- **AND** ログインシェルは起動しない

#### Scenario: 既定の場所に無いときはログインシェルで探す

- **GIVEN** `/opt/homebrew/bin/gh` と `/usr/local/bin/gh` のどちらも無い
- **AND** ログインシェルの `command -v gh` が、シェルの初期化で出た行に続けて `/Users/me/.local/bin/gh` を出力する
- **WHEN** Mewbell が gh を探す
- **THEN** 最後の行の `/Users/me/.local/bin/gh` を候補として検証する

#### Scenario: 自動ではログインシェルでの検索は 1 回だけ

- **GIVEN** ログインシェルでの検索で gh が見つからなかった
- **WHEN** ユーザーがポップオーバーを開き直す
- **THEN** `/opt/homebrew/bin/gh` と `/usr/local/bin/gh` は確かめ直す
- **AND** ログインシェルは起動しない

#### Scenario: 再読み込みではログインシェルで探し直す

- **GIVEN** ログインシェルでの検索で gh が見つからず、ユーザーがその後 `~/.local/bin` に gh を入れた
- **WHEN** ユーザーが「再読み込み」を押す
- **THEN** ログインシェルでもう一度 `command -v gh` を実行し、見つけた gh を使う

#### Scenario: 見つかった後は探し直さない

- **GIVEN** ログインシェルでの検索で gh が見つかっている
- **WHEN** ユーザーが「再読み込み」を押す
- **THEN** ログインシェルは起動しない

#### Scenario: 設定で上書きしたパスを使う

- **GIVEN** `/opt/homebrew/bin/gh` に使える gh があり、ユーザーが設定で gh のパスを `/Users/me/bin/gh`（使える gh）に上書きした
- **WHEN** Mewbell が gh を探す
- **THEN** `/Users/me/bin/gh` を使い、`/opt/homebrew/bin/gh` は使わない
- **AND** ログインシェルは起動しない

#### Scenario: 上書きしたパスが使えない

- **GIVEN** `/opt/homebrew/bin/gh` に使える gh があり、ユーザーが設定で gh のパスを存在しない `/Users/me/bin/gh` に上書きした
- **WHEN** Mewbell が gh を探す
- **THEN** 「gh が見つからない」状態になり、`/opt/homebrew/bin/gh` は使わない

### Requirement: hosts.yml の場所と読み取り

Mewbell は gh の設定ディレクトリを、設定で上書きしたディレクトリ、アプリのプロセスの環境変数 `GH_CONFIG_DIR`、`XDG_CONFIG_HOME` に `gh` を足したもの、`~/.config/gh` の順に決め、その中の `hosts.yml` を読まなければならない（MUST）。設定で上書きしたディレクトリは、絶対パスで、（シンボリックリンクをたどった先が）存在するディレクトリで、所有者が現在のユーザーで、world-writable でないときだけ使わなければならない（MUST）。満たさないときは、ほかの候補に移らずに「hosts.yml を読めない」状態にし、案内にはそのディレクトリの `hosts.yml` のパスを出さなければならない（MUST）。上書きを変えたとき、または消したときは、持っているトークンをすべて捨ててから（accounts「不要になったトークンの破棄」）アカウントを読み直さなければならない（MUST）。

`hosts.yml` から取り出すのは、ホスト名、ホストごとのユーザー名の一覧、ホストのアクティブなユーザー名だけでなければならない（MUST）。`oauth_token` など、ほかのキーの値を読み取って保持してはならない（MUST NOT）。複数アカウントの形式（ホストの下の `users:` にユーザー名が並ぶ）と、それ以前の形式（ホストの下に `user:` だけがある）の両方を読めなければならない（MUST）。

#### Scenario: 複数アカウントの形式

- **GIVEN** `hosts.yml` の `github.com` の下に `users:` として `alice` と `bob` があり、`user: alice` がある
- **WHEN** Mewbell が `hosts.yml` を読む
- **THEN** `github.com` の `alice`（アクティブ）と `bob` の 2 アカウントを得る

#### Scenario: 以前の形式

- **GIVEN** `hosts.yml` の `ghe.example.com` の下に `users:` が無く、`user: carol` と `oauth_token: test-token` がある
- **WHEN** Mewbell が `hosts.yml` を読む
- **THEN** `ghe.example.com` の `carol` を得る
- **AND** `oauth_token` の値は読み取った結果のどこにも含まれない

#### Scenario: hosts.yml が無い

- **GIVEN** gh の設定ディレクトリに `hosts.yml` が無い
- **WHEN** Mewbell が `hosts.yml` を読む
- **THEN** アカウントは 0 件として扱う（「未ログイン」）

#### Scenario: hosts.yml が壊れている

- **GIVEN** `hosts.yml` が YAML として解釈できない、または読み取り権限が無い
- **WHEN** Mewbell が `hosts.yml` を読む
- **THEN** 「hosts.yml を読めない」状態になる
- **AND** ファイルの中身は UI にもログにも出さない

#### Scenario: 設定で上書きした設定ディレクトリ

- **GIVEN** Finder から起動した Mewbell のプロセスの環境に `GH_CONFIG_DIR` が無く、ユーザーが設定で gh の設定ディレクトリを `/Users/me/.gh-work` に上書きした
- **WHEN** Mewbell がアカウントを読み込む
- **THEN** `/Users/me/.gh-work/hosts.yml` を読み、`~/.config/gh/hosts.yml` は読まない

#### Scenario: 上書きした設定ディレクトリが無い

- **GIVEN** ユーザーが設定で gh の設定ディレクトリを存在しない `/Users/me/.gh-old` に上書きした
- **WHEN** Mewbell がアカウントを読み込む
- **THEN** 「hosts.yml を読めない」状態になり、案内に `/Users/me/.gh-old/hosts.yml` が出る
- **AND** `~/.config/gh/hosts.yml` は読まない

### Requirement: gh auth token の実行

Mewbell はアカウントのトークンを `gh auth token --hostname <host> --user <user>` の標準出力からだけ受け取らなければならない（MUST）。子プロセスの環境変数からは `GH_TOKEN`、`GITHUB_TOKEN`、`GH_ENTERPRISE_TOKEN`、`GITHUB_ENTERPRISE_TOKEN`、`GH_HOST` を取り除き（MUST）、`GH_PROMPT_DISABLED=1` と `GH_NO_UPDATE_NOTIFIER=1` を設定しなければならない（MUST）。設定で gh の設定ディレクトリを上書きしているときは、gh の子プロセス（`gh --version` を含む）の環境の `GH_CONFIG_DIR` をそのディレクトリにしなければならない（MUST。Mewbell が読んだ `hosts.yml` と gh が使う設定をそろえるため）。標準出力の前後の空白を除いた結果が、空でなく、空白や改行を含まない 1 行のときだけトークンとして受け入れなければならない（MUST）。終了コードが 0 以外のとき、一定時間内に終わらないとき、標準出力が上限のサイズを超えたときは子プロセスを終了させ、取得に失敗したものとして扱わなければならない（MUST）。

#### Scenario: 認証用の環境変数を渡さない

- **GIVEN** Mewbell のプロセスの環境に `GH_TOKEN` と `GH_HOST` がある
- **WHEN** Mewbell が `gh auth token --hostname github.com --user alice` を実行する
- **THEN** 子プロセスの環境に `GH_TOKEN` と `GH_HOST` は無い

#### Scenario: 上書きした設定ディレクトリを gh に渡す

- **GIVEN** Mewbell のプロセスの環境の `GH_CONFIG_DIR` が `/Users/me/.config/gh` で、ユーザーが設定で gh の設定ディレクトリを `/Users/me/.gh-work` に上書きした
- **WHEN** Mewbell が `gh auth token --hostname github.com --user alice` を実行する
- **THEN** 子プロセスの環境の `GH_CONFIG_DIR` は `/Users/me/.gh-work` になっている
- **AND** `GH_TOKEN` などの取り除く環境変数は無い

#### Scenario: gh が応答しない

- **GIVEN** gh が Keychain の確認ダイアログなどで止まり、制限時間を過ぎても終わらない
- **WHEN** Mewbell がトークンを取得しようとする
- **THEN** 子プロセスを終了させ、そのアカウントは「トークンを取れない」状態になる

#### Scenario: 出力が途中で切れているかもしれない

- **GIVEN** gh は終了したが、gh が起動した別のプロセスが標準出力を開いたまま残り、EOF が来ない
- **WHEN** Mewbell がトークンを取得しようとする
- **THEN** 読めた分をトークンとして受け取らず、取得に失敗したものとして扱う

#### Scenario: 出力が大きすぎる

- **GIVEN** gh の標準出力が上限のサイズを超える
- **WHEN** Mewbell がトークンを取得しようとする
- **THEN** 子プロセスを終了させ、取得に失敗したものとして扱う
