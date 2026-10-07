# Proposal

## Why

マイルストーン **M0「土台」** に属する change。リポジトリにはまだ Xcode プロジェクトもアプリのコードもなく、M1 以降（gh 連携・通知取得）の実装を載せる場所がない。最初に「メニューバーに常駐して終了できるだけのアプリ」と、ビルド・lint・テストを回す仕組みを用意し、以降の change が機能追加だけに集中できるようにする。

## What Changes

- Xcode 27.2 以降の JSON プロジェクト形式（`Mewbell.xcodeproj/project.xcproj`）でアプリターゲット `Mewbell` とテストターゲット `MewbellTests` を作る
  - Bundle ID `com.codingfeline.mewbell`、Deployment target macOS 26、Swift 6（strict concurrency 有効）、App Sandbox 無効
- SwiftUI の `MenuBarExtra`（`.window` スタイル）を持つ `LSUIElement` アプリにする。メニューバーに猫アイコンが出て、ポップオーバーに「Mewbell」の表示と Quit ボタンがあり、Quit でアプリが終了する
- `MewbellTests` にダミーテストを 1 つ置き、`xcodebuild test` が通る状態にする
- リポジトリの付帯ファイルを整える: MIT の `LICENSE`、`README.md`、`.gitignore`（DerivedData・`build/`・`xcuserdata/` を除外し、`.xcodeproj` はコミット対象）
- `swift-format` と `swiftlint` の設定ファイルを置く
- GitHub Actions のワークフローを追加する。Xcode 27.2 以降が入ったランナーを `xcode-select` で明示し、lint・ビルド・テストを実行する

トークンや gh の呼び出しはこの change では扱わない（M1 以降）。

## Capabilities

### New Capabilities

- `ui`: メニューバー常駐アプリとしての最小の外形。メニューバーアイコンの表示、ポップオーバーの内容（アプリ名と Quit）、Dock に出ないこと、Quit で終了すること

### Modified Capabilities

（なし。`openspec/specs/` にはまだ spec がない）

## Impact

- 追加されるもの: `Mewbell.xcodeproj/`、`Mewbell/App/`、`MewbellTests/`、`LICENSE`、`README.md`、`.swift-format`、`.swiftlint.yml`、`.github/workflows/`
- 変更されるもの: `.gitignore`
- 外部依存: アプリのランタイム依存は追加しない（Yams の導入は M1）。開発ツールとして `swift-format`（Xcode 同梱）と `swiftlint` を使う
- 開発環境の前提: Xcode 27.2 以降が必要。現在の手元環境は Xcode 27.0 で、ライセンスに未同意、`xcode-select` は CommandLineTools を指している。実装の前に Xcode の更新と切り替えが必要（tasks の先頭に置く）
- CI: GitHub Actions のホストランナーに Xcode 27.2 が入っているかは、実装時に runner image の一覧で確認する
