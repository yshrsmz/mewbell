# Tasks

## 1. 印を actor の状態にする

- [x] 1.1 `AccountPoller.swift` の `unconditionalRequested` を `Atomic(false)` から actor の `var unconditionalRequested = false` にし、`hidden`・`readThroughs` と同じ状態の並びに移す。コメントに「取得を早めはしない」を移す。`requestUnconditionalFetch()` を消し、`refreshNow()` では `unconditionalRequested = true` と書く。`fetch(with:)` の `exchange` を、`await` を挟まない `let requested = unconditionalRequested` と `unconditionalRequested = false` の 2 行にし、取り終えられなかったときの `store` も代入にする（design.md D1）。`git grep -n "requestUnconditionalFetch\|unconditionalRequested\.\(store\|exchange\|load\)" Mewbell MewbellTests` が何も返さないことを確かめる。
- [x] 1.2 `AccountPoller+ThreadActions.swift` の `perform(_:)` と `markAllRead(through:)` の `store` を `unconditionalRequested = true` にし、`import Synchronization` を消す。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/UnconditionalFetchTests -only-testing:MewbellTests/RefreshNowTests -only-testing:MewbellTests/MarkReadPollingTests -only-testing:MewbellTests/DonePollingTests -only-testing:MewbellTests/MarkAllReadPollingTests` がテストを変えずに通ることを確かめる。
- [x] 1.3 スキル `update-architecture-doc` の手順で `docs/architecture.md` の A2 を改める。`Atomic` の名前を外し、外から触る状態は `Synchronization` の型で、中だけで触る状態は actor の `var` で持つと書き、根拠に `remove-poller-flag-atomic D1` を足す（design.md D2）。`grep -rnw 'A2' CLAUDE.md .claude openspec .swiftlint.yml docs` で引いている箇所と食い違わないこと、`bash scripts/check-architecture.sh` と `bash scripts/tests/check-architecture-test.sh` が通ることを確かめる。

## 2. 確認

- [x] 2.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [x] 2.2 `bash scripts/run.sh` で起動し、手元で確かめる。通知の一覧が取れること、再読み込みで取り直すこと、既読にしたスレッドが一覧から外れることが今までどおりであること（再読み込みと既読の後の取得が `If-Modified-Since` なしになることは、ログの `without If-Modified-Since` で確かめる）。

## 3. レビュー

- [x] 3.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [x] 3.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [x] 3.3 ロジックの変更を含む修正が多ければ、3.2 を新しいサブエージェントでもう一度実行する。（直したのは文書とコメントだけで、ロジックの変更が無いので再実行しない）
