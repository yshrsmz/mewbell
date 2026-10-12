# Design

## Context

候補の洗い出しでは、テストを 4 つの領域（ポーリング、gh・アカウント、GitHub API・アプリ、ストア・UI・通知）に分け、それぞれ実装と突き合わせた。候補ごとに「削ったときに見逃す現実的な不具合」を書き、代表的な指摘は実物で確かめた。具体的な対象は tasks.md に書く。

テストは Swift Testing（`@Test`、`#expect`、`@Test(arguments:)`）で書いている。ネットワークは `HTTPTransport` を `FakeHTTPTransport` に、gh サブプロセスは `ProcessRunning` を `FakeProcessRunner` に、通知は `UserNotificationCenter` を `FakeUserNotificationCenter` に差し替えている。この change では、これらの差し替えの仕組みは変えない。

## Goals / Non-Goals

**Goals:**

- 次のどれかに当たるテストを、削除・統合・縮小する。
  - 削っても見逃す不具合が無いもの
  - 他のテストが同じ不具合を拾えるもの
  - 型や言語が保証しているもの
- 実時間の待ちと、必ず通る確認を減らす。

**Non-Goals:**

- 足りないテストを網羅的に足すこと。ただし、書き換えの結果、今まで通っていなかった分岐を確かめるようになるものは入れる。対象は次の 2 つ。
  - `AccountStoreTests` の `userInitiated: true` の場合
  - `LaunchAtLoginTests` の、承認待ちでもスイッチが ON のままであること
- テストの fixture の作り直し。例として、`FakeHTTPTransport.pausedMethod` を `pausedWhere` に一本化することはしない。
- 固定の sleep で合流を待つテスト（`keepsGhRunningForAJoinedCaller…` と `sharesARunningTokenFetch…`）を、別の待ち方に置き換えること。

## Decisions

### 判断の基準

テストを残すかどうかは、件数やカバレッジではなく、「削ったときに、どんな現実的な不具合を見逃すか」で決める。他のテストが同じ不具合を拾えるときは、次の順で残す側を選ぶ。

1. 速い単体テスト
2. 仕様を直接表しているテスト
3. 層の正本になっているテスト。たとえば、共通ヘッダーは `buildsTheRequest`、オリジン検査は `APIEndpointsTests.checksTheRequestURL` が正本にあたる。

### 候補どうしの調整

1 つの不具合を拾うテストが 2 か所にあり、それぞれが「もう一方で拾える」と判定されている組み合わせがある。両方を消さないよう、次のように残す側を決める。

- `refetchesWhenTheUpdateAdvances`（ポーラーとキャッシュの両方にある）: キャッシュ側を `attachesOnlyWhenTheUpdateMatches` に寄せて残し、ポーラー側を消す。
- 「配列でないボディ」の検査（3 か所にある）: `GitHubAPIModelTests.rejectsABodyThatIsNotAnArray` を消す。`ThreadEventResolverTests.skipsMalformedItemsAndRejectsNonArrays` と `GitHubAPIClientTests.failsOnAMalformedBody` を残す。
- ポーリング間隔の境界: `FeedDiagnosticsTests.derivesThePollInterval` に集める。`PollingDiagnosticsTests.recordsTheIntervalAndTheNextFetch` は配線を確かめる 1 件に減らす。

### 残すもの

候補の洗い出しで削除を検討したが、次のテストは残す。

- `AccountDiscoverySettingsTests.doesNotPassGhConfigDirWithoutAnOverride`: 上書きが無いときに既定のディレクトリを `GH_CONFIG_DIR` に入れると、ログインシェルの環境でユーザーが設定した `GH_CONFIG_DIR` を潰す。この不具合を拾える。
- `NotificationStoreOpenTests.passesFeedChangesToTheNotifier`: 本物のポーラーと本物の `SystemNotifier` を通す唯一の通し試験。
- `NotificationStoreActionTests.marksAThreadReadWithoutOpeningIt`: `markRead` を `.done` に配線し間違えたとき、store の単体で拾えるのはこのテストだけ。

### `GitHubAPIClientTests.keepsEachAccountsTokenAcrossPagesWhenFetchingConcurrently`

このテストは削除する。理由は次のとおり。

- `GitHubAPIClient` は状態を持たない struct で、トークンを毎回引数で受け取る。
- fake にも並行に割り込む仕組みが無いので、今の設計ではこのテストは落ちようがない。

Gitify #2176 の不具合（共有クライアントの既定のヘッダーにトークンを入れる）を防ぐ約束は CLAUDE.md と security.md にあり、レビューで守る。もう 1 つの案として、仕掛け線のつもりで残すことも考えた。しかし、共有状態を持つ実装に変えたとしても、このテストの fake では割り込みが起きないので検出できない。そのため採らない。

### 本体の変更

`AccountPoller.requestUnconditionalFetch()` は nonisolated で、本体から呼ぶのは `refreshNow` だけになる。テスト側を `perform(.read)` の経路に書き換えたうえで private にする。外から見た振る舞いは変えない。

### スレッドと actor の境界

本体の actor と `@MainActor` の境界は変えない。テストを統合するときも、`SWIFT_APPROACHABLE_CONCURRENCY` の注意（fake で同期的に待たない）に従う。`Thread.sleep` を使う唯一のテストは、この change で削除する。

## セキュリティ

本体のトークンの流れは変えない。トークンは `gh auth token` で取得し、`CredentialStore` の actor の中にだけ持ち、リクエストごとにアカウントの API ベースへ送り、アカウントを外すときと終了時に破棄する。

この change は、security.md の性質を確かめるテストを整理する。各性質について、確かめるテストのうち最後の 1 本は必ず残す。残すテストは次のとおり。

| 性質 | 残すテスト |
|---|---|
| 伏せ字 | `AccessTokenTests.neverRevealsTheValueWhenConvertedToText`、`RedactionTests`（統合後の 1 本と `leavesOtherTextAlone`）、`DiagnosticsReportTests.redactsTokenLikeStringsInTheCopiedText` |
| 環境変数の除去 | `GhEnvironmentTests` の除去のテスト。`passesOnlyTheGivenEnvironment` は、親の環境が漏れないことを確かめる形に書き換えて、より厳密にする |
| オリジン検査 | `APIEndpointsTests.checksTheRequestURL`、`doesNotFollowANextLinkOutsideTheAPIBase`（1 件に縮小）、`sendsNothingToTheLinkedHost`（1 件に縮小） |
| リダイレクト拒否 | `URLSessionTransportTests.rejectsEveryRedirect` |
| ホスト名・ユーザー名の検証 | `GhIdentifierTests`、`HostsFileTests.skipsInvalidEntriesAndKeepsTheRest` |
| 開く URL の検査 | `ThreadWebURLTests.fallsBackToTheRepositoryPage`、`ThreadOpenRequestTests.rejectsInvalidIdentifiers` と `replacesAnUnsafeURLWithTheRepositoryPage`、`doesNotOpenTheWebNotificationsPageForAnInvalidHost` |
| gh のパスの検証 | `ExecutableValidatorTests` の拒否する側、`LoginShell.rejectsUnlistedShells`、`rejectsARelativeAnswerFromTheShell` |
| `hosts.yml` のトークンを型に載せない | `HostsFileTests` の `String(reflecting:)` の確認のうち 1 つ |
| キャッシュと共有ヘッダー | `doesNotCacheOrKeepCookiesOrSharedHeaders`（タイムアウトの定数の行だけ外す） |

## Risks / Trade-offs

- [統合のときに、元のテストにしか無かった `#expect` を落とす] → 統合するテストごとに、元の `#expect` を統合先へ移したか、他のテストで拾えるかを確かめる。統合した後のテストは、実装を一時的に壊して落ちることを代表のものだけで確かめる。
- [確信度が中の候補に、見落としている固有の価値がある] → 削除した後に、別コンテキストの code-review で見てもらう。指摘があれば戻す。
- [テストの件数が減ったことで、カバレッジの数値が下がる] → 数値は判断に使わない（Non-Goals）。
