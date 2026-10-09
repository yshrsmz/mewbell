# Mewbell

macOS のメニューバーに常駐し、複数の GitHub アカウント（github.com / GHE Cloud データレジデンシー `*.ghe.com` / GHES 3.13+）の通知をまとめて受け取るアプリです。認証には [gh CLI](https://cli.github.com/) のログイン情報をそのまま使い、アプリ独自のログイン（PAT の入力や OAuth App）は持ちません。

> [!NOTE]
> 開発中です。現在は gh CLI にログイン済みのアカウントごとに未読の通知を取得してメニューバーのポップオーバーに一覧し、新しい通知を macOS の通知で知らせ、一覧からスレッドを既読・Done にしたり、アカウントごとにすべて既読にしたりできる状態です（マイルストーン M4 の前半）。設定画面はまだありません。
>
> gh 2.40.0 以降が必要です（`gh auth token --user` を使うため）。

## 通知の取得

- 取得するのは未読の通知だけです（`GET /notifications` に `all=false`、`participating=false`）。自分が関わっていないウォッチ中のリポジトリの通知も含みます
- アカウントごとに独立してポーリングします。間隔は API の `X-Poll-Interval` に従い、60 秒より短くはしません。変化が無ければ `304 Not Modified` で済ませます。ただし `304` だけでは古い通知の増減や Web での既読を見落とすので、5 分ごとと再読み込みボタンを押したときは条件を付けずに取り直します。再読み込みボタンを押すと、次の予定を待たずにすぐ取り直し、終わるまでボタンが読み込み中の表示になります（アカウントごとに 10 秒に 1 回まで。レート制限中は早めません）
- ポップオーバーの一覧のスレッドや macOS の通知をクリックすると、その Pull request や Issue をブラウザで開き、既読にします
- 一覧の行にマウスを載せると「既読にする」「Done にする」のボタンが出ます（右クリックのメニューにもあります）。どちらもブラウザは開きません。Done は GitHub の受信箱から消す操作で、取り消せません
- アカウントの見出しのボタンで、そのアカウントの通知をすべて既読にできます。1 回目のクリックで確認の表示に変わり、5 秒以内にもう一度押したときだけ実行します。一覧に出ているいちばん新しいスレッドより後に届いた通知は既読にしません
- 新しく届いたスレッドと、新しい動きがあったスレッドを macOS の通知で知らせます（1 スレッド 1 通知）。起動直後にすでにある未読は通知しません。Mewbell で既読や Done にしたスレッドの通知はすぐに、Web などで既読にしたものは次の取得で取り下げます
- メニューバーの猫アイコンの横に、全アカウントの未読の合計を出します
- gh のトークンに `repo` も `notifications` も無いアカウントは止まり、`gh auth refresh --hostname <host> --scopes repo` を案内します

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
