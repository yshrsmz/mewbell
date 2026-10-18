# Tasks

各グループでは `docs/testing.md` の T8 の手順に従う。

- 消すテストの `#expect` が、design.md の D2 の「代わりに残るもの」で拾えるか、移し先に移したかを確かめる。
- 移した・足した `#expect` は、実装を一時的に壊して落ちることを確かめてから戻す。
- グループの終わりに `xcodebuild test -only-testing:MewbellTests/<スイートの型名>` で触ったスイートを流し、結果のスイート数が渡した数と合うことを確かめる（ファイル名ではなくスイートの型名を渡す）。

## 1. Polling: 取得と間隔

- [ ] 1.1 `PollingTests.swift`: `waitsForThePollInterval` と `sendsIfModifiedSinceFromTheSecondFetch` を消し、backsOff の 2 本をパラメタライズする。`waitsUntilTheRateLimitResets` の `1e300` の行を `.nan` に差し替え、`isFinite` の分岐を外すと落ちることを確かめる（D4）。
- [ ] 1.2 `ThreadListMergeTests` の空配列の 2 本を消す（ファイルは残す）。
- [ ] 1.3 `ConditionalFetchTests.swift`: `replacesTheListWithAnUnconditional200`、`keepsThreadsMarkedAllReadOutOfTheMergedList`、`fetchedAgain: false` の引数、`NotificationStoreConditionalFetchTests` を消す。`ifModifiedSince == [nil, "LM-1"]` の確認を `MarkAllReadPollingTests.keepsTheThreadsOutOfAFetchThatEndsWhileThePutIsInFlight` に移す。
- [ ] 1.4 `RefreshNowTests` の rateLimited の 2 本をパラメタライズする。
- [ ] 1.5 `SettingsPollingTests.swift`: `ParticipatingPollerTests` と `restartingDropsTheNoticeAndTheDiagnostics` を消す。

## 2. Polling: 操作（security.md のリクエストごとのトークン・捨てたトークンで送らないことを含む）

- [ ] 2.1 `PollingDiagnosticsTests.swift` の `recordsAReadThatWasNotSentForLackOfAToken` と `doesNotRecordSuccesses` を消し、`actionFailure == nil` と `diagnostics.lastActionFailure == nil` を `MarkReadPollingTests.removesTheThreadAndSendsTheRequest` と `MarkAllReadPollingTests.clearsTheListAndSendsThePut` に足す。
- [ ] 2.2 `MarkReadPollingTests.bringsTheThreadBackWhenTheRequestFailed` を消す。`removesTheThreadAndSendsTheRequest` の URL の確認と、`clearsTheListAndSendsThePut` の URL と `Authorization` の確認を削る。`removesTheThreadAndSendsTheRequest` の `Authorization` と `last_read_at` の確認は残す。
- [ ] 2.3 `GroupActionPollingTests.swift`: `stopsSendingWhenThePollerIsStoppedMidway`、`stopsSendingWhenTheTokenIsDiscardedMidway`、`doesNotWaitForASingleThread` を消し、`diagnostics.lastActionFailure == nil` を `sendsNoMoreAfterTheWaitWhenThePollerIsStoppedDuringIt` に移す。

## 3. Polling: スレッドの詳細

- [ ] 3.1 `ThreadDetailsPollingTests+Release.swift` と `ThreadDetailsPollingTests+Actions.swift` を消す（`project.xcproj` はフォルダ参照なので編集は不要。ビルドで確かめる）。
- [ ] 3.2 `ThreadDetailsPollingTests.stopsWaitingAtTheTimeLimit` と、`publishesTheFirstListWithoutWaiting` の `detailsRequests == 24` を消す。
- [ ] 3.3 `ThreadDetailsCacheTests.picksReleasesWithAnID` を消す。`pausesAtLeastAMinuteOnRateLimits` に `retryAt: now + 600` の引数を足してから、`pausesUntilTheRateLimitEnds` を消す。

## 4. store と通知（security.md の通知のクリックからの URL の検証を含む）

- [ ] 4.1 `FakeUserNotificationCenter.removeDelivered` に、空の配列を無視する guard を入れる（D5）。その後に `SystemNotifierTests.doesNotRetractForNewThreadsAlone` と `doesNothingForNoThreads` を消す。`SystemNotifierTests.retractsAThreadMarkedRead` も消す。
- [ ] 4.2 `SystemNotificationTests.swift` のほかの候補を D2 のとおりに削除・統合・縮小する: `NotificationTrackerTests` の 2 本、`ThreadNotificationContentTests` の 2 本、`ThreadOpenRequestTests.fallsBackToTheRepositoryPageWithoutAURL` の統合、`UnreadBadgeTests.formats`、`MenuBarIconTests.widensWithTheBadge`。
- [ ] 4.3 `SystemNotifierSettingsTests` の 2 本を、アカウントごとに途中で切り替わる closure の 1 本にまとめる。
- [ ] 4.4 `NotificationStoreRepositoriesTests`、`NotificationStoreOpenTests`、`NotificationStoreNewThreadsTests` の候補を D2 のとおりにする。`.accounts([])` の引数を消した後、`NotificationStore` の active でないアカウントを除く filter を一時的に外して、`NotificationStoreSettingsTests.dropsPendingReadsOfADisabledAccount` が落ちることを確かめる。落ちなければ、区切りまで待つ形に直す（T6）。
- [ ] 4.5 `NotificationStoreActionTests` の候補を D2 のとおりにする（`actionSpacing` の注入は残す）。`marksAllThreadsOfOneAccountDoneNewestFirst` に、DELETE のすべてが alice のトークンで送られることの確認を足し（D4）、`perform` に渡すアカウントを取り違えると落ちることを確かめる。

## 5. UI

- [ ] 5.1 `ThreadPresentationTests.swift` の候補を D2 のとおりにする（`returnsNoGroupsForNoThreads`、`isReadyUnlessStopped`、`opensTheReleasesPageForAnInvalidTag`、`opensTheDiscussionsPage`、`readsNoNumberFromOtherSubjects`、`readsNoReleaseIDFromOtherSubjects`）。`ReleaseTagTests` には触れない。
- [ ] 5.2 `ThreadIconTests`、`ListExpansionTests`、`AccountDisclosureTests`、`EnabledStatusesTests`、`ActionFailureMessageTests` の候補を D2 のとおりにする。
- [ ] 5.3 `MarkAllDoneLabelsTests` と `RepositoryActionLabelsTests` を D2 のとおりにする。

## 6. 確認

- [ ] 6.1 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通り、テストの件数が減った分だけ減っていることを確かめる。`bash scripts/lint.sh`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルド、`pnpm exec openspec validate --all --strict` が通ることを確かめる。本体のコードは変えないので、手元での起動の確認は省く。

## 7. レビュー

- [ ] 7.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込む。
- [ ] 7.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
