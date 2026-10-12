# Tasks

各タスクで、変更したファイルのテストを `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/<Suite>` で通す。統合や書き換えで `#expect` を移したら、その `#expect` が落ちることを、実装を一時的に壊して確かめる（代表のものだけでよい）。

## 1. ポーリング

- [x] 1.1 `FeedDiagnosticsTests` を整理し、テストが通ることを確かめる。
  - `classifiesActionResults`、`newFieldsDefaultToEmpty`、`classifiesFetchResults` を削除する。
  - `classifiesFetchFailures` は、値を運ぶ 1 件と network の 1 件にする。
  - `derivesThePollInterval` に、境界の値（60 / nil / 30 / 120）を集める。
- [x] 1.2 `PollingDiagnosticsTests` を整理し、テストが通ることを確かめる。
  - `recordsTheIntervalAndTheNextFetch` は "120" の 1 件にする。
  - 次の 4 本は、それぞれ統合先へ必要な `#expect` を移してから消す。
    - `recordsTheScopesOfAScopeInsufficient403` → `PollingTests.stopsWhenA403SaysTheScopesAreInsufficient`
    - `announcesTheEarlierFetchAfterAReload` → `RefreshNowTests.waitsUntilTenSecondsAfterThePreviousFetch`
    - `dropsTheOldScopesWhenResuming` → `PollingTests.stopsWhenTheScopesAreInsufficientAndResumesLater`
    - `recordsAMarkAllReadThatWasNotSentForLackOfAToken` → `ThreadActionPollingTests.neitherSendsNorClearsWithoutAToken`
  - `clearsTheNoticeOnTheNextSuccessfulFetchButKeepsTheLastFailure`、`doesNotRecordAMarkAllReadBeforeTheFirstFetch`、`replacesTheNoticeWithTheLaterFailure` を削除する。
  - `clearsTheScheduleAndTruncationWhenStoppedButKeepsTheLastFailure` の、必ず通る `isTruncated == false` を消す。
- [x] 1.3 「止めた後は何も送らない」の 4 本を 1 本にまとめ、テストが通ることを確かめる。
  - 対象は `PollingDiagnosticsTests.doesNotRecordWhileStopped`、`MarkReadPollingTests.sendsNothingWhileStopped`、`ThreadActionPollingTests` の Done と MarkAll の `sendsNothingWhileStopped`。
  - まとめた 1 本では、read・done・markAllRead をすべて呼び、何も送らず、`actionFailure` も `lastActionFailure` も nil であることを確かめる。
- [x] 1.4 `MarkReadPollingTests` と `ThreadActionPollingTests` を整理し、テストが通ることを確かめる。
  - Read と Done の「スレッドを消して送る」「失敗したら戻す」を、`ThreadAction` の parameterized にまとめる。Authorization の `#expect` は外す。
  - `bringsTheThreadsBackWhenThePutFailed` を削除する。
  - `route(...)` の helper を 1 つにまとめる。
- [x] 1.5 `PollingTests` を整理し、テストが通ることを確かめる。
  - `stopsAsUnauthorizedWhenTheTokenCannotBeRefreshed`、`waitsForTheRateLimit`、`keepsLastModifiedWhenALaterPageFails` を削除する。
  - NotificationStoreTests の `keepsRunningPollersWhileTheTokenIsFetched` を削除する。
  - `Thread.sleep` を使う `ignoresUpdatesFromStoppedPollers` を削除する。
- [x] 1.6 `RefreshNowTests` と `ThreadDetailsPollingTests+Refresh` を整理し、テストが通ることを確かめる。
  - `RefreshNowTests.endsTheProgressWhenStopped` を削除する。
  - `waitForPendingRefresh` を `PollerFixture` に移し、2 か所の重複をなくす。
- [x] 1.7 `UnconditionalFetchTests` と `AccountPoller` を変え、テストとビルドが通ることを確かめる。
  - `requestedFetchIsUnconditionalButNotEarlier` を削除する。
  - `retriesWithoutIfModifiedSinceAfterAFailedUnconditionalFetch(requested: true)` は、`perform(.read)` で印を立てる形に書き換える。
  - そのうえで `AccountPoller.requestUnconditionalFetch()` を private にする。
- [x] 1.8 `SettingsPollingTests` を整理し、テストが通ることを確かめる。
  - `sendsParticipatingFalseByDefault` を削除する。
  - `followsTheNextLinkAsIs` は、ポーラーを使わない形で `GitHubAPIClientTests` に移す。移した後のテストは、次ページの URL を作り直したら落ちることを確かめる。
  - `keepsTheRateLimitWaitWhenRestarting` を `keepsTheRateLimitWaitWhenEnabledAgain` に吸収する。
- [x] 1.9 `ThreadDetailsPollingTests` を整理し、テストが通ることを確かめる。
  - `refetchesWhenTheUpdateAdvances` と `sendsOnlyTheAccountsToken` を削除する。
  - `stopsWaitingAtTheTimeLimit` は、次の回に取り直す後半を削る。

## 2. gh・アカウント

- [x] 2.1 次の 2 ファイルを整理し、テストが通ることを確かめる。
  - `GhCommandTests.buildsTheReloginCommandForTheHost` を削除する。
  - `AccountDisplayTests.swift` はファイルごと削除する。
- [x] 2.2 `CredentialStoreTests` を整理し、テストが通ることを確かめる。
  - `removesEverything`、`discardsOnlyTheAccountsThatAreGone`、`removesOneAccount` を削除する。
  - close の後に書き戻さないことを確かめる `ignoresNewTokensAfterClosing` は残す。
- [x] 2.3 `SubprocessRunnerTests` を整理し、テストが通ることを確かめる。
  - 統合と書き換え:
    - `timesOutAndStopsTheChild` を `childIsGoneAfterTheTimeout` に統合する。
    - stdout・stderr・終了コードの 2 本を 1 本にまとめる。
    - `passesOnlyTheGivenEnvironment` は、任意の 2 変数だけが渡ることを確かめる形に書き換える。
    - `setsTheOverriddenConfigDirectory` は、`GH_CONFIG_DIR` を置き換えることだけを確かめる形に縮める。
    - 伏せ字の 2 本を parameterized にまとめる。
  - `acceptsASingleLineAndTrimsIt` を削除する。
  - 書き換えた後も、伏せ字と環境変数の除去を確かめるテストが残っていることを確かめる。
- [x] 2.4 `HostsFileTests` を整理し、テストが通ることを確かめる。
  - `acceptsAnOwnedDirectory`、`loadReturnsNilWhenTheFileIsMissing`、`loadReadsAFile` を削除する。
  - `rejectsAWorldWritableDirectory` は、symlink のテストに寄せる。world-writable を拒否する確認は残す。
  - `ignoresTokensStoredUnderUsers` は、`readsTheMultiAccountFormat` の fixture に統合する。`String(reflecting:)` の確認は 1 つ残す。
- [x] 2.5 `GhLocatorTests` を整理し、テストが通ることを確かめる。
  - 次の 5 本を削除する。
    - `acceptsAnExecutableRegularFile`
    - `takesTheLastNonEmptyLine`
    - `searchesTheLoginShellOnlyOnce`
    - `reusesTheLoginShellResultWithoutSearchingAgain`
    - `concurrentCallersShareTheLoginShellResult`
  - `GhClientTests` は次のように整理する。
    - `runsVersionWithTheSanitizedEnvironment` を削除する。
    - `tokenIsNilWhenGhDoesNotGiveOne` は、終了コードが 0 以外・不正な出力・throw の 3 件にする。
    - `versionIsNilWhenGhFails` は、終了コードが 0 以外・throw の 2 件にする。
- [x] 2.6 `GhDiagnosticsTests` と `AccountDiscoveryTests` を整理し、テストが通ることを確かめる。
  - `keepsTheVersionWithoutRunningGhVersionAgain`、`readingTheGhDoesNotReload`、`reportsAnUnreadableHostsFile`、`doesNotRefreshBeforeGhIsVerified` を削除する。
  - 型で保証される `String(reflecting: detection)` の 2 行を消す。
  - `reportsAnOutdatedGh` は `recordsAnOutdatedVersion` に統合する。
  - `BlockingDiscovery.ghReads` と `ghReadCount` を消す。
- [x] 2.7 `AccountDiscoverySettingsTests` と `AccountStoreTests` を整理し、テストが通ることを確かめる。
  - `AccountDiscoverySettingsTests`:
    - `doesNotFallBackFromAnUnusableGhPath` を削除する。
    - 必ず通る removedKeys の 1 行を消す。
    - `doesNotPassGhConfigDirWithoutAnOverride` は残す。
  - `AccountStoreTests`:
    - `runsAQueuedReloadAfterTheCurrentOne` と `doesNothingWithoutDiscovery` を削除する。
    - `keepsTheListWhileReloading` は、`reload(userInitiated: true)` でも一覧が残ることを確かめる形に書き換える。
  - `ArgumentGatedRunner` は `GatedProcessRunner` に統合して、Support に置く。

## 3. GitHub API・アプリ

- [x] 3.1 `ThreadActionRequestTests` と `MarkThreadReadTests` を整理し、テストが通ることを確かめる。
  - 「リクエストを組み立てる」3 本は、メソッド・URL・ボディ・Content-Type だけを確かめる形に縮める。
  - GHES と GHE Cloud の URL のテスト 3 本を削除する。
  - Done とすべて既読の `classifiesTheStatus` は、各操作に固有の成功の集合と、失敗の 1 件だけにする。fake の自己検証になっているリダイレクトと件数の判定は消す。
  - `sendsNothingForAnInvalidID` は、Read 側の 1 本・1 件にまとめる。
- [x] 3.2 `GitHubAPIClientTests` を整理し、テストが通ることを確かめる。
  - 削除するもの:
    - `stopsAtTheTenthPage`（件数の確認は `isTruncatedByTheNextLinkEvenWithFewerThreads` に移す）
    - `isNotTruncatedWhenPagesEndEarly`
    - `NotificationSubjectNumberTests`
    - `doesNotLeakTheTokenOrTheErrorBodyInResults`
    - `keepsEachAccountsTokenAcrossPagesWhenFetchingConcurrently`
  - 縮小・統合するもの:
    - `doesNotFollowANextLinkOutsideTheAPIBase` と `classifiesTransportFailures` は 1 件にする。
    - `readsScopes` に `treatsAMissingScopesHeaderAsInsufficient` を統合する。
    - `doesNotCacheOrKeepCookiesOrSharedHeaders` から、タイムアウトの定数の行を外す。
  - 1.8 で移したテストもここに置く。
  - オリジン検査の確認が 1 件残っていることを確かめる。
- [x] 3.3 `ThreadDetailsRequestTests` を整理し、テストが通ることを確かめる。
  - `usesTheIssuesPathForPullRequests` は GHES の 1 件にする。
  - `sendsNothingWithoutANumber` と `sendsNothingToTheLinkedHost` は、それぞれ 1 件にする。
- [x] 3.4 `GitHubAPIModelTests` と `ThreadEventResolverTests` を整理し、テストが通ることを確かめる。
  - `rejectsABodyThatIsNotAnArray`、`botActor`、`rejectsAMalformedIssue` を削除する。
  - `nullOrInvalidActor` は、actor が null の場合だけにする。
  - `rejectsRepositoryNames` から `"-x/app"` を外す。
- [x] 3.5 アプリまわりのテストを整理し、テストが通ることを確かめる。
  - `MewbellTests.swift` はファイルごと削除する。
  - `SingleInstanceTests` の 3 本（`acquiresWhenNobodyHoldsTheLock`、`secondInstanceCanAcquireAfterFirstReleases`、`acquiringTwiceFromTheSameHolderSucceeds`）を削除する。
  - `LaunchAtLoginTests.reportsThatApprovalIsNeeded` は、承認待ちでもスイッチが ON のままであることを確かめる形に書き換える。
  - `DiagnosticsReportTests` の、必ず通る `!text.contains("test-token")` を消す。
- [x] 3.6 `scripts/tests/verify-app-test.sh` を整理し、`bash scripts/tests/verify-app-test.sh` が通ることを確かめる。
  - 禁止する entitlement のループを、代表 1 件にする。
  - バージョンと build number の 2 ケースを、1 回の実行にまとめる。
- [x] 3.7 `FakeHTTPTransport` の、使われていない `bodyLimit` の検査を消す。テストが通ることを確かめる。

## 4. ストア・UI・通知

- [x] 4.1 `NotificationStoreOpenTests` と `NotificationStoreActionTests` を整理し、テストが通ることを確かめる。
  - `countsNothingForStoppedAccounts` を削除する。
  - Web の通知一覧を開くテストのうち、participating-only と止まったアカウントの 2 本を削除する。
  - `dropsAPendingReadWhenTheAccountCannotBeUsed` は 2 件にする。
  - `canMarkAllRead` の 2 本は、`FeedState.canMarkAllRead` の 3 行の parameterized にまとめる。
- [x] 4.2 `NotificationStoreNewThreadsTests` を整理し、テストが通ることを確かめる。
  - 次の 7 本を削除する。
    - `ignoresThreadsThatComeBackUnchangedAfterMarkingAllReadFails`
    - `reportsNewAndUpdatedThreads`
    - `staysQuietForTheFirstFetchAfterARestart`
    - `ignoresChangesOfOnlyTheDiagnostics`
    - `doesNothingWhileRetrying`
    - `doesNotPostWhatArrivedWhileOffWhenTurnedBackOn`
    - `reportsNoAccountsWhenNotLoggedIn`
  - `doesNotReportARemovedThreadThatComesBackUnchanged` と `startsOverAfterStopping` は、それぞれ統合先へ `#expect` を移してから消す。
  - `reportsOnlyTheAccountMarkedAllRead` は、「取り下げだけのときは `onNewThreads` を呼ばない」ことを確かめる形に縮める。
- [x] 4.3 `SystemNotificationTests` と `SystemNotifierSettingsTests` を整理し、テストが通ることを確かめる。
  - 次の 4 本を削除する。
    - `retractsOnlyThatAccountWhenNotificationsAreTurnedOff`
    - `keepsNotificationsOfTheNewBaseline`
    - `ignoresNonStringValues`
    - `retractsOnlyTheAccountMarkedAllRead`
  - `clearsTheAccountForAnEmptyBaseline` は、`postsNothingForTheBaselineAndClearsStaleNotifications` に統合する。
  - `leaksNeitherTheTokenNorAPIURLs` から、必ず通るトークンの行を消す。API の URL を含まないことの確認は残す。
  - `FakeUserNotificationCenter.removed` を消す。
- [x] 4.4 `ThreadPresentationTests` を整理し、テストが通ることを確かめる。
  - `describesEvents`、`namesReasons`、`ThreadIcon` の表の写しを、代表のケースか関係の確認にする。
  - `opensTheWebNotificationsPageOfTheHost` はホストを 1 つにする。
  - 番号を読むテスト 2 本を縮める。
  - `namesEveryEvent` と、開く URL の検査は残す。
- [x] 4.5 `ThreadDetailsCacheTests` と `ListExpansionTests` を整理し、テストが通ることを確かめる。
  - `ThreadDetailsCacheTests`:
    - `refetchesWhenTheUpdateAdvances` は `attachesOnlyWhenTheUpdateMatches` に、`retriesTemporaryFailures` は `givesUpAfterRepeatedFailures` に統合する。
    - `resetForgetsEverything` を削除する。
  - `ListExpansionTests` の 4 本を削除する。
- [x] 4.6 次のファイルを整理し、テストが通ることを確かめる。
  - `AccountDisclosureTests`:
    - `collapsesAReadyAccountWithNoThreads` を削除する。
    - 折りたたまない場合を parameterized にまとめ、`.retrying` の行を足す。
    - `DisclosureButtonCountTests` を parameterized にまとめる。
  - `ActionFailureMessageTests.givesNoReasonForOtherFailures` は 1 件にする。
  - `EnabledStatusesTests` は 2 組を、それぞれ 1 本にまとめる。
  - `MarkAllReadLabelsTests` の help の文言の完全一致を、要点の `contains` にする。
  - `NotificationStoreRepositoriesTests` の、実装の式を写した 1 行を消す。

## 5. 確認

- [x] 5.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `npx openspec validate --all --strict` を通す。
  - `bash scripts/tests/verify-app-test.sh` を通す。
  - テストの実行時間を変更の前後で比べて、PR に書く。
- [ ] 5.2 `bash scripts/run.sh` で起動し、手元で確かめる。
  - 一覧の表示、既読、再読み込みが今までどおり動くこと。
  - この change は本体の振る舞いを変えないので、動作確認として行う。
- [x] 5.3 `git grep` で、security.md の性質を確かめる最後の 1 本が残っていることを確かめる（design.md の「セキュリティ」の表）。

## 6. レビュー

- [x] 6.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 6.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 6.3 ロジックの変更を含む修正が多ければ、6.2 を新しいサブエージェントでもう一度実行する。
