# Proposal

## Why

`docs/architecture.md` の A1 は「下の層（`GhCLI/`・`GitHubAPI/`）は中間と上の層の型を使わない」「SwiftUI と AppKit を import するのは `UI/` と `App/` だけ」と決めている。しかし今のコードには、これに合わない箇所が 4 つあり、「既知の逸脱」に載っている。

- `GitHubAPI/APIEndpoints.swift` が、`Accounts/` の `HostKind` を使っている。
- `GitHubAPI/GitHubAPIClient.swift` が、`Polling/` の `ThreadAction` を使っている。
- `GhCLI/` と `GitHubAPI/` が、`App/Logging.swift` の `Logger(category:)` を使っている。
- `Polling/NotificationStore.swift` が、`.live` の組み立てで `NSWorkspace` を使うためだけに AppKit を import している。lint の `ui_frameworks_outside_ui` は、このファイルを除外している。

逸脱が残っていると、新しい型を足すときに既存のコードを手本にして同じ向きの依存が増え、lint の除外も広がりやすい。4 件はどれも振る舞いを変えずに直せるので、まとめて直して原則とコードを一致させる。

## What Changes

- `HostKind` を `Accounts/Account.swift` から `GitHubAPI/APIEndpoints.swift` へ移す。ホスト種別は API ベース URL を導くための分類で、使う層のうち最も下は `GitHubAPI/` である。表示名の `displayName` は、使う `UI/` と `Diagnostics/` の共通の依存先の `Accounts/` に残す。
- `GitHubAPIClient.perform(_:endpoints:token:)` を消す。`AccountPoller.perform(_:)` が `ThreadAction` に応じて `markThreadRead` と `markThreadDone` を呼び分ける。`ThreadAction` は `Polling/` に残す。
- `Mewbell/Shared/` を新しく作り、`App/Logging.swift` を `Shared/Logging.swift` に移す。A1 に「どの層からも使ってよい最下段 `Shared/`」を足し、置いてよいものの条件を書く。
- `NotificationStore.live(...)` に `openURL` の引数を足し、`AppDelegate` から `NSWorkspace.shared.open` を渡す。`NotificationStore.swift` の `import AppKit` と、`.swiftlint.yml` の `ui_frameworks_outside_ui` からこのファイルの除外を消す。
- A1 の中間の層の一覧に、漏れていた `Diagnostics/` を足す。
- `docs/architecture.md` の「既知の逸脱」から A1 の 4 行を消し、A11 の根拠に書いたパスを新しい場所に直す。CLAUDE.md のリポジトリ構成の図も今の配置に合わせる。

アプリの振る舞いは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。型の置き場所と部品の組み立て方を変えるだけで、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。add-architecture-principles で「既知の逸脱」に載せた A1 の 4 件を直す。
- 変更するもの:
  - コード: `Mewbell/Accounts/Account.swift`、`Mewbell/GitHubAPI/APIEndpoints.swift`、`Mewbell/GitHubAPI/GitHubAPIClient.swift`、`Mewbell/Polling/AccountPoller+ThreadActions.swift`、`Mewbell/Polling/NotificationStore.swift`、`Mewbell/App/AppDelegate.swift`、`Mewbell/App/Logging.swift`（`Mewbell/Shared/Logging.swift` へ移す）
  - 設定と文書: `.swiftlint.yml`、`docs/architecture.md`（A1・A11・既知の逸脱）、`CLAUDE.md`（リポジトリ構成の図）
  - テストは、型の場所が変わるだけで中身は変えない想定
- プロジェクト: `project.xcproj` はフォルダの同期（`Mewbell` フォルダ）でソースを取り込んでいるので、`Shared/` を足しても編集は要らない想定。足した後に `xcodebuild` で開けてビルドできることを確かめる。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理:
  - トークン: 触れない。トークンは今までどおり actor のメモリにだけ持ち、永続化しない。既読・Done の送り方は、`GitHubAPIClient` の公開メソッドの選び方が変わるだけで、送り先・ヘッダー・トークンの付け方は変えない。
  - gh サブプロセス: 触れない（`GhCLI/` はロガーの拡張の置き場所が変わるだけ）。
  - ネットワーク: 触れない。`APIEndpoints` が API ベース URL を導く規則と、オリジンの検査は変えない。
  - URL を開く処理: 開く関数を `NotificationStore.live` の中で作るのをやめ、`AppDelegate` から渡す。`NotificationStore` の中で開く前に行う検査（`ThreadWebURL`）は変えない。
