# Mewbell

macOS のメニューバーに常駐し、複数の GitHub アカウント（github.com / GHE Cloud データレジデンシー `*.ghe.com` / GHES 3.13+）の通知をまとめて受け取るアプリです。認証には [gh CLI](https://cli.github.com/) のログイン情報をそのまま使い、アプリ独自のログイン（PAT の入力や OAuth App）は持ちません。

> [!NOTE]
> 開発中です。現在は gh CLI にログイン済みのアカウントごとに未読の通知を取得してメニューバーのポップオーバーに一覧し、新しい通知を macOS の通知で知らせ、一覧からスレッドを既読・Done にしたり、アカウントごとにすべて既読にしたりでき、設定画面でアカウントごとの取得や通知、gh の場所を変え、Diagnostics で gh とアカウントの状態を確かめられる状態です（マイルストーン M4）。
>
> gh 2.40.0 以降が必要です（`gh auth token --user` を使うため）。

## 通知の取得

- 取得するのは未読の通知だけです（`GET /notifications` に `all=false`、`participating=false`）。自分が関わっていないウォッチ中のリポジトリの通知も含みます。設定でアカウントごとに、参加しているスレッドだけ（`participating=true`）にできます
- アカウントごとに独立してポーリングします。間隔は API の `X-Poll-Interval` に従い、60 秒より短くはしません。変化が無ければ `304 Not Modified` で済ませます。ただし `304` だけでは古い通知の増減や Web での既読を見落とすので、5 分ごとと再読み込みボタンを押したときは条件を付けずに取り直します。再読み込みボタンを押すと、次の予定を待たずにすぐ取り直し、終わるまでボタンが読み込み中の表示になります（アカウントごとに 10 秒に 1 回まで。レート制限中は早めません）
- ポップオーバーの一覧のスレッドや macOS の通知をクリックすると、その Pull request や Issue をブラウザで開き、既読にします
- 一覧の行にマウスを載せると「既読にする」「Done にする」のボタンが出ます（右クリックのメニューにもあります）。どちらもブラウザは開きません。Done は GitHub の受信箱から消す操作で、取り消せません
- アカウントの見出しのボタンで、そのアカウントの通知をすべて既読にできます。1 回目のクリックで確認の表示に変わり、5 秒以内にもう一度押したときだけ実行します。一覧に出ているいちばん新しいスレッドより後に届いた通知は既読にしません
- 既読・Done・すべて既読が失敗したときは、そのアカウントの区画に 1 行で知らせます。未読のままのスレッドは次の取得で一覧に戻り、その取得が成功すると知らせは消えます
- 1 回の取得で取るのは新しい順に 500 件（50 件 × 10 ページ）までです。それより古い未読があるときは、区画にそのことを出します。このときの「すべて既読」は件数を出さずに `Mark all as read?` と確認し、一覧に出ていない古い未読もまとめて既読にします
- 新しく届いたスレッドと、新しい動きがあったスレッドを macOS の通知で知らせます（1 スレッド 1 通知）。起動直後にすでにある未読は通知しません。Mewbell で既読や Done にしたスレッドの通知はすぐに、Web などで既読にしたものは次の取得で取り下げます
- メニューバーの猫アイコンの横に、全アカウントの未読の合計を出します
- gh のトークンに `repo` も `notifications` も無いアカウントは止まり、`gh auth refresh --hostname <host> --scopes repo` を案内します

## 設定

ポップオーバーの歯車のボタン（または ⌘,）で設定ウィンドウを開きます。変更はすぐに反映されます。設定は UserDefaults に保存し、トークンは保存しません。

- General: ログイン時に起動する、macOS の通知に音を付ける
- Accounts: アカウントごとに、有効・無効、参加しているスレッドだけにする、macOS の通知を出す。無効にしたアカウントはポーリングを止め、メモリ上のトークンを捨て、`gh auth token` も実行しません。参加しているスレッドだけにしたアカウントの「すべて既読」は、一覧に出ていない未読も既読にします（GitHub の API に絞り込みが無いため）
- gh: gh の実行ファイルのパスと、gh の設定ディレクトリの上書き。Finder から起動した Mewbell にはシェルで設定した `GH_CONFIG_DIR` が渡らないので、シェルで別の設定ディレクトリを使っているときはここで指定します（gh を実行するときにも `GH_CONFIG_DIR` として渡します）

- Diagnostics: 使っている gh のパスと見つけ方、バージョン、gh の設定ディレクトリとその決め方、アカウントごとのトークンの状態（トークンそのものは出しません）、取得の状態、最後に取得した時刻と次の取得の時刻、ポーリングの間隔、トークンのスコープ、件数、最後の取得と操作の失敗。「Copy」で同じ内容をテキストでコピーできます（不具合の報告に貼れるように。トークンらしい文字列は伏せ字にし、API の URL とスレッドの件名は含めません）。タブを開いても gh の実行や通知の取得はしません

「ログイン時に起動する」は、その時点の Mewbell.app の場所を登録します。`build/Debug` のビルドを登録すると、ビルドし直しや移動で外れることがあるので、`/Applications` に置いたビルドで使ってください。

## 動作環境

- macOS 26 以降
- 開発には Xcode 27.2 以降が必要です（プロジェクトは JSON 形式の `project.xcproj`。2026 年 10 月時点では beta）

## 開発

### 前提ツール

- [mise](https://mise.jdx.dev/): swiftlint と Node.js（仕様管理の [OpenSpec](https://github.com/Fission-AI/OpenSpec) CLI に使う）のバージョンを固定しています

```bash
mise install                 # mise.toml / mise.lock の swiftlint と Node.js を入れる
npm ci --ignore-scripts      # OpenSpec CLI をプロジェクトローカルに入れる
```

### ビルド・テスト・lint

```bash
bash scripts/build.sh        # build/Debug/Mewbell.app を作る（Release は引数に Release）
xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test
bash scripts/lint.sh         # swift-format（Xcode 同梱）と swiftlint
bash scripts/format.sh       # swift-format で整形する
bash scripts/run.sh          # ビルドして起動する（起動中の Mewbell は終了させる）

# push 前の確認: 警告をエラー扱いにして Debug と Release をビルドする
xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build
xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Release MEWBELL_WARNINGS_AS_ERRORS=YES build
```

CI（GitHub Actions）は ubuntu で lint と OpenSpec の検証だけを回します。ビルドとテストは CI で実行されないので、push する前に手元でテスト、lint、警告をエラー扱いにした Debug と Release のビルドを通してください。

### 進め方

仕様は [OpenSpec](https://github.com/Fission-AI/OpenSpec) で管理しています。正本は `openspec/specs/`、作業中の変更は `openspec/changes/` にあります。詳しくは [CLAUDE.md](CLAUDE.md) を参照してください。

## ライセンス

[MIT](LICENSE)
