# Tasks

## 1. 取り下げを集合で受け取る

- [ ] 1.1 `NotificationTracker.remove(_:for:)` を ID の集合を受け取る形にし、`ThreadChangeDispatcher.threadRemoved` を `threadsRemoved(_:for:)`（集合）に変える（design.md D1）。`NotificationStore.perform` は外したスレッドの ID の集合を 1 回だけ渡す。`ThreadNotifying` の口も `threadsRemoved(_ threadIDs: Set<String>, for:)` に変え、`RecordingNotifier`（`MewbellTests/SettingsPollingTests.swift`）は集合を 1 つの出来事（`threadsRemoved <account> <ID をソートして , でつないだもの>`）として記録する。`NotificationStoreNewThreadsTests` の既存の期待を新しい記録の形に直し、グループの Done（`markDone(_ group:in:)`）とすべて Done（`markAllDone(in:)`）で `threadsRemoved` が 1 回だけ、外したすべての ID を持って届くテストを足す。`xcodebuild ... test -only-testing:MewbellTests/NotificationStoreNewThreadsTests` が通り、スイート数が 1 であることを確かめる。
- [ ] 1.2 `SystemNotifier.threadsRemoved` を、受け取った ID の通知を 1 回の `enqueue` で `removeDelivered(identifiers:)` に渡す形にする。空の集合では何もしない（design.md D2）。`FakeUserNotificationCenter` に `removeDelivered(identifiers:)` の呼び出しを順に記録する値を足す。`SystemNotificationTests` の `retractsAThreadMarkedRead` を新しい口に直し、複数の ID を渡すと呼び出しが 1 回で、それらの通知だけが消えるテストと、空の集合では呼び出しが無いテストを足す。`xcodebuild ... test -only-testing:MewbellTests/SystemNotificationTests` が通り、スイート数を確かめる（スイートの型名はファイルの中で確かめる）。
- [ ] 1.3 `git grep -n "threadRemoved" Mewbell MewbellTests docs` で古い名前が残っていないことを確かめる（`docs/architecture.md` には載っていないことを確かめ済み）。

## 2. 確認

- [ ] 2.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [ ] 2.2 `bash scripts/run.sh` で起動し、手元で確かめる。macOS の通知が出ているスレッドを一覧から既読にすると、その通知が通知センターから消えること。通知が出ている複数のスレッドのあるリポジトリのグループを Done にすると、それらの通知がまとめて消え、ほかのリポジトリの通知は残ること。

## 3. レビュー

- [ ] 3.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 3.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 3.3 ロジックの変更を含む修正が多ければ、3.2 を新しいサブエージェントでもう一度実行する。
