# Design

## Context

今、バージョンは 3 か所でそれぞれ Info.plist から読んでいる。

- About パネル: `StatusItemMenu.showAbout()` が `NSApp.orderFrontStandardAboutPanel(nil)` を呼び、AppKit が `CFBundleShortVersionString` と `CFBundleVersion` を出す
- Diagnostics: `SettingsView.appVersion` が `CFBundleShortVersionString` を読み、`CFBundleVersion` と違うときだけ `(build)` を添える
- `User-Agent`: `APIGateway.userAgent` が `Mewbell/<CFBundleShortVersionString>` を作る

バージョンは `project.xcproj` のプロジェクトの設定の `MARKETING_VERSION` 1 か所にだけ書き、`CURRENT_PROJECT_VERSION` は `$(MARKETING_VERSION)` を参照する。`ci.yml` は `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` の設定がそれぞれ 1 つだけ（構成ごとの上書き `[config=...]` も数える）であることを確かめ、`verify-app.sh` は Release の Info.plist の 2 つの値がタグと一致することを確かめる。Debug 構成では Swift の `DEBUG` の条件が有効になっている（`SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Debug]`）。

## Goals / Non-Goals

**Goals:**

- 3 か所が同じ「表示用のバージョン」を使い、Debug では `-dev` が付く
- Release の表示・`User-Agent`・Info.plist を変えない

**Non-Goals:**

- コミットのハッシュやビルドの日時を埋め込むこと（ビルドのスクリプトの段が要り、`ENABLE_USER_SCRIPT_SANDBOXING` とも絡む。区別するという目的には `-dev` で足りる）
- Debug ビルドのアプリ名・アイコン・バンドル ID を変えること

## Decisions

### D1. `-dev` はビルド設定ではなく、コードの `#if DEBUG` で付ける（A9、A13）

`Mewbell/Shared/AppVersion.swift` に、表示用のバージョンを返す小さな型を置く。

```swift
enum AppVersion {
    /// 表示・送信に使うバージョン。Debug ビルドでは `-dev` を付ける
    static let current = make(shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, isDebug: isDebugBuild)

    static func make(shortVersion: String?, isDebug: Bool) -> String
}
```

`isDebugBuild` は `#if DEBUG` で決める private な定数にする。`make` は純粋な関数にして、Debug と Release の両方の組み立てをユニットテストで確かめられるようにする（テストは Debug 構成で動くので、`current` だけでは Release の側を確かめられない）。`shortVersion` が読めないときの値は、今の `APIGateway` に合わせて `0` にする。

**代替案**: `MARKETING_VERSION[config=Debug]` や `CURRENT_PROJECT_VERSION[config=Debug]` で Info.plist の値を変える案は採らない。`ci.yml` の検査（設定は 1 つだけ）と release-please の印の前提を崩し、Info.plist の `CFBundleShortVersionString` に `X.Y.Z` 以外の形を入れることにもなる。独自のビルド設定（`MEWBELL_VERSION_SUFFIX`）を Info.plist の独自キーに流す案も、3 か所が読むのは結局コードなので、`#if DEBUG` より部品が増えるだけになる。

### D2. 置き場所は `Shared/`（A1）

使うのは `GitHubAPI/`（下の層）、`UI/`、`App/` で、アカウントなどの領域の型を知らない小さな道具なので、A1 の `Shared/` の条件に合う。`Foundation` の `Bundle` だけを使い、SwiftUI と AppKit は import しない。`docs/architecture.md` の A1 は `Shared/` に置くものの例に `Logger(category:)` を挙げているだけで、例を足す必要はない（新しい原則ではない）。

### D3. Diagnostics の `(build)` の添え書きをやめる（A9）

`CFBundleVersion` は `$(MARKETING_VERSION)` を参照していて、CI もそれを確かめているので、`CFBundleShortVersionString` と違うことは起きない（コマンドラインで `MARKETING_VERSION` を上書きしても両方が変わる）。添え書きを残すと、Debug で `0.5.0-dev` と `0.5.0` を比べて `0.5.0-dev (0.5.0)` になるのを避ける分岐が要る。使われない分岐なので消し、Diagnostics は `AppVersion.current` をそのまま出す。

### D4. About パネルにはオプションで渡す

`orderFrontStandardAboutPanel(options:)` に `.applicationVersion: AppVersion.current` を渡す。何も渡さないと AppKit は `CFBundleVersion` を括弧で添えるので、Debug では `0.5.0-dev (0.5.0)` のように出るおそれがある。括弧を出さない渡し方（`.version` に空の文字列を渡すか、`.applicationVersion` と同じ値を渡すか）は、手元で About パネルを開いて決める（tasks 2.2）。Release でも同じオプションを渡し、表示が今と同じ `0.5.0` であることを確かめる。

### actor と `@MainActor` の境界

`AppVersion.current` は `static let` の不変の `String` で、`Sendable` なのでどの actor からも読める。About パネルと Diagnostics は main actor から、`APIGateway` は呼び出し元の actor（`AccountPoller` など）から読む。

### テストでの差し替え

ネットワークと gh サブプロセスには触れないので、差し替えるものは無い。`make` の引数で Debug と Release を切り替えて確かめる。`User-Agent` は既存の `GitHubAPIClientTests` の `FakeHTTPTransport` で、Debug 構成のテストでは `Mewbell/<X.Y.Z>-dev` になることを確かめる。

## セキュリティ

- トークンの流れは変えない（取得・保持・送り先・破棄のどれにも触れない）
- `User-Agent` の値が変わるだけで、ヘッダーの組み立ての関所（`APIGateway.send`、A6）とオリジン検査は変えない。`-dev` は固定の文字列で、外から入る値を含まない
- gh サブプロセス、URL を開く処理、ビルドの設定（Hardened Runtime・entitlement・ATS）には触れない。Release の Info.plist も変えないので、`verify-app.sh` の検査はそのまま通る

## Risks / Trade-offs

- [About パネルの括弧の出方が macOS のバージョンで違う] → tasks 2.2 で手元の macOS 26 で確かめ、決めた渡し方をコメントに書く
- [`User-Agent` が Debug と Release で違う] → GitHub 側の挙動は `User-Agent` の値で変わらない。むしろ Debug のリクエストを見分けられる
