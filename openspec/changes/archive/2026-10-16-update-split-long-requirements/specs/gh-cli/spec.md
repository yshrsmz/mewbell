## ADDED Requirements

### Requirement: gh 実行ファイルの検出のログインシェルでの検索の回数

ログインシェルでの検索は、自動では（起動時やポップオーバーを開いたときは）アプリを起動してから終了するまでに 1 回だけでなければならない（MUST）。ユーザーが「再読み込み」を押したときは、前回の検索で使える gh が見つかっていない場合に限り、もう一度検索してよい（MAY）。

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

### Requirement: gh 実行ファイルの検出の設定による上書き

ユーザーが設定（settings「設定項目と既定値」）で gh の実行ファイルのパスを上書きしているときは、そのパスだけを候補にしなければならない（MUST）。そのパスが「gh 実行ファイルの検証」を通らないときは、既定の場所やログインシェルで探し直さずに「gh が見つからない」状態にしなければならない（MUST。ユーザーが指定した gh と別の gh を黙って使わないため）。上書きを変えたとき、または消したときは、アカウントを読み直して、新しい候補で gh を確かめ直さなければならない（MUST）。

#### Scenario: 設定で上書きしたパスを使う

- **GIVEN** `/opt/homebrew/bin/gh` に使える gh があり、ユーザーが設定で gh のパスを `/Users/me/bin/gh`（使える gh）に上書きした
- **WHEN** Mewbell が gh を探す
- **THEN** `/Users/me/bin/gh` を使い、`/opt/homebrew/bin/gh` は使わない
- **AND** ログインシェルは起動しない

#### Scenario: 上書きしたパスが使えない

- **GIVEN** `/opt/homebrew/bin/gh` に使える gh があり、ユーザーが設定で gh のパスを存在しない `/Users/me/bin/gh` に上書きした
- **WHEN** Mewbell が gh を探す
- **THEN** 「gh が見つからない」状態になり、`/opt/homebrew/bin/gh` は使わない

### Requirement: hosts.yml の場所の設定による上書き

gh の設定ディレクトリを決めるとき、設定で上書きしたディレクトリは、絶対パスで、（シンボリックリンクをたどった先が）存在するディレクトリで、所有者が現在のユーザーで、world-writable でないときだけ使わなければならない（MUST）。満たさないときは、ほかの候補に移らずに「hosts.yml を読めない」状態にし、案内にはそのディレクトリの `hosts.yml` のパスを出さなければならない（MUST）。上書きを変えたとき、または消したときは、持っているトークンをすべて捨ててから（accounts「不要になったトークンの破棄」）アカウントを読み直さなければならない（MUST）。

#### Scenario: 上書きした設定ディレクトリが無い

- **GIVEN** ユーザーが設定で gh の設定ディレクトリを存在しない `/Users/me/.gh-old` に上書きした
- **WHEN** Mewbell がアカウントを読み込む
- **THEN** 「hosts.yml を読めない」状態になり、案内に `/Users/me/.gh-old/hosts.yml` が出る
- **AND** `~/.config/gh/hosts.yml` は読まない

### Requirement: gh auth token の実行の出力の受け入れ

`gh auth token` の実行で、標準出力の前後の空白を除いた結果が、空でなく、空白や改行を含まない 1 行のときだけトークンとして受け入れなければならない（MUST）。終了コードが 0 以外のとき、一定時間内に終わらないとき、標準出力が上限のサイズを超えたときは子プロセスを終了させ、取得に失敗したものとして扱わなければならない（MUST）。

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

### Requirement: 検出の結果の記録の分からない値と前の値

gh が見つからないときはパスとバージョンを、バージョンを読めないときはバージョンを、設定の上書きのディレクトリが使えないときは設定ディレクトリを、「分からない」として持たなければならない（MUST）。「検出の結果の記録」の値に前の読み直しの値を残してはならない（MUST NOT）。ただし、今回使う gh の実体のパスが前の読み直しでバージョンを確かめたものと同じなら、`hosts.yml` を読めない、または設定の上書きのディレクトリが使えないために途中で読み直しを終えたときも、確かめたバージョンを持たなければならない（MUST。バージョンは実行ファイルの性質で、`gh --version` を実行し直さずに分かるため）。

#### Scenario: gh が見つからなくなった

- **GIVEN** 前の読み直しで `/opt/homebrew/bin/gh`（2.62.0）を記録していた
- **WHEN** gh がアンインストールされ、次の読み直しで gh が見つからない
- **THEN** gh のパスとバージョンは「分からない」になる

#### Scenario: hosts.yml を読めなくなっても確かめたバージョンは残す

- **GIVEN** 前の読み直しで `/opt/homebrew/bin/gh` のバージョン `2.62.0` を確かめた
- **WHEN** `hosts.yml` が壊れ、次の読み直しで全体の状態が「`hosts.yml` を読めない」になる
- **THEN** バージョン `2.62.0` は記録されたまま残り、`gh --version` は実行されない

#### Scenario: バージョンが分かっていれば gh --version を繰り返さない

- **GIVEN** 前の読み直しで、同じ gh のパスと同じ設定ディレクトリでバージョン `2.62.0` を確かめている
- **WHEN** Mewbell がもう一度アカウントを読み直す
- **THEN** `gh --version` は実行されず、バージョン `2.62.0` が記録されたまま残る

### Requirement: 検出の結果の記録の gh の出力と実行

検出の結果を記録するとき、gh の標準出力・標準エラー出力の文字列そのものを持ってはならない（MUST NOT）。値を記録するために、検出（「gh 実行ファイルの検出」「gh 実行ファイルの検出のログインシェルでの検索の回数」「gh のバージョン確認」「hosts.yml の場所と読み取り」）で実行する gh のコマンド・回数・順序を変えてはならない（MUST NOT）。

#### Scenario: gh の出力そのものは記録せず、記録のために gh を余計に実行しない

- **GIVEN** gh のパスを上書きしておらず、`/opt/homebrew/bin/gh` が検証を通る
- **WHEN** Mewbell がアカウントを読み直し、検出の結果を記録する
- **THEN** gh の標準出力・標準エラー出力の文字列そのものは記録されない
- **AND** 検出で実行する gh のコマンド・回数・順序は、記録しないときと同じである

## MODIFIED Requirements

### Requirement: gh 実行ファイルの検出

Mewbell は gh の実行ファイルを、`/opt/homebrew/bin/gh`、`/usr/local/bin/gh` の順に探さなければならない（MUST）。どちらにも使える gh が無いときに限り、ユーザーのログインシェル（ユーザーアカウントに登録されたシェルで、`/etc/shells` に載っているもの）を対話モードのログインシェルとして起動して（`~/.zshrc` などで通した PATH も拾うため）`command -v gh` を実行し、その出力の最後の空でない行をパスの候補にしなければならない（MUST）。

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

Mewbell は gh の設定ディレクトリを、設定で上書きしたディレクトリ、アプリのプロセスの環境変数 `GH_CONFIG_DIR`、`XDG_CONFIG_HOME` に `gh` を足したもの、`~/.config/gh` の順に決め、その中の `hosts.yml` を読まなければならない（MUST）。

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

Mewbell はアカウントのトークンを `gh auth token --hostname <host> --user <user>` の標準出力からだけ受け取らなければならない（MUST）。子プロセスの環境変数からは `GH_TOKEN`、`GITHUB_TOKEN`、`GH_ENTERPRISE_TOKEN`、`GITHUB_ENTERPRISE_TOKEN`、`GH_HOST` を取り除き（MUST）、`GH_PROMPT_DISABLED=1` と `GH_NO_UPDATE_NOTIFIER=1` を設定しなければならない（MUST）。設定で gh の設定ディレクトリを上書きしているときは、gh の子プロセス（`gh --version` を含む）の環境の `GH_CONFIG_DIR` をそのディレクトリにしなければならない（MUST。Mewbell が読んだ `hosts.yml` と gh が使う設定をそろえるため）。

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

### Requirement: 検出の結果の記録

Mewbell は、アカウントの読み直しのたびに、gh の検出の結果として次の値をメモリに持ち、Diagnostics（diagnostics「Diagnostics タブの gh の項目」）から読めるようにしなければならない（SHALL）。

- 使っている gh の実体のパス（「gh 実行ファイルの検証」を通ったもの）と、その見つけ方: 設定の上書き、既定の場所（`/opt/homebrew/bin/gh`、`/usr/local/bin/gh`）、ログインシェル
- `gh --version` から読んだバージョン（`X.Y.Z` の数字だけ）。対応するバージョンより古いときも持つ
- 使っている gh の設定ディレクトリのパスと、その決め方: 設定の上書き、環境変数 `GH_CONFIG_DIR`、環境変数 `XDG_CONFIG_HOME`、既定の `~/.config/gh`

#### Scenario: 既定の場所の gh

- **GIVEN** gh のパスを上書きしておらず、`/opt/homebrew/bin/gh` が検証を通り、`gh --version` が `gh version 2.62.0 (2024-11-14)` を返す
- **WHEN** Mewbell がアカウントを読み直す
- **THEN** gh の実体のパス、見つけ方「既定の場所」、バージョン `2.62.0` が記録される
- **AND** `gh --version` の出力の文字列そのものは記録されない

#### Scenario: ログインシェルで見つけた gh

- **GIVEN** 既定の場所に gh が無く、ログインシェルの `command -v gh` で `/Users/me/.local/bin/gh` が見つかって検証を通る
- **WHEN** Mewbell がアカウントを読み直す
- **THEN** gh の実体のパスと、見つけ方「ログインシェル」が記録される

#### Scenario: 環境変数の設定ディレクトリ

- **GIVEN** 設定ディレクトリを上書きしておらず、Mewbell の環境に `GH_CONFIG_DIR=/Users/me/gh-config` がある
- **WHEN** Mewbell がアカウントを読み直す
- **THEN** 設定ディレクトリ `/Users/me/gh-config` と、決め方「`GH_CONFIG_DIR`」が記録される

#### Scenario: gh が見つからなくなった

- **GIVEN** 前の読み直しで `/opt/homebrew/bin/gh`（2.62.0）を記録していた
- **WHEN** gh がアンインストールされ、次の読み直しで gh が見つからない
- **THEN** gh のパスとバージョンは「分からない」になる

#### Scenario: hosts.yml を読めなくなっても確かめたバージョンは残す

- **GIVEN** 前の読み直しで `/opt/homebrew/bin/gh` のバージョン `2.62.0` を確かめた
- **WHEN** `hosts.yml` が壊れ、次の読み直しで全体の状態が「`hosts.yml` を読めない」になる
- **THEN** バージョン `2.62.0` は記録されたまま残り、`gh --version` は実行されない

#### Scenario: バージョンが分かっていれば gh --version を繰り返さない

- **GIVEN** 前の読み直しで、同じ gh のパスと同じ設定ディレクトリでバージョン `2.62.0` を確かめている
- **WHEN** Mewbell がもう一度アカウントを読み直す
- **THEN** `gh --version` は実行されず、バージョン `2.62.0` が記録されたまま残る
