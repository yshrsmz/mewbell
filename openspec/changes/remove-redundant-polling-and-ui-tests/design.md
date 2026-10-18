# Design

## Context

テストは Swift Testing で書いている。ネットワークは `HTTPTransport` を `FakeHTTPTransport` に、トークンは `FakeTokenProvider` に、待ちは `ManualSleeper` に、通知センターは `UserNotificationCentering` を `FakeUserNotificationCenter` に差し替えている（A5）。

候補は、実装と `openspec/specs/` を読ませた別コンテキストのサブエージェントで洗い出した。そのうえで、もう一度別のサブエージェント 2 つ（Polling と、store・通知・UI）に、候補ごとに実物と突き合わせさせた。突き合わせでは、代わりに拾うとされたテストの `#expect` の中身まで読ませ、次の 4 点を判定させた。

- 代わりのテストが T2 の正本か
- 削る引数が攻撃の形ごとの引数ではないか（T4 の例外）
- 表の 1 行ずつが別の値との対応ではないか（T3）
- 境界の片側ではないか（T4）

行番号はずれるので、対象はテストの名前で書く。

## Goals / Non-Goals

**Goals:**

- `docs/testing.md` の T1・T2・T3・T4 に当たるテスト（確信度が高・中のもの）を、削除・統合・縮小する。
- 消すテストにしか無い確認は、残すテストへ移す。
- 本物と食い違う fake（`FakeUserNotificationCenter.removeDelivered`）を直す（T5）。
- 突き合わせで見つかった確認の穴のうち、ユーザーと決めた 2 つを埋める（D4）。

**Non-Goals:**

- remove-redundant-api-and-account-tests が触れた側のテスト。
- 確信度が低の候補。理由は D3 に書く。
- `docs/testing.md` の「既知の逸脱」のテストの待ち方を直すこと。`SubprocessRunnerTests` の孫プロセスも扱わない。
- `ThreadPresentationTests.swift` に Polling と GitHubAPI の層のスイートが入っている置き場所の問題。ファイルは動かさない。
- 本体のコードの変更。

## Decisions

### D1. 判断の基準と正本（`docs/testing.md` の T1・T2・T8、`docs/architecture.md` の A7）

削るかどうかは T1 で決める。2 つのテストが同じ不具合を拾うときは、T8 の順（速い単体テスト、仕様を直接表すテスト、T2 の正本）で残す側を選ぶ。値型や純粋な関数に切り出した判断（A7）は、その型のテストが正本になる。この change での正本は次のとおり。

| 判断 | 正本 |
|---|---|
| ポーリングの間隔の境界 | `FeedDiagnosticsTests.derivesThePollInterval` |
| 一覧の重ね方 | `ThreadListMergeTests.replacesTheSameIDAddsNewOnesAndKeepsTheRest` |
| 条件付きの `200` で重ね、条件なしの `200` で置き換えること | `ConditionalFetchTests.mergesTheThreadsIntoTheCurrentList`、`UnconditionalFetchTests.refetchesWithoutIfModifiedSinceEveryFiveMinutes` |
| 取得の失敗の種類 | `FeedDiagnosticsTests.classifiesFetchFailures` と `classifiesFetchResults` |
| まとめての操作の 1 秒の間隔 | `GroupActionPollingTests.waitsOneSecondAfterEachResultBeforeTheNextRequest` |
| 詳細を取る対象の選び方 | `ThreadDetailsCacheTests.picksPendingThreadsNewestFirst` |
| store から notifier への新着と取り下げ | `NotificationStoreNewThreadsTests` |
| notifier から通知センターへの取り下げ | `SystemNotifierTests.retractsThreadsMarkedDoneTogetherInOneCall` |
| リポジトリの並べ方 | `RepositoryGroupTests.ordersRepositoriesAndThreadsByTheNewestUpdate` |
| `subject.url` のオリジンとリポジトリの検査（private の `subjectPath`） | `ThreadWebURLTests.fallsBackToTheRepositoryPage` |
| リリースのタグの検証 | `ReleaseTagTests.rejectsTags`（触れない） |
| スレッド ID の境界（20 桁と 21 桁） | `ThreadIDTests.accepts` と `rejects` |
| ホスト名の検証 | `GhIdentifierTests.rejectsInvalidHosts`、`APIEndpointsTests.rejectsAnInvalidHost` |
| `FeedPhase.showsThreads` | `AccountDisclosureTests` |
| `FeedPhase.isStopped` | `TokenStateIconTests.showsTheState` |

### D2. 削除・統合・縮小するテスト

Polling:

| テスト | 操作 | T | 代わりに残るもの |
|---|---|---|---|
| `ThreadListMergeTests.keepsTheCurrentListWhenNothingIsFetched`、`returnsTheFetchedThreadsWhenTheListIsEmpty` | 削除 | T1・T4 | `merge` は分岐の無い 1 式。`replacesTheSameIDAddsNewOnesAndKeepsTheRest` |
| `PollScheduleTests.waitsForThePollInterval` | 削除 | T2 | `derivesThePollInterval`（同じ `PollSchedule.afterSuccess` を通る。120・60・nil・30） |
| `AccountPollerTests.sendsIfModifiedSinceFromTheSecondFetch` | 削除 | T2 | `refetchesWithoutIfModifiedSinceEveryFiveMinutes` の `[nil, "LM-1"]`、`waitsWithoutSendingWhenThereIsNoToken`、`MarkAllReadPollingTests.clearsTheListAndSendsThePut` |
| `AccountPollerTests.backsOffAndKeepsTheThreadsWhileFailing` と `backsOffASecondaryRateLimitWithoutAWait` | パラメタライズで 2→1。引数ごとに待ちの列、件数、`.retrying(…, rateLimited:)` の完全一致、成功の後に 60 秒へ戻ることを残す。`lastFetchFailure?.kind == .rateLimited` は二次レート制限の引数に残す | T4 | 統合先 |
| `ConditionalFetchTests.replacesTheListWithAnUnconditional200` | 削除 | T2 | `refetchesWithoutIfModifiedSinceEveryFiveMinutes`、`doesNotCountAConditional200AsAFullFetch`、`RefreshNowTests.wakesTheWaitAndFetchesWithoutIfModifiedSince` |
| `ConditionalFetchTests.keepsThreadsMarkedAllReadOutOfTheMergedList` | 削除。2 回目の取得が条件付きであること（`ifModifiedSince == [nil, "LM-1"]`）の確認を `MarkAllReadPollingTests.keepsTheThreadsOutOfAFetchThatEndsWhileThePutIsInFlight` に移す | T2 | 移し先 |
| `ConditionalFetchTests.keepsAThreadBeingReadOutOfTheMergedList` の `fetchedAgain: false` | 引数 2→1（`true` を残す） | T1 | `false` では隠す処理が無くても通る |
| `NotificationStoreConditionalFetchTests`（スイート） | 削除 | T2 | store は条件付きかどうかを知らない。`mergesTheThreadsIntoTheCurrentList`、`NotificationStoreNewThreadsTests.reportsNewThreadsAndGoneOnes` |
| `RefreshNowTests.doesNotHastenARateLimitedWait` と `doesNotHastenASecondaryRateLimitWithoutAWait` | パラメタライズで 2→1。引数ごとにリクエストの数と待ちの列を残し、次の取得が条件なしであることも残す | T4 | 統合先 |
| `ParticipatingPollerTests`（スイート） | 削除 | T2 | `NotificationStoreSettingsTests.restartsWithTheNewParticipatingSetting` の `participating=true` のクエリの確認、`GitHubAPIClientTests.buildsTheRequest`、`APIEndpointsTests.derivesBaseURLs` |
| `NotificationStoreSettingsTests.restartingDropsTheNoticeAndTheDiagnostics` | 削除 | T2・T5 | `restartsWithTheNewParticipatingSetting` の `== .loading` の完全一致、`dropsLateUpdatesFromTheStoppedPoller` |
| `ActionFailurePollingTests.recordsAReadThatWasNotSentForLackOfAToken` | 削除 | T4 | `GroupActionPollingTests.sendsNothingWithoutAToken` |
| `ActionFailurePollingTests.doesNotRecordSuccesses` | 削除。`MarkReadPollingTests.removesTheThreadAndSendsTheRequest` と `MarkAllReadPollingTests.clearsTheListAndSendsThePut` に、操作の直後（取得を進める前）の `actionFailure == nil` と `diagnostics.lastActionFailure == nil` を足す | T4 | 足し先 |
| `MarkReadPollingTests.bringsTheThreadBackWhenTheRequestFailed` | 削除 | T4 | `GroupActionPollingTests.stopsSendingAfterAnAuthErrorOrARateLimit`（Done）、`ThreadDetailsPollingTests.keepsDetailsOfThreadsHiddenForAWhile`（既読） |
| `MarkReadPollingTests.removesTheThreadAndSendsTheRequest` の URL の確認、`MarkAllReadPollingTests.clearsTheListAndSendsThePut` の URL と `Authorization` の確認 | URL の確認を、送るメソッドだけの確認にする。`removesTheThreadAndSendsTheRequest` の `Authorization` の 1 行と、`last_read_at` の確認は残す | T2 | API の層の `buildsThePatchRequest`・`buildsTheDeleteRequest`・`buildsThePutRequest`、`NotificationStoreActionTests` の DELETE の完全な URL |
| `GroupActionPollingTests.stopsSendingWhenThePollerIsStoppedMidway` | 削除。`diagnostics.lastActionFailure == nil` の確認を `sendsNoMoreAfterTheWaitWhenThePollerIsStoppedDuringIt` に移す | T4 | 移し先（確認を待ちの前に移す並べ替えまで拾う） |
| `GroupActionPollingTests.stopsSendingWhenTheTokenIsDiscardedMidway` | 削除 | T4 | `sendsNoMoreAfterTheWaitWhenTheTokenIsDiscardedDuringIt` |
| `GroupActionPollingTests.doesNotWaitForASingleThread` | 削除 | T4 | `waitsOneSecondAfterEachResultBeforeTheNextRequest`（1 件目の前に待たない、最後の後に待たない） |
| `ThreadDetailsPollingTests+Release.swift`（`fetchesTheTagOfNewReleasesBeforePublishing`、`tagsTheFirstListAfterPublishing`）と `+Actions.swift`（`findsTheRunOfNewApprovalsBeforePublishing`） | ファイルごと削除 | T2 | 流れは `fetchesNewThreadsBeforePublishing` と `publishesTheFirstListWithoutWaiting`（ポーラーは種類で分岐しない）、種類ごとの対象は `ThreadDetailsSubjectTests.readsTheReleaseID` と `searchesTheRunOfActionsThreads`、リクエストは `ThreadDetailsRequestTests+Release.fetchesTheTag` と `+Actions.takesTheOnlyWaitingRunTheUserCanApprove`、探し直さないことは `doesNotRefetchUnchangedThreads` |
| `ThreadDetailsPollingTests.stopsWaitingAtTheTimeLimit` | 削除（`PollerFixture` の、使われなくなる `detailsTimeout` の引数も消す） | T2・T6 | `ThreadDetailsFetcherTests.reportsTimedOutFetchesAsFailures`、`doesNotRetryAPrefetchFailureInTheSameCycle`。実時間の 100ms の待ちが無くなる |
| `ThreadDetailsPollingTests.publishesTheFirstListWithoutWaiting` の `detailsRequests == 24` | 1 行削除 | T3 | 1 件に 2 回というクライアントの手順の写し。同じテストの `allSatisfy { $0.details == … }`、`doesNotRefetchUnchangedThreads` |
| `ThreadDetailsCacheTests.picksReleasesWithAnID` | 削除（テストの `thread` の、使われなくなる `kind` と `releaseID` の引数も消す） | T2 | `picksPendingThreadsNewestFirst`（キャッシュは `detailsSubject != nil` しか見ない） |
| `ThreadDetailsCacheTests.pausesUntilTheRateLimitEnds` | 削除。`pausesAtLeastAMinuteOnRateLimits` に `retryAt` が勝つ側（`now + 600`）の引数を足す | T4 | 足し先（1 分の下限と `retryAt` の境界の両側） |

store・通知:

| テスト | 操作 | T | 代わりに残るもの |
|---|---|---|---|
| `NotificationStoreRepositoriesTests.groupsTheThreadsOfAnArrivedFeed` | 削除 | T2 | `RepositoryGroupTests.ordersRepositoriesAndThreadsByTheNewestUpdate`、`forgetsTheGroupsOfADisabledAccount` |
| `NotificationStoreOpenTests.doesNothingWhenTheURLCannotBeBuilt` | 削除 | T1 | 検証済みのホストからは URL が必ず作れるので、本番が通らない経路。50ms の固定の待ちも無くなる |
| `NotificationStoreOpenTests.opensTheWebNotificationsPageWithoutMarkingAnythingRead`、`opensTheWebNotificationsPageForAccountsWithoutAPoller`、`doesNotOpenTheWebNotificationsPageForAnInvalidHost` | 3→1。ポーラーのあるアカウントと `.unavailable` のアカウントを 1 つの store で開き、一覧と未読数が変わらないこと、GET 以外を送らないことを確かめる | T1・T2 | `openWebNotifications` は `pollers` を見ない。GHES の URL は `APIEndpointsTests.derivesBaseURLs` と `ThreadWebURLTests.opensTheWebNotificationsPageOfTheHost` |
| `NotificationStoreOpenTests.dropsAPendingReadWhenTheAccountCannotBeUsed` の `.accounts([])` | 引数 2→1（`.unavailable` を残す） | T4 | `NotificationStoreSettingsTests.dropsPendingReadsOfADisabledAccount`（同じ「`active` に無い」の分岐） |
| `NotificationStoreActionTests.marksAThreadDoneWithoutOpeningIt` と `marksAThreadReadWithoutOpeningIt` | パラメタライズで 2→1。通知センターの確認を外し、一覧、未読数、開かないこと、送るメソッドと URL、もう一方のメソッドを送らないことを残す | T2・T4 | 取り下げは `NotificationStoreNewThreadsTests.ignoresAThreadThatCameBackUnchangedAfterLeavingTheList` と `SystemNotifierTests.retractsThreadsMarkedDoneTogetherInOneCall` |
| `NotificationStoreActionTests.marksTheThreadsOfARepositoryGroupDone` の通知センターの確認 | 確認を削る | T2 | `NotificationStoreNewThreadsTests.removesTheThreadsOfAGroupMarkedDoneTogether` |
| `NotificationStoreActionTests.marksAllThreadsOfOneAccountDoneNewestFirst` の間隔と通知センターの確認 | 確認を削る（新しい順は残す）。`actionSpacing` の注入は `{ _ in }` にして残す（記録する `spacings` は消す） | T2 | `waitsOneSecondAfterEachResultBeforeTheNextRequest`、`removesTheThreadsOfAGroupMarkedDoneTogether` |
| `NotificationStoreActionTests.marksAllThreadsOfOneAccountRead` の `waitUntil` の直後の `#expect` | 1 行削除 | T1 | 直前の `waitUntil` と同じ条件 |
| `NotificationStoreNewThreadsTests.staysQuietForTheBaseline` | 削除 | T4 | `staysQuietForTheFirstFetchAfterStoppingAll`（`stopAll` は追跡を最初に戻すだけで、同じ経路） |
| `NotificationStoreNewThreadsTests.removesAllThreadsMarkedDoneTogether` | 削除（`removesTheThreadsOfAGroupMarkedDoneTogether` を残す） | T4 | 残す側。markAllDone がすべての ID を渡すことは `marksAllThreadsOfOneAccountDoneNewestFirst` の DELETE |
| `NotificationStoreNewThreadsTests.treatsTheFirstFetchAfterARestartAsTheBaseline` | 削除 | T2 | `restartsWithTheNewParticipatingSetting` の `notifier.events.isEmpty` と `baselineSet`、`SystemNotifierTests.postsNothingForTheBaselineAndClearsStaleNotifications`（この組は、片方だけを消すと決めている） |
| `NotificationTrackerTests.postsNothingForTheBaseline` | 削除 | T4 | `postsNewAndAdvancedThreadsOnly` |
| `NotificationTrackerTests.startsOverAfterReset` | 削除 | T1 | 本番の `ThreadChangeDispatcher` は先に `hasBaseline` を見るので、`update` の「基準が無ければ基準にする」分岐を通らない。reset が効くことは `NotificationStoreNewThreadsTests.removesTheAccountWhenItStopsAndStartsOver` |
| `ThreadNotificationContentTests.opensTheWorkflowRun` | 削除（`opensTheReleaseOfTheTag` は、詳細の付いたスレッドを `ThreadWebURL.make` に渡す配線の代表として残す） | T2 | 中身の URL は `ThreadWebURL.make` をそのまま呼ぶ。URL は `ActionsThreadWebURLTests.opensTheRunOfActionsThreads` |
| `ThreadOpenRequestTests.fallsBackToTheRepositoryPageWithoutAURL` | `replacesAnUnsafeURLWithTheRepositoryPage` の引数を `String?` にして nil を足し、統合する | T4 | 統合先。`rejectsAnUnsafeURLWithAnInvalidRepository` は結果が違う（nil）ので残す |
| `SystemNotifierTests.doesNotRetractForNewThreadsAlone`、`doesNothingForNoThreads` | 削除（fake を直すことが前提。D5） | T5 | 直した fake では落ちようがない。post は `postsNewThreadsAndRetractsGoneOnes` |
| `SystemNotifierTests.retractsAThreadMarkedRead` | 削除 | T4 | `retractsThreadsMarkedDoneTogetherInOneCall`（2 件を 1 回で取り下げ、ほかが残る） |
| `UnreadBadgeTests.formats` | 6→4（`-1` と `1_000` を消し、`0`・`1`・`99`・`100` を残す） | T4 | 境界（0 と 1、99 と 100）の両側 |
| `MenuBarIconTests.widensWithTheBadge` | 縮小。「バッジがあれば猫だけより広い」を削り、「1 桁より 99+ が広い」を残す | T2 | `drawsAGreenCatAndALabelColoredBadge`（幅が広がらなければ件数の列の画素の確認で落ちる） |
| `SystemNotifierSettingsTests.skipsPostingForAnAccountWithNotificationsOff` と `postsAgainWhenTurnedBackOn` | 2→1。アカウントごとに判定し、途中で切り替わる closure にして、アカウントが渡ることと呼ぶたびに読み直すこと（オフの間の分をためない）の両方を残す | T4 | 統合先 |

UI:

| テスト | 操作 | T | 代わりに残るもの |
|---|---|---|---|
| `RepositoryGroupTests.returnsNoGroupsForNoThreads` | 削除 | T1 | 空の配列は `Dictionary(grouping:)` と `map`・`sorted` の保証 |
| `TokenStateIconTests.isReadyUnlessStopped` | `showsTheState` の表に nil・`.loading`・`.retrying` の 3 行を移して削除（`.loaded` は表にある） | T4 | 移し先。3 つは `isStopped` の分類を別々に間違えうる（T3） |
| `ThreadWebURLTests.opensTheReleasesPageForAnInvalidTag` | 4→1（`../../settings`） | T2 | `ReleaseTagTests.rejectsTags` |
| `ThreadWebURLTests.opensTheDiscussionsPage` | 6→3（他人のホスト、`pulls/42`、`discussions/abc`） | T2・T4 | nil と他のリポジトリは `fallsBackToTheRepositoryPage`、21 桁は `ThreadIDTests.rejects` |
| `ThreadDetailsSubjectTests.readsNoNumberFromOtherSubjects` | 5→2（他人のホスト、`commits/…`） | T2 | `fallsBackToTheRepositoryPage` |
| `ThreadDetailsSubjectTests.readsNoReleaseIDFromOtherSubjects` | 5→3（nil、他人のホスト、`releases/v1.0.0`） | T2 | `fallsBackToTheRepositoryPage`、21 桁は `ThreadIDTests.rejects`。nil の行は、`ThreadDetailsCacheTests.picksReleasesWithAnID` を消した後の種類ごとの nil の確認として残す |
| `ThreadIconTests.showsOnlyTheKindWithoutAState` | 3→1（`.pullRequest`） | T3・T4 | 同じ else を通り、名前は実装の表の写し |
| `ListExpansionTests.observesOnlyTheAccountThatChanged` | 削除（`ChangeFlag` と `import Observation` も） | T1 | 想定する後退が起きても落ちない。取り違えは `expandsOnlyTheAccountAndTheRepositoriesWithNewThreads` と `forgetsAccountsThatAreNoLongerShown` |
| `AccountDisclosureTests.collapsesWhileShowingThreads`、`doesNotCollapseWithoutThreadsShown`、`staysExpandedWhenNotStoredCollapsed` | 1 つの表にまとめて 9→7。true の側は 2 行（覚えていない／覚えている）、false の側は、ほかの条件を満たしたまま 1 つずつ外す 5 行（`unavailable`、phase が nil、`unauthorized`、`scopeInsufficient`、`loading`） | T4 | 統合先。spec が畳まない条件を 1 つずつ挙げているので 5 行にはしない（T3） |
| `MarkAllDoneLabelsTests.namesTheCount` | `confirmation` の確認だけにする | T3 | ほかの 5 つの文字列は spec で決まっていない |
| `RepositoryActionLabelsTests.namesTheRepositoryAndTheCount` | 文字列の完全一致をやめ、`confirmation` の完全一致と、ほかのすべての返り値が `octo/app` を含むことにする | T3 | spec が決めているのは「どのリポジトリへの操作かが分かる」こと |
| `EnabledStatusesTests.keepsNothingWithoutAccounts` | 3→1 | T4 | 同じ guard |
| `ActionFailureMessageTests.givesNoReasonForOtherFailures` | 削除 | T4 | `describesAFailedDoneWithoutTheStatusCode`（同じ `default`）、`asksToLogInAgainAfterAnUnauthorizedRead`（既読の文言） |

### D3. 採らなかった候補

- `ThreadListMergeTests` のファイルごとの削除: `ThreadListMerge.merge` は純粋な関数（A7）で、`replacesTheSameIDAddsNewOnesAndKeepsTheRest` が重ね方の正本になる。代わりとされた `ConditionalFetchTests` は上の層。
- `PollScheduleTests.waitsUntilTheRateLimitResets` の `1e300` の行の削除: 「`Int` に直してから丸める」並べ替えを拾うのはこの行だけ。D4 で `.nan` に差し替える。
- `FeedDiagnosticsTests` を `.network` と 422 だけにする縮小: `FailureKind` の init は値の対応表で、どの行も別々に間違えうる（T3）。代わりとされた各ポーラーのテストは上の層（T2）。
- `ThreadOpenRequestTests.rejectsAnUnsafeURLWithAnInvalidRepository` を `replacesAnUnsafeURLWithTheRepositoryPage` に統合すること: 結果が違う（nil とリポジトリのページ）。`replacesAnUnsafeURLWithTheRepositoryPage` の 5 つの引数は、security.md の「ブラウザで開く URL」の攻撃の形なので削らない（T4 の例外）。
- `MenuBarIconTests.widensWithTheBadge` の削除: 99+ が 1 桁より広いことは、ほかのテストが拾わない（spec の「100 件以上は 99+」）。
- `AccountDisclosureTests` の 9→5、`isReadyUnlessStopped` の 4→1: spec が条件を 1 つずつ挙げていて、どの値も別々に間違えうる（T3）。
- `NotificationStoreOpenTests.passesFeedChangesToTheNotifier`: remove-redundant-tests で残すと決めた理由が今も当てはまる。
- `ReleaseTagTests.rejectsTags` の 14→8: タグの検証の正本で、この change の縮小（`opensTheReleasesPageForAnInvalidTag`）がこれを当てにしている。
- 確信度が低の候補（`UnconditionalFetchTests` の `requested: false`、`ThreadActionPollingTests.aFailedEarlierPutDoesNotEndALaterOnesHiding`、store 側の再開の 2 本の統合、`NotificationStoreNewThreadsTests` の `removesTheAccountWhenItStopsAndStartsOver` の引数・`postsTheEventAndDoesNotRepostWhenDetailsArrive` の本文の完全一致・`NotificationStoreRetainedAccountsTests` の 2 本、`ThreadOpenRequestTests.rejectsInvalidIdentifiers` 8→5、`retractsTheAccountWhenItStopsOrIsRemoved` の後半、`describesTheImageForVoiceOver`、`opensTheDiscussionOfTheNumber` 3→1、`ListScrollerTests` の期待値、`DisclosureAnimationsTests` の 2 本、`MarkAllReadLabelsTests` の 2 行）: 削っても減る量が小さく、残す価値が少しある。`aFailedEarlierPutDoesNotEndALaterOnesHiding` は spec の要件を 1 本で守っている。

### D4. 整理の途中で見つかった確認の穴を埋める（T1・T2、ユーザーと決めた）

- **書き込みのトークンの取り違え**: ポーラーの層で書き込みの `Authorization` を確かめるのは `MarkReadPollingTests.removesTheThreadAndSendsTheRequest` の 1 行だけになる。この fixture は alice しか持たないので、拾えるのはトークンの付け忘れまでで、複数のアカウントで取り違える不具合（Gitify #2176、CLAUDE.md）は拾えない。2 つのアカウントが 1 つの `GitHubAPIClient` を共有してポーリングしている `NotificationStoreActionTests.marksAllThreadsOfOneAccountDoneNewestFirst` に、DELETE のすべてが alice のトークンで送られることの確認を足す。トークンを付けるのは `APIGateway.send` だけで、lint の `authorization_header_outside_gateway` が守っているが、どのアカウントのトークンを渡すかは呼び出し側が決める。
- **`X-RateLimit-Reset` が NaN のとき**: `PollScheduleTests.waitsUntilTheRateLimitResets` の `1e300` の行を `.nan` に差し替える。`isFinite` の分岐を外すと `Int(nan)` で落ちる不具合と、先に `Int` に直す不具合の両方を 1 行で拾う。`.infinity` は `min` で上限に収まるので、この分岐を拾わない。

### D5. fake を本物に合わせる（T5、A5）

本物の `LiveUserNotificationCenter.removeDelivered` は、空の配列では何もしない（`guard !identifiers.isEmpty`）。`FakeUserNotificationCenter.removeDelivered` は空の配列でも呼び出しを記録するので、本物では起きない違いを確かめるテスト（`doesNotRetractForNewThreadsAlone`、`doesNothingForNoThreads`）が書けてしまう。fake にも同じ guard を入れる。`removals` を見ているほかのテスト（`retractsThreadsMarkedDoneTogetherInOneCall`）は空でない呼び出しだけを見ているので、影響しない。

### スレッドと actor の境界・テストでの差し替え

本体の actor と `@MainActor` の境界（A2）は変えない。差し替えの仕組み（A5）も変えず、`FakeUserNotificationCenter` の振る舞いだけを本物に合わせる。統合したテストでも、fake で同期的に待たない（T6）。`NotificationStoreActionTests` の `actionSpacing` の注入は残し、本物の 1 秒の待ちを入れない。消すテストとファイルの名前は `docs/architecture.md`、`docs/testing.md`、CLAUDE.md、`.claude/`、`openspec/specs/` には書かれていない（grep で確かめた）。

## セキュリティ

本体のトークンの流れは変えない。トークンは `gh auth token` で取得し、`CredentialStore` の actor の中にだけ持つ。リクエストごとに `APIGateway.send` でアカウントの API ベースへ送り、アカウントを外すときと終了時に破棄する。

security.md の性質を確かめるテストは、この change の後も性質ごとに次が残る。攻撃の形ごとの引数（`ThreadOpenRequestTests.replacesAnUnsafeURLWithTheRepositoryPage`、`fallsBackToTheRepositoryPage`、`ReleaseTagTests`）は削らない。

| 性質 | 残るテスト |
|---|---|
| リクエストごとのトークン | `GitHubAPIClientTests.buildsTheRequest`（正本）。ポーラーの層では、取得について `refreshesTheTokenOnceAfter401` と `stopsWhenTheScopesAreInsufficientAndResumesLater`、書き込みについて `MarkReadPollingTests.removesTheThreadAndSendsTheRequest`。複数のアカウントでの取り違えは、D4 で足す `marksAllThreadsOfOneAccountDoneNewestFirst` の確認。詳細の取得の GET の `Authorization` は、`ThreadDetailsPollingTests+Release` の削除でポーラーの層から無くなるが、付けるのは `APIGateway.send` の 1 か所で、詳細の取得もトークンを引数で渡す |
| 捨てたトークン・無いトークンで送らない | `sendsNoMoreAfterTheWaitWhenTheTokenIsDiscardedDuringIt`、`GroupActionPollingTests.sendsNothingWithoutAToken`、`MarkAllReadPollingTests.neitherSendsNorClearsWithoutAToken`、`waitsWithoutSendingWhenThereIsNoToken`、`ThreadDetailsPollingTests.sendsNothingWithoutAToken`、`stopsAsUnauthorizedWhenStill401AfterRefreshing` |
| 止めたポーラー（無効化・削除・終了）は送らない | `sendsNoMoreAfterTheWaitWhenThePollerIsStoppedDuringIt`、`RefreshNowTests.doesNotResumeAfterStop`、`NotificationStoreSettingsTests.stopsADisabledAccount`、`ActionFailurePollingTests.neitherSendsNorRecordsWhileStopped` |
| ブラウザで開く URL は https で、アカウントの Web ホストと一致する | `ThreadWebURLTests.alwaysPointsAtTheAccountHostOverHTTPS`、`fallsBackToTheRepositoryPage`（全引数）、`escapesTheTagAsPathComponents`、`opensTheReleasesPageForAnInvalidTag`（`../../settings`）、`ActionsThreadWebURLTests.opensTheFilteredRunsWithoutARun` |
| 通知のクリックからの URL を検証し、だめならリポジトリのページで代用する | `ThreadOpenRequestTests.replacesAnUnsafeURLWithTheRepositoryPage`（5 つの攻撃の形と nil）、`rejectsAnUnsafeURLWithAnInvalidRepository`、`acceptsValidUserInfo` |
| ホスト名・ユーザー名・ID の検証 | `GhIdentifierTests.rejectsInvalidHosts`・`rejectsInvalidUsers`、`APIEndpointsTests.rejectsAnInvalidHost`、`ThreadOpenRequestTests.rejectsInvalidIdentifiers`、`ThreadIDTests.rejects`・`accepts`、`readsNoReleaseIDFromOtherSubjects` の `v1.0.0` |
| 通知の本文にトークンも API の URL も入れない | `ThreadNotificationContentTests.leaksNeitherTheTokenNorAPIURLs` |
| store が検証済みの URL だけを開く | `NotificationStoreOpenTests.opensAndMarksAThreadRead`、`keepsANotificationClickUntilThePollerStarts`、`NotificationStoreSettingsTests.dropsPendingReadsOfADisabledAccount` |

## Risks / Trade-offs

- [統合のときに、元のテストにしか無かった `#expect` を落とす] → T8 の手順に従い、移した・足した `#expect` は実装を一時的に壊して落ちることを確かめる。
- [`dropsPendingReadsOfADisabledAccount` は「PATCH を送らない」を、消す側にある短い後待ちなしで確かめている] → `NotificationStore` の active でないアカウントを除く filter を一時的に外して落ちるかを確かめる。落ちなければ、T6 の「起きないことを確かめるとき」に従って区切りまで待つ形にする。
- [`NotificationTracker.update` の「基準が無ければ基準にする」分岐を確かめるテストが無くなる] → 本番では通らない分岐。消すかどうかは本体の change で決める。
- [`PollIntervalInfo` が将来 `PollSchedule.afterSuccess` を使わなくなると、`afterSuccess` の単体の確認が無くなる] → そのときは `derivesThePollInterval` の正本を見直す。
- [確信度が中の候補に、見落としている固有の価値がある] → 削除した後の code-review で見てもらう。
