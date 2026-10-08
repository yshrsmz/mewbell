# Proposal

## Why

マイルストーン **M0「土台」** に属する change。リポジトリにはまだ Xcode プロジェクトもアプリのコードもなく、M1 以降（gh 連携・通知取得）の実装を載せる場所がない。最初に「メニューバーに常駐して終了できるだけのアプリ」と、ビルド・lint・テストを回す仕組みを用意し、以降の change が機能追加だけに集中できるようにする。

## What Changes

- Xcode 27.2 以降の JSON プロジェクト形式（`Mewbell.xcodeproj/project.xcproj`）でアプリターゲット `Mewbell` とテストターゲット `MewbellTests` を作る
  - Bundle ID `com.codingfeline.mewbell`、Deployment target macOS 26、Swift 6（strict concurrency 有効）、App Sandbox 無効
- SwiftUI の `MenuBarExtra`（`.window` スタイル）を持つ `LSUIElement` アプリにする。メニューバーに猫アイコンが出て、ポップオーバーに「Mewbell」の表示と Quit ボタンがあり、Quit でアプリが終了する
- 二重起動を防ぐ。すでに Mewbell が動いていれば、後から起動した方はすぐに終了する（M1 以降でポーリングや通知が重複しないようにするため）
- `MewbellTests` にテストを置き、`xcodebuild test` が通る状態にする
- リポジトリの付帯ファイルを整える: MIT の `LICENSE`、`README.md`、`.gitignore`（DerivedData・`build/`・`xcuserdata/` を除外し、`.xcodeproj` はコミット対象）
- `swift-format` と `swiftlint` の設定ファイルを置く
- GitHub Actions のワークフローを追加する。macOS ランナーは高価なので、ubuntu で動く範囲（lint と OpenSpec の検証）だけを回す。xcodebuild のビルドとテストは手元で実行する

トークンや gh の呼び出しはこの change では扱わない（M1 以降）。

## Capabilities

### New Capabilities

- `ui`: メニューバー常駐アプリとしての最小の外形。メニューバーアイコンの表示、ポップオーバーの内容（アプリ名と Quit）、Dock に出ないこと、Quit で終了すること、二重起動しないこと

### Modified Capabilities

（なし。`openspec/specs/` にはまだ spec がない）

## Impact

- 追加されるもの: `Mewbell.xcodeproj/`、`Mewbell/App/`、`Mewbell/Assets.xcassets`、`MewbellTests/`、`scripts/`、`LICENSE`、`README.md`、`.swift-format`、`.swiftlint.yml`、`mise.toml`、`mise.lock`、`.github/workflows/`
- 変更されるもの: `.gitignore`
- 外部依存: アプリのランタイム依存は追加しない（Yams の導入は M1）。開発ツールとして `swift-format`（Xcode 同梱）と `swiftlint`、それらと Node.js を固定する `mise` を使う
- 開発環境の前提: Xcode 27.2 以降が必要。現在の手元環境は Xcode 27.0 で、ライセンスに未同意、`xcode-select` は CommandLineTools を指している。実装の前に Xcode の更新と切り替えが必要（tasks の先頭に置く）
- セキュリティ: トークン・gh サブプロセス・ネットワーク・URL を開く処理のいずれにも触れない。Hardened Runtime、ATS、CI の権限と Action の固定など、後から変えにくい土台の設定だけを決める（design.md「セキュリティ」）
- CI: ubuntu ランナーだけを使う。macOS 固有のビルドとテストは CI では確かめられないので、push 前に手元で通す
