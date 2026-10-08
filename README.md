# Mewbell

macOS のメニューバーに常駐し、複数の GitHub アカウント（github.com / GHE Cloud データレジデンシー `*.ghe.com` / GHES 3.13+）の通知をまとめて受け取るアプリです。認証には [gh CLI](https://cli.github.com/) のログイン情報をそのまま使い、アプリ独自のログイン（PAT の入力や OAuth App）は持ちません。

> [!NOTE]
> 開発中です。現在はメニューバーに常駐して終了できるだけの状態です（マイルストーン M0）。

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
bash scripts/run.sh          # ビルドして起動する（起動中の Mewbell は終了させる）

# push 前の確認: 警告をエラー扱いにして Debug と Release をビルドする
xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Release SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

CI（GitHub Actions）は ubuntu で lint と OpenSpec の検証だけを回します。ビルドとテストは CI で実行されないので、push する前に手元でテスト、lint、警告をエラー扱いにした Debug と Release のビルドを通してください。

### 進め方

仕様は [OpenSpec](https://github.com/Fission-AI/OpenSpec) で管理しています。正本は `openspec/specs/`、作業中の変更は `openspec/changes/` にあります。詳しくは [CLAUDE.md](CLAUDE.md) を参照してください。

## ライセンス

[MIT](LICENSE)
