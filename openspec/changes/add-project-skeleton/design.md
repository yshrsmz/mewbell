# Design

## Context

リポジトリには CLAUDE.md・`openspec/`・OpenSpec CLI 用の `package.json` しかなく、Swift のコードも Xcode プロジェクトもない（動機は proposal.md の Why を参照）。満たすべき振る舞いは `specs/ui/spec.md` にある。

設計に効く制約:

- プロジェクトは Xcode 27.2 以降の JSON 形式（`project.xcproj`）にする（CLAUDE.md）。Apple の説明では、27.2 以降は新規プロジェクトの既定がこの形式で、既存プロジェクトは file inspector から切り替えられる。`.xcproj` のプロジェクトは 27.0 / 27.1 でも開けるが、生成と変換は 27.2 以降でしかできない
- 手元の Xcode は 27.0（27A266a）で、ライセンスに未同意、`xcode-select` は `/Library/Developer/CommandLineTools` を指している
- GitHub Actions では `runs-on: xcode-27` イメージに `/Applications/Xcode_27.2_beta.app`（27B5019j）が入っている。2026-09-28 時点で 27.2 はまだ beta
- 依存ポリシー: ツールのバージョンは固定し、公開から 7 日以上たった版を使う。グローバルインストールはしない

## Goals / Non-Goals

**Goals:**

- `xcodebuild build` / `xcodebuild test` / lint を手元と CI で同じコマンドで回せる
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
| `SWIFT_VERSION` | `6` |
| `SWIFT_STRICT_CONCURRENCY` | `complete` |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | 指定しない（テンプレートの `MainActor` を消し、`nonisolated` 既定に戻す。`@MainActor` は明示する方針のため） |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES`（テンプレートの既定を維持） |
| `ENABLE_APP_SANDBOX` | `NO`（entitlements ファイルも作らない） |
| `ENABLE_HARDENED_RUNTIME` | `YES`（緩める entitlement は付けない）。ただし Debug は `ENABLE_PREVIEWS=YES` のため Xcode が自動で `NO` にする。Release は `YES` |
| `INFOPLIST_KEY_LSUIElement` | `YES` |
| `GENERATE_INFOPLIST_FILE` | `YES`（Info.plist ファイルは置かない） |
| `CODE_SIGN_IDENTITY` | `-`（ad-hoc。M5 まで署名しない）。`CODE_SIGN_STYLE` は `Manual` |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` | Release だけ `NO`（Release に `get-task-allow` を入れず、デバッガからのアタッチを防ぐ） |
| `SWIFT_TREAT_WARNINGS_AS_ERRORS` | Debug は `NO`、CI では `xcodebuild` 引数で `YES` を渡す |

### D2. UI は `MenuBarExtra(.window)` の 1 シーンだけ

`@main struct MewbellApp: App` に `MenuBarExtra("Mewbell", systemImage: "cat.fill")` を置き、`.menuBarExtraStyle(.window)` にする。中身の `MenuBarContentView` は「Mewbell」の `Text` と Quit の `Button` だけを持つ。Quit は `NSApplication.shared.terminate(nil)` を呼び、`.keyboardShortcut("q")` を付ける。

- アイコンはテンプレート画像として描画される SF Symbol（`cat.fill`）を使い、ライト／ダークの両方に追従させる
- 代替案: `.menu` スタイル → M2 以降で一覧を表示するため、最初から `.window` にしておく
- 代替案: AppKit の `NSStatusItem` + `NSPopover` → SwiftUI だけで足りる間は使わない（CLAUDE.md の「AppKit は必要箇所のみ」）
- `Settings` シーンは M4 で追加する。M0 では置かない

### D3. 並行性の境界

- M0 で動くのは SwiftUI のシーンと View、Quit の処理だけで、すべて main thread / `@MainActor` 上で動く。`App` と `View` は SwiftUI 側で `@MainActor` に隔離されているため、追加の注釈は要らない。Quit のハンドラも `@MainActor` 上から `NSApplication` を呼ぶ
- actor は M0 では作らない。ネットワークは M2 で `GitHubAPIClient` actor、ポーリングは M2 で `Poller` actor に閉じ込める予定（ここでは決めない）
- strict concurrency を `complete` にしておくことで、M1 以降で境界を越えるコードを書いたときにコンパイルエラーで気づけるようにする

### D4. テストでの差し替え

M0 にはネットワークも gh サブプロセスもないので、差し替える対象はない。`MewbellTests` には Swift Testing（`import Testing`）のダミーテストを 1 つだけ置き、テストターゲットとスキームが正しく構成されていることだけを確かめる。

M1 以降の方針としてここに書いておく: gh の実行は `GhCommandRunning` のようなプロトコル、HTTP は `HTTPTransport` のようなプロトコルの裏に置き、テストではフェイク実装を注入する（実際の名前とシグネチャは各 change の design で決める）。

- 代替案: XCTest → 新規コードなので Swift Testing を使う。UI テストターゲットは M0 では作らない

### D5. lint / format ツールの入手方法

- **swift-format**: Xcode 27 に同梱されている `xcrun swift-format` を使う。Xcode のバージョンに固定されるので、別途ピン留めする必要がない
- **swiftlint**: リポジトリ直下の `mise.toml` で `swiftlint = "0.65.1"`（2026-08-21 公開）に固定し、`mise.lock` でチェックサムも固定する。手元も CI も `mise exec -- swiftlint` で呼ぶ
  - 代替案: Homebrew → バージョンを固定できない。採らない
  - 代替案: SwiftPM のビルドツールプラグイン（SwiftLintPlugins）→ プロジェクトに SwiftPM 依存が入り、プラグインの信頼確認がビルドのたびに必要になる。採らない
  - 代替案: GitHub Releases の `portable_swiftlint.zip` を SHA-256 を確かめてダウンロードするスクリプト → これでも要件は満たせるが、mise ならバージョン固定とチェックサム検証をまとめて任せられる
- `swift-format` と `swiftlint` はルールが重なるので、整形は `swift-format` に任せ、swiftlint では整形系のルール（`trailing_whitespace`、`opening_brace` など）を無効にする
- 呼び出しは `scripts/lint.sh` にまとめる（`swift-format lint --strict -r Mewbell MewbellTests` と `swiftlint lint --strict`）

### D6. CI

`.github/workflows/ci.yml` を 1 本置き、`pull_request` と `push`（main）で動かす。

- `runs-on: xcode-27`
- `sudo xcode-select -s /Applications/Xcode_27.2_beta.app` で Xcode を明示する。27.2 の正式版がイメージに入ったら `/Applications/Xcode_27.2.app` に変える
- ジョブの流れ: checkout → mise のセットアップ → `bash scripts/lint.sh` → `xcodebuild build` → `xcodebuild test`
- Action はタグではなくコミット SHA で固定する（`actions/checkout` v7.0.1、`jdx/mise-action` は公開から 7 日以上たった版）。SHA は実装時に確かめる
- 署名は `CODE_SIGNING_ALLOWED=NO` で無効にする
- ワークフローに `permissions: contents: read` を明示する。トリガーは `pull_request` と `push` だけにし、`pull_request_target` は使わない。シークレットは渡さない

### D7. ビルド出力の置き場所

CLAUDE.md の `open build/Debug/Mewbell.app` に合わせるため、`scripts/build.sh` では `-derivedDataPath build/DerivedData` を渡し、ビルドが終わったら `build/Debug/Mewbell.app` にコピーする。`build/` は `.gitignore` に入れる。

## セキュリティ

M0 ではトークンを取得も保持も送信もしない。gh サブプロセスもネットワーク通信もないので、トークンの流れはまだない（取得は M1、送信は M2 で設計する）。それでも、後から変えると影響が大きい土台の設定はここで決めておく（`.claude/rules/security.md` の「アプリとビルドの設定」「依存とサプライチェーン」に対応）。

- Hardened Runtime を最初から有効にし、緩める entitlement を付けない（D1）。App Sandbox が無効な分、コード注入への耐性は Hardened Runtime で確保する
- Info.plist に ATS の例外を入れない。`GENERATE_INFOPLIST_FILE` で生成される内容に `NSAppTransportSecurity` が含まれないことを確かめる
- CI は読み取り権限だけで動かし、Action はコミット SHA で固定する（D6）
- アプリのランタイム依存は追加しない。開発ツール（swiftlint、OpenSpec CLI）はバージョンを固定し、`mise.lock` / `package-lock.json` をコミットする

## Risks / Trade-offs

- [Xcode 27.2 は 2026-09 時点で CI では beta] → CI はまず `Xcode_27.2_beta.app` で動かし、正式版が入ったらパスを差し替える。beta によるビルド失敗は CI のログで切り分ける
- [手元の Xcode が 27.0] → 実装の最初のタスクで 27.2 に更新し、`xcode-select` の切り替えとライセンス同意をする（sudo が要るのでユーザーが行う）。27.0 のままでも `.xcproj` は開けるが、プロジェクトを作る作業は 27.2 でしかできない
- [`.xcproj` の形式はまだ新しく、ツールの対応が追いついていない] → `xcodebuild` が CLI で開けることを毎回確かめる（CLAUDE.md の約束どおり）。うまくいかない場合は直接編集をやめて Xcode の GUI で設定を変える
- [swift-format と swiftlint のルールが食い違う] → 整形は swift-format だけに任せ、swiftlint 側の整形ルールを切る（D5）
- [mise が手元にない開発者がいる] → v1 は作者のローカルビルドが前提なので許容する。README に `mise install` の手順を書く

## Migration Plan

新規作成なので移行はない。ロールバックが必要になったら、この change の PR を revert すればよい。

## Open Questions

- 27.2 の正式版が出た後に CI の `xcode-select` のパスを差し替えるのは、M0 の後でよい（spec にも tasks にも影響しない）
