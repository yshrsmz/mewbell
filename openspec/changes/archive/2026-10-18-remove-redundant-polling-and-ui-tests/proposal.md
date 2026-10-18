# Proposal

## Why

`docs/testing.md` の T1〜T8 に照らすと、余分なテストが約 1,100 行あった。GitHubAPI・gh・アカウント・設定・App・`scripts/tests` の側は remove-redundant-api-and-account-tests で整理した。この change では、残りの Polling・NotificationStore・通知・UI の側を整理する。

この側で多いのは次の 3 つ。

- 下の層の確認を上の層で繰り返している（T2）。ポーラーのテストが URL・`Authorization`・本文の形を API の層と同じ粒度で確かめ、store のテストがポーラーの 1 秒の間隔や通知センターの取り下げを確かめ直している
- 純粋な関数のテストとポーラー経由のテストが、同じ分岐を確かめている（`PollScheduleTests`、`ThreadDetailsCacheTests` の一部）
- 同じ分岐を通る引数を並べている（T4）

あわせて、本物と食い違う fake を 1 つ直し（T5）、整理の途中で見つかった確認の穴を 2 つ埋める。

## What Changes

- 次のテストを削除・統合・縮小する。対象の一覧と、それぞれの代わりに残るテストは design.md に書く。
  - Polling: `PollingTests`、`ConditionalFetchTests`、`ThreadListMergeTests`、`RefreshNowTests`、`SettingsPollingTests`、`PollingDiagnosticsTests`、`MarkReadPollingTests`、`ThreadActionPollingTests`、`GroupActionPollingTests`、`ThreadDetailsPollingTests`（本体）、`ThreadDetailsCacheTests`
  - store・通知: `NotificationStoreRepositoriesTests`、`NotificationStoreOpenTests`、`NotificationStoreActionTests`、`NotificationStoreNewThreadsTests`、`SystemNotificationTests`、`SystemNotifierSettingsTests`
  - UI: `ThreadPresentationTests`、`ThreadIconTests`、`ListExpansionTests`、`AccountDisclosureTests`、`MarkAllDoneLabelsTests`、`RepositoryActionLabelsTests`、`EnabledStatusesTests`、`ActionFailureMessageTests`
- `ThreadDetailsPollingTests+Release.swift` と `ThreadDetailsPollingTests+Actions.swift` を消す。
- 消すテストにしか無い確認は、残すテストへ移す（成功のときに失敗を記録しないこと、条件付きの取得であること、レート制限の `retryAt` が勝つ側など）。
- fake を 1 つ直す: `FakeUserNotificationCenter.removeDelivered` が、本物の `LiveUserNotificationCenter` と同じく空の配列を無視するようにする（T5）。
- 確認の穴を埋める（ユーザーと決めた）:
  - 複数のアカウントが 1 つの `GitHubAPIClient` を共有するときに、書き込みのリクエストにそのアカウントのトークンが付くことを、store のテストで確かめる（Gitify #2176 の取り違え）。
  - `X-RateLimit-Reset` が NaN のときに落ちないことを確かめる行を足す。
- 本体のコードは変えない。

削る量は約 600 行の見込み。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。テストだけの変更で、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。remove-redundant-api-and-account-tests の続きで、そちらが触れたファイルには触れない。
- 変更するもの: `MewbellTests/` の上記のファイルと、`MewbellTests/` の fake（`FakeUserNotificationCenter`）。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: 本体には触れない。ただし、これらを確かめるテスト（リクエストごとのトークン、捨てたトークンで送らないこと、ブラウザで開く URL の検査、通知のクリックからの URL の検証）を整理するので、security.md の性質ごとに残るテストを design.md に書く。
- トークンの永続化に関わる変更は無い。
