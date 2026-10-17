# Design

## Context

今、バージョンは 3 か所でそれぞれ Info.plist から読み、アプリ名は 2 か所に文字列で書いている。

- About パネル: `StatusItemMenu.showAbout()` が `NSApp.orderFrontStandardAboutPanel(nil)` を呼び、AppKit が `CFBundleShortVersionString` と `CFBundleVersion` を出す
- Diagnostics: `SettingsView.appVersion` が `CFBundleShortVersionString` を読み、`CFBundleVersion` と違うときだけ `(build)` を添えて `DiagnosticsReport` に渡す。`DiagnosticsReport` は最初の節の見出しを `"Mewbell"` と書いていて、コピーするテキストには `[Mewbell]` として入る
- `User-Agent`: `APIGateway.userAgent` が `Mewbell/<CFBundleShortVersionString>` を作る
- ポップオーバーの見出し: `MenuBarContentView` の `Text("Mewbell")`

バージョンは `project.xcproj` のプロジェクトの設定の `MARKETING_VERSION` 1 か所にだけ書き、`CURRENT_PROJECT_VERSION` は `$(MARKETING_VERSION)` を参照する。`ci.yml` は `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` の設定がそれぞれ 1 つだけ（構成ごとの上書き `[config=...]` も数える）であることを確かめ、`verify-app.sh` は Release の Info.plist の 2 つの値がタグと一致することを確かめる。Debug 構成では Swift の `DEBUG` の条件が有効になっている（`SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Debug]`）。

## Goals / Non-Goals

**Goals:**

- 表示用のアプリ名とバージョンを 1 か所で決め、Debug では `Mewbell (dev)` と `X.Y.Z-dev` にする
- Release の表示・`User-Agent`・Info.plist を変えない

**Non-Goals:**

- `CFBundleDisplayName` を変えること（About パネルのアプリ名、通知のバナー、システム設定の通知やログイン項目の一覧に出る名前は `Mewbell` のまま。ユーザーの判断で、アプリの画面の中だけにした）
- 文言の中の `Mewbell`（`Quit Mewbell`、案内の文、右クリックのメニュー、メニューバーのアイコンの読み上げ）を変えること。アプリを指す文で、見出しのようにどのビルドかを示す場所ではない
- コミットのハッシュやビルドの日時を埋め込むこと（ビルドのスクリプトの段が要り、`ENABLE_USER_SCRIPT_SANDBOXING` とも絡む。区別するという目的には印で足りる）
- Debug ビルドのアイコン・バンドル ID を変えること

## Decisions

### D1. 印はビルド設定ではなく、コードの `#if DEBUG` で付ける（A9、A13）

`Mewbell/Shared/AppInfo.swift` に、表示用のアプリ名とバージョンを持つ小さな型を置く。

```swift
enum AppInfo {
    private static let shortVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    #if DEBUG
        /// 画面に出すアプリ名
        static let name = "Mewbell (dev)"
        /// 表示・送信に使うバージョン
        static let version = "\(shortVersion)-dev"
    #else
        static let name = "Mewbell"
        static let version = shortVersion
    #endif
}
```

`#if DEBUG` で分ける `static let` だけを置き、組み立ての関数は置かない。Release の側をユニットテストで確かめるために `isDebug` を引数に取る純粋な関数を置く案もあったが、確かめる中身は文字列の選び分けだけで、削っても見逃す現実的な不具合が無い（A12）。本体から呼ばれない入口をテストのために足すことにもなる（A10）。Release の側は手元の Release ビルドで確かめる（tasks 3.2）。ユニットテストは、Debug 構成で動くテストで `name` と `version` に印が付いていることを確かめる 1 本だけにする。`shortVersion` が読めないときの値は、今の `APIGateway` に合わせて `0` にする（`SettingsView` は `?` にしていたが、`GENERATE_INFOPLIST_FILE` と `MARKETING_VERSION` があるので読めないことは起きない）。アプリ名は Info.plist から読まずに `Mewbell` と書く（今の 2 か所と同じ。`CFBundleDisplayName` を変えない以上、読む理由が無い）。

「ビルド構成の違いをコードの `#if DEBUG` で表す」ことは `docs/architecture.md` の原則には足さない。Debug のバンドル ID やアイコンのように、Info.plist やアセットそのものを変えるものはビルド設定で分けるのが正しく、いつも成り立つ決まりではないため。この change では、変えたいのがアプリが自分で出す文字列だけで、Info.plist を変えない（distribution の要件）からコードで分ける。

**代替案**: `MARKETING_VERSION[config=Debug]` や `CURRENT_PROJECT_VERSION[config=Debug]` で Info.plist の値を変える案は採らない。`ci.yml` の検査（設定は 1 つだけ）と release-please の印の前提を崩し、Info.plist の `CFBundleShortVersionString` に `X.Y.Z` 以外の形を入れることにもなる。`INFOPLIST_KEY_CFBundleDisplayName[config=Debug]` で名前を変える案は、範囲をアプリの画面の中だけにしたので採らない。独自のビルド設定を Info.plist の独自キーに流す案も、読むのは結局コードなので、`#if DEBUG` より部品が増えるだけになる。

### D2. 置き場所は `Shared/`（A1）

使うのは `GitHubAPI/`（下の層）、`Diagnostics/` の呼び出し元の `UI/`、`App/` で、アカウントなどの領域の型を知らない小さな道具なので、A1 の `Shared/` の条件に合う。`Foundation` の `Bundle` だけを使い、SwiftUI と AppKit は import しない。`docs/architecture.md` の A1 は `Shared/` に置くものの例に `Logger(category:)` を挙げているだけで、例を足す必要はない（新しい原則ではない）。

### D3. `DiagnosticsReport` は名前も引数で受け取る（A5、A7）

`DiagnosticsReport` は今 `appVersion` を引数で受け取り、`Bundle` を読まない純粋な値型になっている。同じ形に合わせて `appName` を引数に足し、最初の節の見出しにする。`SettingsView` が `AppInfo.name` と `AppInfo.version` を渡す。こうすると `DiagnosticsReportTests` は構成によらず決まった値で確かめられる。コピーするテキストの 1 行目の `Mewbell Diagnostics` は変えない（何のテキストかを示す題で、どのビルドかは次の節の見出しとバージョンで分かる）。

### D4. Diagnostics の `(build)` の添え書きをやめる（A9）

`CFBundleVersion` は `$(MARKETING_VERSION)` を参照していて、CI もそれを確かめているので、`CFBundleShortVersionString` と違うことは起きない（コマンドラインで `MARKETING_VERSION` を上書きしても両方が変わる）。添え書きを残すと、Debug で `0.5.0-dev` と `0.5.0` を比べて `0.5.0-dev (0.5.0)` になるのを避ける分岐が要る。使われない分岐なので消し、`SettingsView.appVersion` も消す。

### D5. About パネルにはオプションで渡す

`orderFrontStandardAboutPanel(options:)` に `.applicationVersion: AppInfo.version` を渡す。何も渡さないと AppKit は `CFBundleVersion` を括弧で添えるので、Debug では `0.5.0-dev (0.5.0)` のように出るおそれがある。括弧を出さない渡し方（`.version` に空の文字列を渡すか、`.applicationVersion` と同じ値を渡すか）は、手元で About パネルを開いて決める（tasks 2.3）。Release でも同じオプションを渡す。今の Release の About パネルが `0.5.0 (0.5.0)` のように括弧を出しているなら、この変更で括弧が消える（バージョンの値は同じ）。tasks 3.2 で main のビルドの表示と見比べて記録する。アプリ名（`.applicationName`）は渡さない（Non-Goals）。

### actor と `@MainActor` の境界

`AppInfo.name` と `AppInfo.version` は `static let` の不変の `String` で、`Sendable` なのでどの actor からも読める。ポップオーバー、About パネル、Diagnostics は main actor から、`APIGateway` は呼び出し元の actor（`AccountPoller` など）から読む。

### テストでの差し替え

ネットワークと gh サブプロセスには触れないので、差し替えるものは無い。`AppInfo` のテストは Debug 構成で動く前提で書き、そのことをテストのコメントに書く（スキームの Test 構成は Debug）。`User-Agent` は既存の `GitHubAPIClientTests` の `FakeHTTPTransport` で、`Mewbell/\(AppInfo.version)` になることを確かめる。

## セキュリティ

- トークンの流れは変えない（取得・保持・送り先・破棄のどれにも触れない）
- `User-Agent` の値が変わるだけで、ヘッダーの組み立ての関所（`APIGateway.send`、A6）とオリジン検査は変えない。`-dev` は固定の文字列で、外から入る値を含まない
- Diagnostics のコピーの伏せ字（`Redaction.redactTokens`）は、節の見出しを含むテキスト全体にこれまでどおりかかる
- gh サブプロセス、URL を開く処理、ビルドの設定（Hardened Runtime・entitlement・ATS）には触れない。Release の Info.plist も変えないので、`verify-app.sh` の検査はそのまま通る

## Risks / Trade-offs

- [About パネルの括弧の出方が macOS のバージョンで違う] → tasks 2.3 で手元の macOS 27.0.1 で確かめ、`.version` に空の文字列を渡すことにした（理由はコードのコメント）
- [About パネルの名前は `Mewbell` のままで、バージョンだけに印が付く] → ユーザーの判断で名前はアプリの画面の中だけにした。バージョンの `-dev` で見分けられる
- [`User-Agent` が Debug と Release で違う] → GitHub 側の挙動は `User-Agent` の値で変わらない。むしろ Debug のリクエストを見分けられる
