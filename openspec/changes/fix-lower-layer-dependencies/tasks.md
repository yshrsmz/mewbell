# Tasks

## 1. 下の層から上の層への型の参照を無くす

- [x] 1.1 `HostKind`（`init(host:)` と `displayName` を含む）を `Mewbell/Accounts/Account.swift` から `Mewbell/GitHubAPI/APIEndpoints.swift` の先頭へ移す。中身は変えず、`Account.hostKind` は `Accounts/` に残す（design.md D1）。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/APIEndpointsTests -only-testing:MewbellTests/AccountDiscoveryTests` が、テストを変えずに通ることを確かめる（「N tests in M suites」のスイート数も確かめる）。`git grep -n "HostKind" Mewbell/GitHubAPI` に `Accounts/` の型の参照が残っていないことも確かめる。
- [x] 1.2 `GitHubAPIClient.perform(_:endpoints:token:)` を消し、`AccountPoller+ThreadActions.swift` の `perform(_:)` で `ThreadAction` を `switch` して、`client.markThreadRead` と `client.markThreadDone` を呼び分ける（design.md D2）。`git grep -n "ThreadAction\b" Mewbell/GitHubAPI` が何も返さないこと（`ThreadActionResult` は残る）と、`-only-testing:MewbellTests/MarkReadPollingTests -only-testing:MewbellTests/DonePollingTests -only-testing:MewbellTests/MarkThreadReadTests -only-testing:MewbellTests/MarkThreadDoneTests` が、テストを変えずに通ることを確かめる。

## 2. `Shared/` を足し、ロガーの拡張を移す

- [x] 2.1 `Mewbell/Shared/` を作り、`git mv Mewbell/App/Logging.swift Mewbell/Shared/Logging.swift` で中身を変えずに移す（design.md D3）。`xcodebuild -list -project Mewbell.xcodeproj` でプロジェクトが開けることと、Debug のビルドが通ることを確かめる。取り込まれなければ `project.xcproj` を直し、もう一度確かめる。
- [x] 2.2 スキル `update-architecture-doc` の手順で `docs/architecture.md` を改める（design.md D3・D5・D6）。
  - A1: 最下段 `Shared/` と、置いてよいものの条件を足す。中間の層に `Diagnostics/` を足す。根拠に `fix-lower-layer-dependencies D1`〜`D5` を足す。
  - A11: 根拠のパスを `Mewbell/Shared/Logging.swift` に直す。
  - 「既知の逸脱」から A1 の `HostKind`・`ThreadAction`・`Logger(category:)` の 3 行を消す（`NotificationStore` の行は 3.1 で消す）。
  - 確認: `grep -rnw 'A1' CLAUDE.md .claude openspec/specs openspec/config.yaml .swiftlint.yml docs` で引いている箇所と食い違わないこと、`bash scripts/check-architecture.sh` と `bash scripts/tests/check-architecture-test.sh` が通ること。
- [x] 2.3 CLAUDE.md のリポジトリ構成の図で、`Accounts/` の説明から `HostKind` を外し、`Shared/` の行（ロガーなど、どの層からも使う小さな道具）を足す（design.md D6）。`git grep -n "App/Logging\|GitHubAPIClient.perform\|client.perform" -- ':!openspec/changes/archive'` が何も返さないことを確かめる。

## 3. `NotificationStore` から AppKit を外す

- [x] 3.1 `NotificationStore.live(...)` に既定値の無い `openURL: @escaping @MainActor (URL) -> Void` を足し、`AppDelegate` から `{ NSWorkspace.shared.open($0) }` を渡す。`NotificationStore.swift` の `import AppKit` を消し、`.swiftlint.yml` の `ui_frameworks_outside_ui` の `excluded` から `Mewbell/Polling/NotificationStore\.swift` を消す。`docs/architecture.md` の「既知の逸脱」から `NotificationStore` の行を消す（design.md D4・D6）。確認: `bash scripts/lint.sh` が通ること、`-only-testing:MewbellTests/NotificationStoreActionTests` がテストを変えずに通ること、`bash scripts/check-architecture.sh` が通ること。

## 4. 確認

- [x] 4.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh`、`bash scripts/tests/check-architecture-test.sh`、`pnpm exec openspec validate --all --strict` を通す。
- [ ] 4.2 `bash scripts/run.sh` で起動し、手元で今までどおり動くことを確かめる。
  - 通知の一覧が取れること（`github.com` が先頭に並ぶこと）。
  - スレッドを既読と Done にでき、一覧から外れること。
  - スレッドをクリックするとブラウザで開くこと。
  - 設定の Diagnostics に Host kind が出ること。
  - ログ（`/usr/bin/log show --info --predicate 'subsystem == "com.codingfeline.mewbell"'`）が今までのカテゴリで出ること。

## 5. レビュー

- [ ] 5.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 5.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 5.3 ロジックの変更を含む修正が多ければ、5.2 を新しいサブエージェントでもう一度実行する。
