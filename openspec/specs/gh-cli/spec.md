# gh-cli Specification

## Purpose
Mewbell が gh CLI を安全に見つけて実行し、gh にログイン済みのアカウントの一覧とトークンを受け取るための約束を定める。gh 実行ファイルの検出と検証、バージョンの確認、`hosts.yml` の読み取り、`gh auth token` の実行を対象とする。

## Requirements

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

### Requirement: gh 実行ファイルの検証

Mewbell は、候補のパスが次のすべてを満たすときにだけ gh として実行しなければならない（MUST）: 絶対パスである、（シンボリックリンクをたどった先が）通常ファイルである、現在のユーザーが実行できる、所有者が現在のユーザーか root である、group と world が書き込めない、ファイルを置いたディレクトリが world-writable でない（Homebrew の `bin` は admin グループが書き込める 775 なので、ディレクトリの group は許す）。満たさない候補は使ってはならない（MUST NOT）。gh はシェルを経由せず、実行ファイルのパスと引数の配列で起動しなければならない（MUST）。

#### Scenario: 誰でも書き込めるファイルは使わない

- **GIVEN** 候補のパスのファイルが world-writable である
- **WHEN** Mewbell が候補を検証する
- **THEN** その候補を使わず、次の候補を確かめる

#### Scenario: 相対パスの出力は使わない

- **GIVEN** ログインシェルの `command -v gh` が `gh`（エイリアスなど、絶対パスでない文字列）を出力する
- **WHEN** Mewbell が候補を検証する
- **THEN** gh は見つからなかったものとして扱う

### Requirement: gh のバージョン確認

Mewbell は `gh auth token` を実行する前に `gh --version` でバージョンを確かめ、バージョンを読めて 2.40.0 未満のとき（`gh auth token --user` が使えないとき）は「gh が古い」状態にし、トークンの取得を行ってはならない（MUST NOT）。`gh --version` が失敗したとき（タイムアウト、起動の失敗、終了コードが 0 以外）とバージョンを読み取れないときは、「gh が古い」ではなく「gh を実行できない」状態にし、トークンの取得を行ってはならない（MUST NOT）。この結果は覚えず、次の読み直しで確かめ直さなければならない（MUST）（初回起動の検査で遅れたなど、一時的な失敗のことがあるため）。また、gh は `hosts.yml` を解釈できないと `gh --version` でも失敗するため、バージョンの確認より先に `hosts.yml` を読み、読めないときは「hosts.yml を読めない」状態にしなければならない（MUST）。

#### Scenario: 古い gh

- **GIVEN** `gh --version` が `gh version 2.39.2 (2023-11-14)` を出力する
- **WHEN** Mewbell が gh を確かめる
- **THEN** 「gh が古い」状態になり、検出したバージョンと更新方法（`brew upgrade gh`）を案内する
- **AND** `gh auth token` は実行しない

#### Scenario: gh --version が一時的に失敗する

- **GIVEN** `hosts.yml` は読めるが、`gh --version` が 5 秒以内に終わらない
- **WHEN** Mewbell が gh を確かめる
- **THEN** 「gh を実行できない」状態になり、「gh が古い」にはならない
- **AND** 次にポップオーバーを開いたときに `gh --version` をもう一度実行する

#### Scenario: hosts.yml が壊れていて gh が起動できない

- **GIVEN** `hosts.yml` が YAML として解釈できず、`gh --version` も設定の読み込みに失敗して終了コード 1 で終わる
- **WHEN** Mewbell が gh を確かめる
- **THEN** 「hosts.yml を読めない」状態になり、「gh が古い」にはならない

#### Scenario: 対応するバージョン

- **GIVEN** `gh --version` が `gh version 2.102.0 (2026-09-30)` を出力する
- **WHEN** Mewbell が gh を確かめる
- **THEN** アカウントの読み取りに進む

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

### Requirement: ホスト名とユーザー名の検証

Mewbell は、`hosts.yml` から読んだホスト名とユーザー名を、gh の引数やアカウントの識別に使う前に検証しなければならない（MUST）。ホスト名は DNS 名として妥当（英数字とハイフンからなるラベルをドットでつないだもの、全体 253 文字以下）でなければならず、ユーザー名は英数字・ハイフン・アンダースコアだけからなる 1〜100 文字でなければならない（MUST）。どちらも `-` で始まる値は拒否しなければならない（MUST）。検証を通らないエントリは読み飛ばし、ほかのエントリの読み取りは続けなければならない（MUST）。

#### Scenario: オプションに見えるユーザー名を拒否する

- **GIVEN** `hosts.yml` の `github.com` の `users:` に `--help` と `alice` がある
- **WHEN** Mewbell が `hosts.yml` を読む
- **THEN** `alice` だけを得る
- **AND** `--help` を引数にして gh を実行することはない

#### Scenario: EMU のユーザー名を受け入れる

- **GIVEN** `hosts.yml` の `github.com` の `users:` に `alice_acme` がある
- **WHEN** Mewbell が `hosts.yml` を読む
- **THEN** `alice_acme` を得る

#### Scenario: 不正なホスト名を拒否する

- **GIVEN** `hosts.yml` に `evil host/path` というホストがある
- **WHEN** Mewbell が `hosts.yml` を読む
- **THEN** そのホストのエントリを読み飛ばす

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

### Requirement: トークンと gh の出力を漏らさない

Mewbell は、トークンをログ・エラーメッセージ・UI・デバッグ用の文字列表現に出してはならない（MUST NOT）。トークンを文字列に変換したときは伏せ字にならなければならない（MUST）。gh の標準エラー出力は UI に出してはならず（MUST NOT）、ログに残すときは `gh` に英小文字 1 文字と `_` が続く文字列（`ghp_`、`gho_`、`ghr_` など）、`github_pat_` で始まる文字列、40 桁の 16 進数（古い形式のトークン）を伏せ字にしてからにしなければならない（MUST）。

#### Scenario: トークンを文字列にすると伏せ字になる

- **GIVEN** `test-token` という値のトークンを受け取っている
- **WHEN** トークンを文字列補間・デバッグ出力・`dump` で文字列にする
- **THEN** 結果に `test-token` は含まれない

#### Scenario: 標準エラー出力のトークンを伏せる

- **GIVEN** gh の標準エラー出力に `ghp_` で始まる文字列が含まれる
- **WHEN** Mewbell がそれをログ用に整形する
- **THEN** 整形後の文字列にはその文字列が含まれず、伏せ字に置き換わっている

### Requirement: 検出の結果の記録

Mewbell は、アカウントの読み直しのたびに、gh の検出の結果として次の値をメモリに持ち、Diagnostics（diagnostics「Diagnostics タブの gh の項目」）から読めるようにしなければならない（SHALL）。

- 使っている gh の実体のパス（「gh 実行ファイルの検証」を通ったもの）と、その見つけ方: 設定の上書き、既定の場所（`/opt/homebrew/bin/gh`、`/usr/local/bin/gh`）、ログインシェル
- `gh --version` から読んだバージョン（`X.Y.Z` の数字だけ）。対応するバージョンより古いときも持つ
- 使っている gh の設定ディレクトリのパスと、その決め方: 設定の上書き、環境変数 `GH_CONFIG_DIR`、環境変数 `XDG_CONFIG_HOME`、既定の `~/.config/gh`

gh が見つからないときはパスとバージョンを、バージョンを読めないときはバージョンを、設定の上書きのディレクトリが使えないときは設定ディレクトリを、「分からない」として持たなければならない（MUST）。これらの値に前の読み直しの値を残してはならない（MUST NOT）。ただし、今回使う gh の実体のパスが前の読み直しでバージョンを確かめたものと同じなら、`hosts.yml` を読めない、または設定の上書きのディレクトリが使えないために途中で読み直しを終えたときも、確かめたバージョンを持たなければならない（MUST。バージョンは実行ファイルの性質で、`gh --version` を実行し直さずに分かるため）。gh の標準出力・標準エラー出力の文字列そのものを持ってはならない（MUST NOT）。値を記録するために、検出（「gh 実行ファイルの検出」「gh のバージョン確認」「hosts.yml の場所と読み取り」）で実行する gh のコマンド・回数・順序を変えてはならない（MUST NOT）。

#### Scenario: 既定の場所の gh

- **GIVEN** gh のパスを上書きしておらず、`/opt/homebrew/bin/gh` が検証を通り、`gh --version` が `gh version 2.62.0 (2024-11-14)` を返す
- **WHEN** Mewbell がアカウントを読み直す
- **THEN** gh の実体のパス、見つけ方「既定の場所」、バージョン `2.62.0` が記録される
- **AND** `gh --version` の出力の文字列そのものは記録されない

#### Scenario: ログインシェルで見つけた gh

- **GIVEN** 既定の場所に gh が無く、ログインシェルの `command -v gh` で `/Users/me/.local/bin/gh` が見つかって検証を通る
- **WHEN** Mewbell がアカウントを読み直す
- **THEN** gh の実体のパスと、見つけ方「ログインシェル」が記録される

#### Scenario: gh が見つからなくなった

- **GIVEN** 前の読み直しで `/opt/homebrew/bin/gh`（2.62.0）を記録していた
- **WHEN** gh がアンインストールされ、次の読み直しで gh が見つからない
- **THEN** gh のパスとバージョンは「分からない」になる

#### Scenario: hosts.yml を読めなくなっても確かめたバージョンは残す

- **GIVEN** 前の読み直しで `/opt/homebrew/bin/gh` のバージョン `2.62.0` を確かめた
- **WHEN** `hosts.yml` が壊れ、次の読み直しで全体の状態が「`hosts.yml` を読めない」になる
- **THEN** バージョン `2.62.0` は記録されたまま残り、`gh --version` は実行されない

#### Scenario: 環境変数の設定ディレクトリ

- **GIVEN** 設定ディレクトリを上書きしておらず、Mewbell の環境に `GH_CONFIG_DIR=/Users/me/gh-config` がある
- **WHEN** Mewbell がアカウントを読み直す
- **THEN** 設定ディレクトリ `/Users/me/gh-config` と、決め方「`GH_CONFIG_DIR`」が記録される

#### Scenario: バージョンが分かっていれば gh --version を繰り返さない

- **GIVEN** 前の読み直しで、同じ gh のパスと同じ設定ディレクトリでバージョン `2.62.0` を確かめている
- **WHEN** Mewbell がもう一度アカウントを読み直す
- **THEN** `gh --version` は実行されず、バージョン `2.62.0` が記録されたまま残る
