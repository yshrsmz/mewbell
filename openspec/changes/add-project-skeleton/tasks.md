# Tasks

## 1. 開発環境の前提（ユーザー作業を含む）

- [x] 1.1 Xcode 27.2 以降をインストールし、`sudo xcode-select -s <Xcode 27.2 のパス>/Contents/Developer` と `sudo xcodebuild -license accept` を実行する（sudo が必要なのでユーザーが行う）。確認: `xcodebuild -version` が 27.2 以降を表示し、`xcode-select -p` が Xcode を指している
- [x] 1.2 リポジトリ直下に `mise.toml` を作って `swiftlint = "0.65.1"` と `node = "26.9.0"` を固定し、`mise install` と `mise lock` で `mise.lock` を生成する。確認: `mise exec -- swiftlint version` が `0.65.1` を表示し、`xcrun swift-format --version` が通る

## 2. Xcode プロジェクトとアプリ本体

- [x] 2.1 Xcode 27.2 の macOS App テンプレート（SwiftUI / Swift Testing）で `Mewbell` プロジェクトを作ってリポジトリに移し、UI テストのターゲットを消す（design.md D1）。`project.pbxproj` ではなく `Mewbell.xcodeproj/project.xcproj`（JSON）になっていることを確かめる。確認: `xcodebuild -list -project Mewbell.xcodeproj` がターゲット `Mewbell` / `MewbellTests` とスキーム `Mewbell` を表示する
- [x] 2.2 `project.xcproj` のビルド設定を design.md D1 の表どおりにする（Bundle ID、macOS 26.0、Swift 6、strict concurrency `complete`、App Sandbox 無効、Hardened Runtime 有効、`LSUIElement=YES`、ad-hoc 署名）。entitlements ファイルは作らない。確認: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -showBuildSettings | grep -E 'PRODUCT_BUNDLE_IDENTIFIER|MACOSX_DEPLOYMENT_TARGET|SWIFT_VERSION|SWIFT_STRICT_CONCURRENCY|ENABLE_APP_SANDBOX|ENABLE_HARDENED_RUNTIME|INFOPLIST_KEY_LSUIElement'` の値が表どおり（`ENABLE_HARDENED_RUNTIME` は `-configuration Release` で `YES`）。ビルドした `.app` で `codesign -d --entitlements - build/Debug/Mewbell.app` に緩める entitlement がなく、`plutil -p build/Debug/Mewbell.app/Contents/Info.plist` に `NSAppTransportSecurity` がないことも確かめる
- [x] 2.3 ソースを `Mewbell/App/` に置く（`MewbellApp.swift` と `MenuBarContentView.swift`）。`MenuBarExtra("Mewbell", systemImage: "cat.fill")` と `.menuBarExtraStyle(.window)`、「Mewbell」の `Text`、⌘Q 付きの Quit ボタン（`NSApplication.shared.terminate(nil)`）を実装する。確認: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug build` が警告なしで通る
- [x] 2.4 `MewbellTests` に Swift Testing のダミーテストを 1 つ置く（例: `#expect(Bundle.main.bundleIdentifier != nil)` のように、ホストアプリが読み込まれていることを確かめるもの）。確認: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が成功し、テストが 1 件実行されている

- [x] 2.5 二重起動を防ぐ（design.md D2a）。`SingleInstanceLock` のユニットテスト（誰も持っていなければ取れる、持たれていれば取れない、解放や破棄の後は取れる、同じ持ち主の 2 回目は成功する）を書く。確認: `xcodebuild test` でテストが通り、起動中に別のコピーを同時に 2 つ起動してもプロセスが 1 つのまま

## 3. スクリプトと lint 設定

- [x] 3.1 `scripts/build.sh` を作る（`-derivedDataPath build/DerivedData` でビルドし、`build/Debug/Mewbell.app` にコピーする）。確認: `bash scripts/build.sh` の後に `build/Debug/Mewbell.app` がある
- [x] 3.2 `scripts/run.sh` を作る（ビルドしてから `open build/Debug/Mewbell.app`）。確認: `bash scripts/run.sh` でメニューバーに猫アイコンが出る
- [x] 3.3 `.swift-format`（インデント 4、行長 120 など）と `.swiftlint.yml`（対象は `Mewbell` と `MewbellTests`、整形系ルールは無効）を置き、`scripts/lint.sh` に両方の呼び出しをまとめる。確認: `bash scripts/lint.sh` が 0 で終わる。わざと末尾空白や長い行を入れると失敗することも一度確かめて、元に戻す

## 4. リポジトリの付帯ファイル

- [x] 4.1 `.gitignore` に `build/`、`DerivedData/` を足す（`xcuserdata/`、`node_modules/`、`.DS_Store` は既にある）。`*.xcodeproj` は除外しない。確認: ビルドした後の `git status` に `build/` や `xcuserdata/` が出ず、`Mewbell.xcodeproj/project.xcproj` は出る
- [x] 4.2 MIT の `LICENSE`（著作権者 Yasuhiro Shimizu、2026 年）を置く。確認: GitHub のライセンス判定で MIT と認識される文面になっている（choosealicense.com の MIT 全文と一致）
- [x] 4.3 `README.md` を書く（概要、動作環境 macOS 26+ / Xcode 27.2+、前提ツール `mise install` と `npm ci`、ビルド・テスト・lint・起動のコマンド、ライセンス）。確認: README のコマンドを上から順にコピーして実行し、そのまま通る

## 5. CI

- [x] 5.1 `.github/workflows/ci.yml` を design.md D6 のとおりに作る（`runs-on: ubuntu-24.04`、swift-format は `swift:6.3.2-noble`、swiftlint は `ghcr.io/realm/swiftlint:0.65.1` のイメージをそれぞれ digest で固定して `docker run`、mise で Node を入れて `openspec validate --all --strict`）。`actions/checkout` と `jdx/mise-action` はコミット SHA で固定し、横にタグをコメントで書く。`permissions: contents: read` を明示し、トリガーは `pull_request` と `push` だけにする。確認: ブランチを push して PR を作り、ワークフローが緑になる
- [x] 5.2 CI と同じイメージで手元でも lint を実行し、手元の `bash scripts/lint.sh`（Xcode 同梱の swift-format と mise の swiftlint）と結果が同じになることを確かめる。確認: `docker run` で両方のイメージを実行して違反が出ない

## 6. 最終確認

- [x] 6.1 ビルドが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build` と、同じく `-configuration Release` のビルドが成功する（CI では回らないので手元で確かめる）
- [x] 6.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が成功し、`bash scripts/lint.sh` も通る
- [x] 6.3 手元で起動して確認した: `bash scripts/run.sh` で起動し、spec のシナリオを手で確かめる。メニューバーに猫アイコンが出ること、Dock に出ないこと、クリックでポップオーバーに「Mewbell」と Quit が出ること、外側のクリックで閉じること、ライトとダークの両方でアイコンが見えること、Quit と ⌘Q で終了してアイコンが消えること
- [x] 6.4 二重起動しないことを手元で確かめた: 起動中に `open -n build/DerivedData/Build/Products/Debug/Mewbell.app` と `open -n build/Debug/Mewbell.app` を同時に実行しても、何も動いていない状態で同時に実行しても、`pgrep -fl 'MacOS/Mewbell$'` が 1 件になる

## 7. 別コンテキストでのレビュー

- [x] 7.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [x] 7.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 7.2 をやり直す。確認: 指摘の件数と対応結果を PR 本文の Test plan に書いた
