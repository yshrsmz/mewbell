# Proposal

## Why

マイルストーン **M1「gh 連携」** に属する change。M0 でメニューバーに常駐するだけのアプリはできたが、どの GitHub アカウントの通知を取るのかをまだ決められない。Mewbell の中核は「gh CLI にログイン済みのアカウントをそのまま使う」ことなので、通知の取得（M2）より先に、gh を見つけ、ログイン済みのアカウントを列挙し、各アカウントのトークンを gh から受け取れる状態にする。gh が無い・古い・未ログインのときにユーザーが次に何をすればよいかも、ここで示す。

## What Changes

- gh 実行ファイルを探す。`/opt/homebrew/bin/gh` → `/usr/local/bin/gh` の順に確かめ、無ければログインシェルで `command -v gh` を試す（自動では起動ごとに 1 回だけ。見つかっていなければ、ユーザーが再読み込みを押したときに探し直す）。見つけたパスは、通常ファイル・実行可能・world-writable でないことを確かめてから使う
- gh のバージョンを `gh --version` で確かめ、`gh auth token --user` が使える 2.40.0 未満なら更新を案内する
- gh の設定ディレクトリ（`GH_CONFIG_DIR` → `XDG_CONFIG_HOME/gh` → `~/.config/gh`）の `hosts.yml` を読み、ホストとユーザーの組を列挙する。複数アカウント形式（`users:`）と、それ以前の形式（ホスト直下の `user:` だけ）の両方を読む。`oauth_token` などトークンを含むキーは読まない
- ホスト名とユーザー名の形式を検証し、不正なエントリは読み飛ばす。ホスト種別（github.com / `*.ghe.com` / GHES）を判定して一覧に出す
- アカウントごとに `gh auth token --hostname <host> --user <user>` を実行し、トークンをメモリ上の actor にだけ持つ。子プロセスの環境から `GH_TOKEN` などの認証用の変数を取り除き、タイムアウトと出力サイズの上限を付ける
- 起動時、ポップオーバーを開いたとき、「再読み込み」ボタンを押したときにアカウントを読み直す。トークンを持っているアカウントには gh を呼び直さない
- ポップオーバーに状態に応じた画面を出す: アカウント一覧（ホストごと）、gh が無い、gh が古い、gh を実行できない、未ログイン、`hosts.yml` が読めない、アカウントのトークンを取れない。案内は実行すべきコマンドの表示とコピーだけにし、Mewbell がターミナルを開いたり `gh auth login` を代わりに実行したりはしない
- 外部依存として Yams 6.2.2 を追加する（`hosts.yml` の YAML を読むため）

この change では次のことはしない:

- API へのリクエストと、`X-OAuth-Scopes` によるスコープ確認（M2）
- gh のパスを設定画面で上書きする機能（M4。M1 では検出処理が上書きパスを受け取れる形にだけしておく）
- アカウントごとの ON/OFF、Diagnostics 画面（M4）

## Capabilities

### New Capabilities

- `gh-cli`: gh 実行ファイルの検出と検証、バージョン確認、`hosts.yml` の場所の決定と解析、`gh auth token` の実行（環境変数の除去・タイムアウト・出力上限・トークンの伏せ字）
- `accounts`: gh から得たアカウントの一覧と状態（使える / トークンを取れない）、ホスト種別の判定、読み直しのタイミング、トークンをメモリにだけ持つことと破棄のタイミング

### Modified Capabilities

- `ui`: ポップオーバーの中身に、アカウント一覧と各種の案内画面を足す（ADDED のみ）。既存の「Mewbell の表示と Quit ボタン」「⌘Q で終了」などの要件はそのまま満たす

## Impact

- 追加されるコード: `Mewbell/GhCLI/`、`Mewbell/Accounts/`、`Mewbell/UI/`、対応するテスト（`MewbellTests/`）。`MenuBarContentView` はアカウントの状態を表示するように変わる
- 外部依存: Yams 6.2.2（MIT、2026-05-26 公開。中身は libyaml の C ターゲットと Swift のラッパーで、ビルドプラグインやスクリプトは無い）を SwiftPM で `exactVersion` 固定で追加し、`Package.resolved` をコミットする
- **トークン: 扱う。** `gh auth token` の標準出力から受け取り、actor の中のメモリにだけ持つ。ディスク・UserDefaults・Keychain・ログには書かない。アカウントが `hosts.yml` から消えたときとアプリの終了時に破棄する。永続化しない方針（CLAUDE.md）を守る
- **gh サブプロセス: 扱う。** `gh --version`、`gh auth token`、ログインシェルでの `command -v gh` を実行する。`.claude/rules/security.md` の「gh サブプロセス」の項目がすべて適用される
- **ネットワーク: 扱わない。** M1 では Mewbell から HTTP リクエストを送らない（gh が内部で通信することはあるが、Mewbell は関与しない）
- **URL を開く処理: 扱う（固定 URL のみ）。** gh が無いときの案内で、固定の `https://cli.github.com/` をブラウザで開くボタンを置く。API レスポンスや `hosts.yml` 由来の URL は開かない
- Keychain: Mewbell は読まない。gh がトークンを Keychain に保存している場合、gh 自身が読む
- ドキュメント: `SETUP.md` の M4 の行に「gh のパスの上書き（設定画面と UserDefaults）」を書き足す
