## ADDED Requirements

### Requirement: 検出の結果の記録

Mewbell は、アカウントの読み直しのたびに、gh の検出の結果として次の値をメモリに持ち、Diagnostics（diagnostics「Diagnostics タブの gh の項目」）から読めるようにしなければならない（SHALL）。

- 使っている gh の実体のパス（「gh 実行ファイルの検証」を通ったもの）と、その見つけ方: 設定の上書き、既定の場所（`/opt/homebrew/bin/gh`、`/usr/local/bin/gh`）、ログインシェル
- `gh --version` から読んだバージョン（`X.Y.Z` の数字だけ）。対応するバージョンより古いときも持つ
- 使っている gh の設定ディレクトリのパスと、その決め方: 設定の上書き、環境変数 `GH_CONFIG_DIR`、環境変数 `XDG_CONFIG_HOME`、既定の `~/.config/gh`

gh が見つからないとき、バージョンを読めないとき、設定の上書きのディレクトリが使えないときは、その値を「分からない」として持たなければならない（MUST）。前の読み直しの値を残してはならない（MUST NOT）。gh の標準出力・標準エラー出力の文字列そのものを持ってはならない（MUST NOT）。値を記録するために、検出（「gh 実行ファイルの検出」「gh のバージョン確認」「hosts.yml の場所と読み取り」）で実行する gh のコマンド・回数・順序を変えてはならない（MUST NOT）。

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

#### Scenario: 環境変数の設定ディレクトリ

- **GIVEN** 設定ディレクトリを上書きしておらず、Mewbell の環境に `GH_CONFIG_DIR=/Users/me/gh-config` がある
- **WHEN** Mewbell がアカウントを読み直す
- **THEN** 設定ディレクトリ `/Users/me/gh-config` と、決め方「`GH_CONFIG_DIR`」が記録される

#### Scenario: バージョンが分かっていれば gh --version を繰り返さない

- **GIVEN** 前の読み直しで、同じ gh のパスと同じ設定ディレクトリでバージョン `2.62.0` を確かめている
- **WHEN** Mewbell がもう一度アカウントを読み直す
- **THEN** `gh --version` は実行されず、バージョン `2.62.0` が記録されたまま残る
