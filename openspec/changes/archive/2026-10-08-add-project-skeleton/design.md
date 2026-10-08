# Design

## Context

リポジトリには CLAUDE.md・`openspec/`・OpenSpec CLI 用の `package.json` しかなく、Swift のコードも Xcode プロジェクトもない（動機は proposal.md の Why を参照）。満たすべき振る舞いは `specs/ui/spec.md` にある。

設計に効く制約:

- プロジェクトは Xcode 27.2 以降の JSON 形式（`project.xcproj`）にする（CLAUDE.md）。Apple の説明では、27.2 以降は新規プロジェクトの既定がこの形式で、既存プロジェクトは file inspector から切り替えられる。`.xcproj` のプロジェクトは 27.0 / 27.1 でも開けるが、生成と変換は 27.2 以降でしかできない
- 手元の Xcode は 27.0（27A266a）で、ライセンスに未同意、`xcode-select` は `/Library/Developer/CommandLineTools` を指している
- macOS の GitHub Actions ランナーは高価なので使わない。CI は ubuntu で動く範囲（lint と OpenSpec の検証）だけにする
- 依存ポリシー: ツールのバージョンは固定し、公開から 7 日以上たった版を使う。グローバルインストールはしない

## Goals / Non-Goals

**Goals:**

- `xcodebuild build` / `xcodebuild test` / lint を手元で同じコマンドで回せる。lint は CI（ubuntu）でも同じ引数で回す（手元は `scripts/lint.sh`、CI は Docker イメージ。swift-format のバージョンの違いは D5）
- M1 以降で `CLAUDE.md` の目標構成（`Mewbell/App/`, `Mewbell/GhCLI/` …）にファイルを足していけるディレクトリとグループ構成にする
- Swift 6 の strict concurrency を最初から有効にし、後から警告を潰す作業を発生させない

**Non-Goals:**

- アプリアイコン（`AppIcon`）の作り込み。M0 では SF Symbols で済ませる
- 署名・notarize・配布（M5）
- ログイン時起動、設定画面（M4）

## Decisions

### D1. `project.xcproj` は Xcode 27.2 のテンプレートから作り、設定は CLI で変える

Xcode 27.2 の macOS App テンプレート（SwiftUI / Swift Testing）でプロジェクトを作り、リポジトリに移す。その後のビルド設定の変更・ターゲットの削除は、Xcode 同梱の `xcrun xcodeproj`（`setting set` / `setting unset` / `target remove` / `group remove`）で行い、変更のたびに `xcrun xcprojformatter --update Mewbell.xcodeproj` で正規の形に整える。テンプレートとの差分が下の表の項目だけになっていることを `git diff --no-index` で確かめる。

- テンプレートが作る UI テストのターゲット、App Sandbox の設定、`ContentView.swift` は使わないので消す。`Assets.xcassets`（AppIcon / AccentColor）は残す
- テンプレートの警告設定（`CLANG_WARN_*` など）や `SWIFT_APPROACHABLE_CONCURRENCY=YES` はそのまま使う
- 代替案: Xcode 同梱の CLI だけで一から作る → 試したところビルドは通ったが、テンプレートが既定で入れる設定と同じになっている保証がない。採らない
- 代替案: XcodeGen / Tuist で生成する → 外部依存が増え、「`project.xcproj` を正本としてコミットする」方針とも合わない。採らない

主なビルド設定:

| 設定 | 値 |
| --- | --- |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.codingfeline.mewbell`（テストは `com.codingfeline.mewbell.tests`） |
| `MACOSX_DEPLOYMENT_TARGET` | `26.0` |
| `SWIFT_VERSION` | `6.0` |
| `SWIFT_STRICT_CONCURRENCY` | `complete` |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | 指定しない（テンプレートの `MainActor` を消し、`nonisolated` 既定に戻す。`@MainActor` は明示する方針のため） |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES`（テンプレートの既定を維持） |
| `ENABLE_APP_SANDBOX` | `NO`（entitlements ファイルも作らない） |
| `ENABLE_HARDENED_RUNTIME` | `YES` と設定する（緩める entitlement は付けない）。実際の値は Release が `YES`、Debug は `ENABLE_PREVIEWS=YES` のため Xcode が自動で `NO` にする |
| `INFOPLIST_KEY_LSUIElement` | `YES` |
| `GENERATE_INFOPLIST_FILE` | `YES`（Info.plist ファイルは置かない） |
| `CODE_SIGN_IDENTITY` | `-`（ad-hoc。M5 まで署名しない）。`CODE_SIGN_STYLE` は `Manual` |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` | Release だけ `NO`（Release に `get-task-allow` を入れず、デバッガからのアタッチを防ぐ） |
| `SWIFT_TREAT_WARNINGS_AS_ERRORS` | 設定しない（Debug・Release とも既定の `NO`）。push 前の最終確認で、Debug と Release の両方のビルドに `xcodebuild` の引数で `YES` を渡す（CI では xcodebuild を回さないため） |
| `INFOPLIST_KEY_CFBundleDisplayName` | `Mewbell` |
| `INFOPLIST_KEY_LSApplicationCategoryType` | `public.app-category.developer-tools` |
| `INFOPLIST_KEY_NSHumanReadableCopyright` | `Copyright © 2026 Yasuhiro Shimizu. MIT License.` |
| `MARKETING_VERSION` | `0.1.0`（v1 までは 0.x にする） |

### D2. UI は `MenuBarExtra(.window)` の 1 シーンだけ

`@main struct MewbellApp: App` に `MenuBarExtra("Mewbell", systemImage: "cat.fill")` を置き、`.menuBarExtraStyle(.window)` にする。中身の `MenuBarContentView` は「Mewbell」の `Text` と Quit の `Button` だけを持つ。Quit は `NSApplication.shared.terminate(nil)` を呼び、`.keyboardShortcut("q")` を付ける。

- アイコンはテンプレート画像として描画される SF Symbol（`cat.fill`）を使い、ライト／ダークの両方に追従させる
- 代替案: `.menu` スタイル → M2 以降で一覧を表示するため、最初から `.window` にしておく
- 代替案: AppKit の `NSStatusItem` + `NSPopover` → SwiftUI だけで足りる間は使わない（CLAUDE.md の「AppKit は必要箇所のみ」）
- `Settings` シーンは M4 で追加する。M0 では置かない

### D2a. 二重起動の防止

`MewbellApp.init()` で、`~/Library/Application Support/com.codingfeline.mewbell/instance.lock` にファイルロック（`flock(LOCK_EX | LOCK_NB)`）を取る。取れなければほかの Mewbell が動いているので、そのまま `exit` する。シーンを作る前に確かめるので、アイコンが一瞬出てから消えることもない。ロックはプロセスが終わるまで持ち続ける。

- ロックは OS がまとめて取得するので、同時に起動しても片方しか取れない。プロセスが終われば（クラッシュしても）ロックは自動で外れ、ロックファイルは次の起動で使い回すので後片付けも要らない
- ロックの取得と解放は `SingleInstanceLock` に切り出し、一時ディレクトリのロックファイルを使ってユニットテストする（`flock` はファイルを開いた単位で効くので、同じプロセスの中でも 2 つ目の取得が失敗することを確かめられる）
- ロックの結果は「取れた」「ほかが持っている」「エラー（ファイルを開けないなど）」の 3 つに分ける。エラーのときは終了せず、os_log に記録して起動を続ける（ロックファイルの置き場所が壊れているだけで、アプリが毎回黙って終了するのを避けるため。二重起動を防げない方がまだ被害が小さい）
- テストのホストや SwiftUI プレビューとして起動されたとき（環境変数 `XCTestConfigurationFilePath` がある、または `XCODE_RUNNING_FOR_PREVIEWS=1` のとき）はロックを取らない。起動中の Mewbell があってもテストやプレビューを動かせ、その間に普段使いの Mewbell を起動しても終了しないようにするため
- 先に動いている方を前面に出す処理はしない。`LSUIElement` のアプリを前面に出しても表示されるものがないため
- 代替案: `NSRunningApplication` で同じ Bundle ID のアプリを探し、起動時刻と PID で先後を決める → 最初はこの方式にしたが、起動時刻が取れないと PID の大小に頼ることになる。PID は一周すると小さい値に戻るので後から起動した方が残ることがあり、3 つ以上が同時に起動すると全部が終了することもあった。採らない
- 代替案: `LSMultipleInstancesProhibited` → 同じ `.app` を開き直す場合しか防げず、別の場所にあるコピー（`build/` と DerivedData の 2 か所や、配布後のコピー）は防げない。採らない
- M1 以降、二重起動するとポーリングと通知が重複するため、M0 のうちに入れておく

### D3. 並行性の境界

- M0 で動くのは SwiftUI のシーンと View、Quit の処理だけで、すべて main thread / `@MainActor` 上で動く。`App` と `View` は SwiftUI 側で `@MainActor` に隔離されているため、追加の注釈は要らない。Quit のハンドラも `@MainActor` 上から `NSApplication` を呼ぶ
- actor は M0 では作らない。ネットワークは M2 で `GitHubAPIClient` actor、ポーリングは M2 で `Poller` actor に閉じ込める予定（ここでは決めない）
- strict concurrency を `complete` にしておくことで、M1 以降で境界を越えるコードを書いたときにコンパイルエラーで気づけるようにする

### D4. テストでの差し替え

M0 にはネットワークも gh サブプロセスもないので、差し替える対象はない。`MewbellTests` には Swift Testing（`import Testing`）で、テストターゲットとスキームが正しく構成されていることを確かめるダミーテストを 1 つ置く。ほかに D2a の `SingleInstanceLock` のユニットテストを置く。

M1 以降の方針としてここに書いておく: gh の実行は `GhCommandRunning` のようなプロトコル、HTTP は `HTTPTransport` のようなプロトコルの裏に置き、テストではフェイク実装を注入する（実際の名前とシグネチャは各 change の design で決める）。

- 代替案: XCTest → 新規コードなので Swift Testing を使う。UI テストターゲットは M0 では作らない

### D5. lint / format ツールの入手方法

- **swift-format**: 手元では Xcode 27 に同梱されている `xcrun swift-format` を使う。CI（Linux）では Swift の公式 Docker イメージ `swift:6.3.2-noble`（digest で固定）に同梱の `swift-format` を `docker run` で使う
  - 手元（Swift 6.4）とバージョンがずれるのは、6.4 のイメージが公開から 7 日の下限を満たしていなかったため。両方で同じ結果になることを確かめた。ずれが出たら 6.4 のイメージに上げる
- **swiftlint**: 手元ではリポジトリ直下の `mise.toml` で `swiftlint = "0.65.1"`（2026-08-21 公開）に固定し、`mise.lock` でチェックサムも固定して `mise exec -- swiftlint` で呼ぶ。CI では同じ 0.65.1 の公式 Docker イメージ `ghcr.io/realm/swiftlint`（digest で固定）を `docker run` で使う
  - CI の swiftlint で mise を使わない理由: Linux 版の swiftlint は Swift ツールチェーンの SourceKit を必要とするため Swift のコンテナで動かす必要があるが、Swift のイメージには curl も wget もなく mise を取得できない。apt で curl を入れる方法は、パッケージのバージョンを固定できないので採らない
  - 代替案: Homebrew → バージョンを固定できない。採らない
  - 代替案: SwiftPM のビルドツールプラグイン（SwiftLintPlugins）→ プロジェクトに SwiftPM 依存が入り、プラグインの信頼確認がビルドのたびに必要になる。採らない
  - 代替案: GitHub Releases の `portable_swiftlint.zip` を SHA-256 を確かめてダウンロードするスクリプト → これでも要件は満たせるが、mise ならバージョン固定とチェックサム検証をまとめて任せられる
- **Node.js**（OpenSpec CLI 用）: `mise.toml` で `node = "26.9.0"` に固定する
- `swift-format` と `swiftlint` はルールが重なるので、整形（import の並びを含む）は `swift-format` に任せ、swiftlint では整形系のルール（`trailing_whitespace`、`opening_brace`、`sorted_imports` など）を無効にする
- 手元の呼び出しは `scripts/lint.sh` にまとめる（`swift-format lint --strict --recursive Mewbell MewbellTests` と `swiftlint lint --strict --quiet`）。CI は同じ引数で各イメージを呼ぶ。対象や引数を変えるときは `scripts/lint.sh` と `ci.yml` の両方を直す

### D6. CI

`.github/workflows/ci.yml` を 1 本置き、`pull_request` と `push`（main）で動かす。macOS ランナーは高価なので使わず、ubuntu で動く範囲だけを回す。

- `runs-on: ubuntu-24.04`
- ジョブの流れ: checkout → swift-format（`swift` イメージ）→ swiftlint（`ghcr.io/realm/swiftlint` イメージ）→ mise のセットアップ（Node だけ）→ `npm ci --ignore-scripts` → `npx openspec validate --all --strict`
- **xcodebuild のビルドとテストは CI では回さない**（SwiftUI / AppKit は Linux でビルドできない）。手元で `xcodebuild test` と Debug / Release のビルドを通してから push する。tasks.md の最終確認にも入れる
- Action はタグではなくコミット SHA で固定する（`actions/checkout` v7.0.1、`jdx/mise-action` v5.0.0）。mise 本体もバージョンと sha256 で固定する
- ワークフローに `permissions: contents: read` を明示し、checkout は `persist-credentials: false` にする。トリガーは `pull_request` と `push` だけにし、`pull_request_target` は使わない。シークレットは渡さない
- main への push では、実行中の CI をキャンセルしない（コミットごとの結果を残す）

### D7. ビルド出力の置き場所

起動するアプリの場所を DerivedData に依存させず `build/Debug/Mewbell.app` に固定するため、`scripts/build.sh` では `-derivedDataPath build/DerivedData` を渡し、ビルドが終わったら `build/Debug/Mewbell.app` にコピーする。`build/` は `.gitignore` に入れる。

`scripts/run.sh` は、ビルドした後に起動中の Mewbell を場所を問わず `pkill -x Mewbell` で終了させてから `build/Debug/Mewbell.app` を開く。二重起動の防止（D2a）があるため、普段使いの Mewbell が動いたままだと新しいビルドがすぐに終了し、古いビルドのまま確認してしまうのを避けるため。5 秒待っても終了しなければ、エラーで止まる。

## セキュリティ

M0 ではトークンを取得も保持も送信もしない。gh サブプロセスもネットワーク通信もないので、トークンの流れはまだない（取得は M1、送信は M2 で設計する）。それでも、後から変えると影響が大きい土台の設定はここで決めておく（`.claude/rules/security.md` の「アプリとビルドの設定」「依存とサプライチェーン」に対応）。

- Hardened Runtime を最初から有効にし、緩める entitlement を付けない（D1）。Debug のビルドだけは Xcode がプレビューのために自動で無効にし、`get-task-allow` も入る。配布物になる Release は有効で、`get-task-allow` も入れない。App Sandbox が無効な分、コード注入への耐性は Hardened Runtime で確保する
- Info.plist に ATS の例外を入れない。`GENERATE_INFOPLIST_FILE` で生成される内容に `NSAppTransportSecurity` が含まれないことを確かめる
- CI は読み取り権限だけで動かし、Action はコミット SHA で固定する（D6）
- アプリのランタイム依存は追加しない。開発ツール（swiftlint、OpenSpec CLI）はバージョンを固定し、`mise.lock` / `package-lock.json` をコミットする

## Risks / Trade-offs

- [CI でビルドとテストを回さない] → macOS 固有のビルドエラーやテストの失敗は CI では見つからない。push の前に手元で `xcodebuild test` と Release のビルドを通すことを tasks.md と PR の Test plan で確かめる。必要になったら、macOS ランナーを手動実行（`workflow_dispatch`）のジョブとして足す
- [Xcode 27.2 は 2026-10 時点で beta] → 手元は Xcode-beta.app で作業する。正式版が出たら入れ替える
- [手元の Xcode が 27.0] → 実装の最初のタスクで 27.2 に更新し、`xcode-select` の切り替えとライセンス同意をする（sudo が要るのでユーザーが行う）。27.0 のままでも `.xcproj` は開けるが、プロジェクトを作る作業は 27.2 でしかできない
- [`.xcproj` の形式はまだ新しく、ツールの対応が追いついていない] → `xcodebuild` が CLI で開けることを毎回確かめる（CLAUDE.md の約束どおり）。うまくいかない場合は直接編集をやめて Xcode の GUI で設定を変える
- [swift-format と swiftlint のルールが食い違う] → 整形は swift-format だけに任せ、swiftlint 側の整形ルールを切る（D5）
- [mise が手元にない開発者がいる] → v1 は作者のローカルビルドが前提なので許容する。README に `mise install` の手順を書く

## Migration Plan

新規作成なので移行はない。ロールバックが必要になったら、この change の PR を revert すればよい。

## Open Questions

- CI の swift-format を Swift 6.4 のイメージに上げるのは、M0 の後でよい（spec にも tasks にも影響しない）
