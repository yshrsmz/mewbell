# Design

## Context

テストは Swift Testing で書いている。ネットワークは `HTTPTransport` を `FakeHTTPTransport` に、gh サブプロセスは `ProcessRunning` を `FakeProcessRunner` に差し替えている（A5）。この change では差し替えの仕組みは変えない。

候補は、実装と `openspec/specs/` を読ませた別コンテキストのサブエージェントで洗い出し、もう一度別のサブエージェントで、候補ごとに実物（代わりに拾うとされたテストの `#expect` の中身まで）と突き合わせた。行番号はずれるので、対象はテストの名前で書く。

## Goals / Non-Goals

**Goals:**

- `docs/testing.md` の T1・T2・T4 に当たるテスト（確信度が高・中のもの）を、削除・統合・縮小する。
- 消すテストにしか無い確認は、残すテストへ移す。

**Non-Goals:**

- Polling・store・通知・UI の側のテスト（`ThreadPresentationTests`、`ReleaseTagTests` を含む）。別の change で行う。
- 確信度が低の候補。理由は「採らなかった候補」に書く。
- `docs/testing.md` の「既知の逸脱」のテストの待ち方を直すこと。
- 本体のコードと fake の変更。

## Decisions

### D1. 判断の基準と残す側の選び方（`docs/testing.md` の T1・T2・T4・T8）

削るかどうかは T1 で決める。2 つのテストが同じ不具合を拾うときは、T8 の順（速い単体テスト、仕様を直接表すテスト、T2 の正本）で残す側を選ぶ。この change での正本は次のとおり。

| 判断 | 正本 |
|---|---|
| ステータスコードの分類 | `GitHubAPIClientTests.classifiesStatusCodes` |
| 共有の `get()` の失敗（401・404・レート制限・リダイレクト・形の崩れたボディ） | `ThreadDetailsRequestTests` の Issue の経路のテスト |
| API のベース URL とホストの種類 | `APIEndpointsTests.derivesBaseURLs` |
| `Authorization` を付けること | `GitHubAPIClientTests.buildsTheRequest` |
| リリースのタグの検証 | `ReleaseTagTests.rejectsTags` |
| run の選び方（`closestRun`・`runSpanning`） | `WorkflowRunSelectionTests` |

### D2. 削除・統合・縮小するテスト

GitHubAPI:

| テスト | 操作 | T | 代わりに残るもの |
|---|---|---|---|
| `URLQueryValueTests`（ファイル） | 削除。`("feat;x", "branch=feat%3Bx")` を `ThreadDetailsRequestTests.escapesTheBranch` に足す | T2・T3 | `ActionsThreadWebURLTests` のエスケープの行、`escapesTheBranch`、`takesTheOnlyWaitingRunTheUserCanApprove` のクエリ |
| `CheckSuiteTitleTests.readsTheTitle` | 7→4（`cancelled`・`skipped`・`succeeded` を消す） | T4 | `ActionsThreadWebURLTests.opensTheFilteredRunsWithoutARun` が端から端まで通す |
| `CheckSuiteTitleTests.rejectsTheTitle` | 12→8（`someone requested…`、ブランチが空、`Attempt #x`、`ma\nin` を消す。`\u{662}` は残す） | T4 | 残した行 |
| `ThreadDetailsRequestTests.fetchesThePageBeforeTheLastWithoutACandidate` | `looksForACloserEventOnThePageBeforeTheLast` に統合し、`page=4` の URL の確認を移す | T4 | 統合先 |
| `ThreadDetailsRequestTests.treatsAPlainForbiddenAsUnavailable` | 削除。`treatsAMissingIssueAsUnavailable` の引数に 403 を足す | T4 | 統合先 |
| `+Release` の `buildsTheReleaseURLFromTheValidatedRepository`、`buildsTheReleaseURLOnGHES`、`sendsNothingWithoutAReleaseID`、`unauthorizedForARelease`、`rateLimitedForARelease` | 削除 | T2 | Issue の経路の同じテスト、`readsNoReleaseIDFromOtherSubjects` |
| `+Release` の `doesNotUseTheHTMLURL` | 削除。固定データ `release()` の `htmlURL` の既定値を攻撃者のホストにする | T1 | `ReleaseSummary` が `tagName` しか持たない（型の保証）。開く URL は `ThreadPresentationTests.opensTheReleaseOfTheTag` |
| `+Release` の `treatsAnInvalidTagAsUnavailable` | 4→1（`../../settings`） | T2・T4 | `ReleaseTagTests.rejectsTags` |
| `+Release` の `temporaryFailuresForARelease` | 確認 6→1（`{}`） | T2 | Issue の経路の一時的な失敗のテスト |
| `+Release` の `treatsAMissingReleaseAsUnavailable` | 4→1（404） | T4 | `treatsAMissingIssueAsUnavailable` |
| `+Actions` の `buildsTheWaitingRunsURLOnGHES`、`takesTheApprovableRunClosestToTheNotification`、`findsNoRunWhenTwoRunsSpanTheNotification`、`findsNoRunWhenTheBranchRunsCannotBeRead` | 削除 | T2 | `usesTheIssuesPathForPullRequests`、`WorkflowRunSelectionTests`、`takesTheOnlyRunTheUserCanApprove`、`rejectsAnApprovableRunThatStartedWaitingLater` |
| `+Actions` の `findsNoWaitingRun` | 6→4（`[false, false]` と 6 件の行を消す。`[true, true]` の行は必ず残す） | T4 | 残した行 |
| `+Actions` の `doesNotSearchTheSpanningRunAfterAWaitingRunOrAFailure` | ループ 3→1（二次レート制限を残す） | T4 | 残した 1 つ |
| `+Actions` の `rejectsInvalidRunIDs` | 21 桁の後半を削る（`-5` は残す） | T1 | `JSONDecoder` の挙動 |
| `+Actions` の `stopsAtAFailedPendingDeploymentsRequest`、`findsNoRunOfTheWorkflowAndDoesNotKeepTheHTMLURL` | 後半を削る | T1・T2 | 前半の確認、`takesTheClosestRunOfTheWorkflow`。`runs()` の固定データの html_url は攻撃者のホストのまま |
| `+Actions` の `findsNoRunWhenTheRunsCannotBeRead`、`failsOnUnauthorizedMalformedAndRedirectedLists` | 3→1（404）、3→1（形の崩れた一覧） | T2 | Issue の経路の `get()` のテスト |
| `fetchesTheIssueAndItsTimeline`、`fetchesTheTag`、`takesTheOnlyWaitingRunTheUserCanApprove` の `Authorization` の確認 | 確認だけを削る | T2 | `GitHubAPIClientTests.buildsTheRequest`、ポーラーの層のトークンの確認 |
| `NotificationThreadTests.readsTheKind` | `.other("CheckRun")` の 1 行だけにする | T2 | `+Actions` が `WorkflowRun` と `CheckSuite` を decode している |
| `NotificationThreadTests.acceptsANullSubjectURL` | 削除 | T2 | `+Actions` のスレッドが `subjectURL: nil` で decode している |
| `LinkHeaderTests.returnsNilWithoutALastLink` と `readsTheLastLink` の 2 つ目の確認 | 削除 | T2・T4 | `returnsNilWithoutANextLink`、`readsTheLastLink` の 1 つ目 |
| `ThreadEventResolverTests.actorEvents` | 6→2（`convert_to_draft` と `head_ref_force_pushed`） | T4 | 残した 2 行 |
| `ThreadEventResolverTests.doesNotKeepCommentBodies` | 削除 | T1 | `TimelineItem` に本文の項目が無い（型の保証） |
| `MarkThreadReadTests.classifiesTheStatus` | 14→9。`(403, ["Retry-After": "soon"])` を `classifiesStatusCodes` に移す。429 の行は残す | T2 | `classifiesStatusCodes` |
| `ThreadIDTests.rejects`、`accepts` | 8→5（`""`、21 桁、全角の数字、`-1`、`../1` を残す）、3→2（`0` と 20 桁） | T4 | 残した引数 |

gh・アカウント・設定・App・シェル:

| テスト | 操作 | T | 代わりに残るもの |
|---|---|---|---|
| `AccountTests.classifiesHosts` | 削除。`("ghe.com", "https://ghe.com/api/v3", "https://ghe.com")` を `APIEndpointsTests.derivesBaseURLs` に足す | T2 | `derivesBaseURLs` |
| `AccountDiscoveryTests.reportsMissingGh` | 削除 | T4 | `GhDiagnosticsTests.forgetsTheGhWhenItIsGone` |
| `GhClientTests.tokenIsNilWhenGhDoesNotGiveOne` の `test-token\nsecond-line` | 1 行削除 | T2 | `AccessTokenTests.rejectsMalformedOutput` |
| `AccountDiscoverySettingsTests.doesNotFallBackFromAnUnusableConfigDirectory` | `GhDiagnosticsTests.forgetsTheConfigDirectoryWhenTheOverrideIsUnusable` に統合。トークンの取得の件数は、前後で変わらないことで確かめる | T4 | 統合先 |
| `AccountStoreGhDiagnosticsTests.publishesTheGhOfTheNewConfigDirectory` | 削除 | T4 | `publishesTheGhAfterEachReload` |
| `AccountStoreTests.stopsReportingStateChangesAfterTermination` | `closesCredentialsAndRefusesToReloadWhenTerminating` に統合 | T4 | 統合先 |
| `AccountStoreSettingsTests.reloadsWhenAnAccountIsEnabledAgain` | 削除。状態の確認を `reloadsAfterTheDisableWhenEnabledRightAway` に移す | T4 | 移し先 |
| `SingleInstanceLockTests.reportsFailureWhenTheLockFileCannotBeOpened` | 削除 | T4 | `doesNotFollowASymbolicLinkAtTheLockFile` |
| `SettingsStorageTests.userDefaultsStorageReadsMalformedValuesAsDefaults` | 削除 | T1 | Foundation の保証。既定値が true なので見分けもつかない |
| `StatusItemMenuTests.attachesOnceToTheSameButton` | `opensSettingsThroughTheLatestAction` に統合。`scheme == "https"` の確認は削る | T4 | 統合先 |
| `verify-app-test.sh` の署名の後の書き換えのケース | 削除 | T1 | 署名の無い `.app` のケースが `codesign --verify` の失敗を確かめる |
| `check-architecture-test.sh` の unknown-id | 削除 | T4 | adjacent-ids |
| `check-architecture-test.sh` の廃止した ID の 2 本、重複の 2 本 | それぞれ 1 本に統合（偽のリポジトリに 2 か所の書き換えを入れ、ファイルごとの出力で確かめる） | T4 | 統合先 |

### D3. 採らなかった候補

- `ActionsThreadWebURLTests.opensTheFilteredRunsWithoutARun` の縮小: 結果ごとに別の分岐で、期待値（`is:cancelled` など）は GitHub の仕様の値で、実装の写しではない。`CheckSuiteTitleTests` の縮小もこのテストを前提にしている。
- `AccountDiscoveryTests.fetchesTokensForEveryAccount` の `--hostname` の確認: fake は引数の最後（ユーザー）からトークンを作るので、正しいホストを渡していることを上の層で確かめるのはここだけ。
- `GhClientTests.fetchesATokenForTheGivenAccount` のタイムアウトと出力の上限: 値は定数の写しだが、security.md の「タイムアウトと出力の上限」を `gh auth token` について確かめるのはここだけ（T1 の例外）。
- `RedactionTests.redactsEveryTokenInTheText`: 1 つの文字列の 2 つのトークンを伏せることを確かめるのはここだけ。最初の 1 つしか伏せない退行を拾う、伏せ字の最後の 1 本（T1・T4 の例外）。
- `AccountDiscoverySettingsTests.doesNotPassGhConfigDirWithoutAnOverride`、`GhCommandTests`: remove-redundant-tests で残すと決めた理由（ユーザーの `GH_CONFIG_DIR` を潰す不具合、ui spec のシナリオを確かめる唯一のテスト）が今も当てはまる。
- 確信度が低の候補（`ThreadActionRequestTests` の二次レート制限の行、`GitHubAPIClientTests` の User-Agent、`GhDiagnosticsTests` の統合 1 件、`SingleInstanceTests` のロックの解除、`DiagnosticsReportTests` の統合、`AppInfoTests`、`check-architecture-test.sh` の proposal-reference）: 削っても減る量が小さく、残す価値が少しある。

### スレッドと actor の境界・テストでの差し替え

本体の actor と `@MainActor` の境界（A2）と、差し替えの仕組み（A5）は変えない。統合したテストでも、fake で同期的に待たない（T6）。消すテストの名前は `docs/architecture.md` と `docs/testing.md` には書かれていない（grep で確かめた）。

## セキュリティ

本体のトークンの流れは変えない。トークンは `gh auth token` で取得し、`CredentialStore` の actor の中にだけ持ち、リクエストごとにアカウントの API ベースへ送り、アカウントを外すときと終了時に破棄する。

security.md の性質を確かめるテストは、この change の後も性質ごとに次が残る。攻撃の形ごとの引数（`APIEndpointsTests.checksTheRequestURL` の全行、`ReleaseTagTests`）は削らない。

| 性質 | 残るテスト |
|---|---|
| 伏せ字 | `RedactionTests` の 3 本、`AccessTokenTests.neverRevealsTheValueWhenConvertedToText`、`DiagnosticsReportTests.redactsTokenLikeStringsInTheCopiedText` |
| オリジン検査と URL の組み立て | `APIEndpointsTests.checksTheRequestURL`、`sendsNothingToTheLinkedHost`、`sendsNothingWithoutANumber` |
| リクエストごとのトークン | `GitHubAPIClientTests.buildsTheRequest`、ポーラーの層のトークンの確認 |
| リダイレクトの拒否 | `classifiesStatusCodes` の 302、`MarkThreadReadTests.classifiesTheStatus` の 307、Issue の経路の一時的な失敗 |
| ID・ホスト名・ユーザー名の検証 | `ThreadIDTests`（縮小後）、`sendsNothingForAnInvalidID`、`APIEndpointsTests.rejectsAnInvalidHost`、`fetchesTokensForEveryAccount` の `--hostname`、`GhClientTests.fetchesATokenForTheGivenAccount` |
| API が返す html_url を使わない | 型の保証。固定データ `release()` と `runs()` の html_url は攻撃者のホストにしておく |
| タイムアウトと出力の上限 | `GhClientTests.fetchesATokenForTheGivenAccount` |
| シンボリックリンクを追わない | `SingleInstanceLockTests.doesNotFollowASymbolicLinkAtTheLockFile` |
| 署名 | `verify-app-test.sh` の署名の無い `.app` のケース |

## Risks / Trade-offs

- [統合のときに、元のテストにしか無かった `#expect` を落とす] → T8 の手順に従い、移した `#expect` は実装を一時的に壊して落ちることを確かめる。
- [`HostKind` が大文字のホスト名を小文字にすることを確かめるテストが無くなる] → `classifiesHosts` の `GitHub.com` の行だけが確かめていた。API のベース URL を導く `APIEndpoints` は、`HostKind` に渡す前に自分でホスト名を小文字にしている。だから `derivesBaseURLs` に行を足しても `HostKind` の小文字化は確かめられない。`HostKind` を大文字のまま受け取るのは `Account` の並べ替えだけで、`hosts.yml` のホスト名は gh が小文字で書くので、影響は並び順だけになる。テストは足さない。
- [確信度が中の候補に、見落としている固有の価値がある] → 削除した後の code-review で見てもらう。
