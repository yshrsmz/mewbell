# Tasks

## 1. 逸脱を直す

- [x] 1.1 `MewbellTests/Support/PollingFakes.swift` の `waitForPendingRefresh()` の条件を `await self.poller.refreshWaitsForNextFetch` にする。`Mewbell/Polling/AccountPoller.swift` の `pendingRefreshCount` と、`Mewbell/Polling/RefreshWaiters.swift` の `count` を消す（design.md D1）。`git grep -n "pendingRefreshCount\|refreshWaiters\.count" Mewbell MewbellTests` が何も返さないことを確かめる。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/RefreshNowTests -only-testing:MewbellTests/ThreadDetailsPollingTests` が通り、結果が 2 スイートであることを確かめる。
- [x] 1.2 `Mewbell/App/SingleInstance.swift` のロガーのカテゴリを `"App"` にする（design.md D2）。`git grep -n 'category: "SingleInstance"'` が何も返さないことを確かめる。
- [x] 1.3 スキル `update-architecture-doc` の手順で、`docs/architecture.md` の「既知の逸脱」から A10 と A11 の行を消す（design.md D3）。`bash scripts/check-architecture.sh` と `bash scripts/tests/check-architecture-test.sh` が通ることを確かめる。

## 2. 確認

- [x] 2.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [x] 2.2 `bash scripts/run.sh` で起動し、手元で確かめる。通知の一覧が取れること、再読み込みで取り直すことが今までどおりであること。`log stream --level info --predicate 'subsystem == "com.codingfeline.mewbell" && category == "App"'` を流しながら、起動中にもう 1 つ `open -n build/Debug/Mewbell.app` で起動し、後から起動した方が終了して `Another instance is running; exiting` が出ること（info のログは保存されないので、`log show` ではなく `log stream` で見る）。（起動後の一覧の取得、再読み込みのボタンでの `without If-Modified-Since` の取得、2 つ目の終了とカテゴリ `App` のログを確かめた）

## 3. レビュー

- [x] 3.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [x] 3.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [x] 3.3 ロジックの変更を含む修正が多ければ、3.2 を新しいサブエージェントでもう一度実行する。（直したのはテストのヘルパーの doc コメントと design.md だけで、ロジックの変更が無いので再実行しない）
