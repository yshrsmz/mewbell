# Design

## Context

この change に関係する今の構成（動機は proposal.md の Why、満たすべき振る舞いは `specs/` の各 delta）:

- `GitHubAPIClient.fetchNotifications` は `page < pageLimit (10)` の間だけ `rel="next"` をたどる。10 ページ目に `rel="next"` があっても、それを結果に残さない。`NotificationsFetchResult.updated` は `threads`、`lastModified`、`pollInterval`、`scopes` を持つ
- `AccountPoller`（actor）は `FeedState`（`phase` と `threads`）を `onUpdate` で `NotificationStore`（`@MainActor`、`@Observable`）に渡す。`NotificationStore.apply` は `feeds[id] != state` のときだけ書き、`ThreadNotifying.feedChanged` を呼ぶ。`SystemNotifier.feedChanged` はスレッドが変わったときだけ通知を出す
- `AccountPoller.perform` と `markAllRead` は、結果が `.succeeded` でなければログに書いて捨てる。すべて既読の結果ごとの扱いは `readThroughs` に、取得の番号（`fetchCount`）を使って「結果が出た後に送った取得か」を決めている
- 次の取得までの待ち（`PollStep.wait(delay)`）は `run()` の中だけで使い、状態には残さない（`.retrying(nextAttempt:)` は失敗のときだけ）
- `AccountDiscovery`（actor）は `GhLocator.locate` で gh の `URL` だけを受け取り、`verifyVersion` で読んだ `GhVersion` は対応しているかの判断にだけ使って捨てる。既定の設定ディレクトリは `GhConfigDirectory.resolve` で `URL` だけを決める
- `AccountStore`（`@MainActor`）は `DiscoveryState` を持ち、変わったら `onStateChange` で `NotificationStore.sync(with:)` を呼ぶ。`DiscoveryState` は多くのテストのフィクスチャで作っている
- 設定ウィンドウ（`SettingsView`）は `AppSettings`、`AccountStore`、`LaunchAtLogin` を受け取り、`NotificationStore` は受け取っていない
- `Redaction.redactTokens(in:)` が gh の標準エラー出力の伏せ字に使われている

## Goals / Non-Goals

**Goals:**

- 診断の値を、それぞれの値を知っている actor の中で作り、`@MainActor` の `@Observable` な型（`NotificationStore`、`AccountStore`）が持つ値として UI に届ける。Diagnostics タブのために actor に問い合わせる経路を作らない（開いても gh や API を呼ばない、という spec を構造で守る）
- 表示とコピーの中身を 1 つの純粋な値の型から作り、ユニットテストで項目と伏せ字を確かめられるようにする
- 既存の `FeedState` / `DiscoveryState` を作っているテストを、できるだけ書き換えずに済ませる

**Non-Goals:**

- 取得の履歴（直近 N 回の結果）を持つこと。持つのは最後の 1 回の失敗だけ
- 操作の失敗から、トークンの取り直しや再送をすること
- Diagnostics の値を `Logger` に書き出すこと（ログは今のまま）

## Decisions

### D1. 型の置き場所と分担

| 置き場所 | 型 | 役割 |
| --- | --- | --- |
| `GitHubAPI/GitHubAPIClient.swift` | `NotificationsFetchResult.updated(..., truncated: Bool)` | 10 ページ目に `rel="next"` があったか |
| `Polling/FeedDiagnostics.swift`（新規） | `FailureKind`、`ThreadActionKind`、`ActionFailure`、`FeedDiagnostics`、`PollIntervalInfo` | 取得と操作の失敗の分類、Diagnostics に出すアカウントごとの値 |
| `Polling/FeedState.swift` | `FeedState.isTruncated`、`FeedState.actionFailure`、`FeedState.diagnostics` | 打ち切り、知らせる操作の失敗、診断の値 |
| `GhCLI/GhLocator.swift` | `GhLocation`（`url`、`source: GhExecutableSource`） | gh の実体のパスと見つけ方 |
| `GhCLI/HostsFile.swift` | `GhConfigDirectory.Resolved`（`url`、`source: GhConfigDirectorySource`） | 設定ディレクトリと決め方 |
| `GhCLI/GhDiagnostics.swift`（新規） | `GhDiagnostics` | 読み直しで記録する gh の検出の結果（gh-cli「検出の結果の記録」） |
| `Diagnostics/DiagnosticsReport.swift`（新規） | `DiagnosticsReport` | 表示とコピーの中身（節と行）。`plainText` は伏せ字にしたテキスト |
| `UI/DiagnosticsSettingsView.swift`（新規） | `DiagnosticsSettingsView` | Diagnostics タブ。`DiagnosticsReport` を描き、Copy で `NSPasteboard` に入れる |
| `UI/AccountSectionView.swift`、`UI/ThreadRow.swift` | `FeedStatusView`、`ActionFailureView`（新規）、`MarkAllReadButton` | 打ち切りの表示、操作の失敗の 1 行、打ち切り時の `Mark all as read?` |

`FailureKind` は `network`、`httpStatus(Int)`、`redirect`、`bodyTooLarge`、`malformedBody`、`noToken`、`rateLimited`、`unauthorized`、`rejectedURL` を持ち、`FetchFailure` と `ThreadActionResult` と `NotificationsFetchResult` の失敗の case から作る。ポップオーバーに出す 3 分類（認証エラー、レート制限、それ以外）は `FailureKind` の計算プロパティにする。

代替案: 診断の値を `FeedPhase` の case の連想値に足す。→ `FeedPhase` の `switch` があちこちにあり、`.loaded` に値を足すと既存のパターンとテストが広く壊れる。また打ち切りや最後の失敗は phase と独立に変わるので、横に並べた値にする。

### D2. `FeedState` に足す値と、既存のテストとの互換

`FeedState` に `var isTruncated = false`、`var actionFailure: ActionFailure? = nil`、`var diagnostics = FeedDiagnostics()` を既定値付きで足す。memberwise イニシャライザーは既定値のある引数を省略できるので、既存の `FeedState(phase:threads:)` はそのまま通る。`FeedState.loading` も変えない。

`FeedState` の `Equatable` は新しい値も比べる。次の取得の予定時刻は取得のたびに変わるので、`NotificationStore.apply` は取得のたびに `feeds` を書き直すことになるが、今も `.loaded(updatedAt:)` が取得のたびに変わるので、書き直しの頻度は変わらない。`SystemNotifier.feedChanged` はスレッドの差分だけを見るので、診断の値が変わっても通知は出ない（`.loaded` で基準が無いときの扱いも、今と同じく phase で決まる）。

`CarriedWait(from:now:)` は `phase` だけを見るので変えない。

### D3. `AccountPoller` での記録

- 打ち切り: `fetch` の結果が `.updated` なら `state.isTruncated = truncated`。`.notModified` では触らない。`stop(as:)` では `false` に戻す
- 次の取得の予定時刻: `run()` で `.wait(delay)` を受け取ったとき、`publish` の前に `state.diagnostics.nextFetchAt = now() + delay` にする。`stop(as:)` と、ループが `.loading` を出し直すとき（再開）は `nil` にする
- 間隔: `succeeded(pollInterval:)` で `PollIntervalInfo(seconds: max(60, pollInterval ?? 60), fromHeader: pollInterval != nil && pollInterval! >= 60)` を入れる。ヘッダーが 60 未満なら下限に揃えたことになるので「`X-Poll-Interval` による」とはしない
- スコープ: `.updated` のときに `scopes.scopes`（`Set<String>?`）を入れる。`refreshToken()` で捨てる
- 最後の取得の失敗: `handle` で失敗の case を `FailureKind` にして `TimedFailure(kind:at:)` を入れる。成功では消さない。`stop(as:)` でも消さない（`stop(as:)` は `state = FeedState(phase:threads:)` で作り直しているので、`isTruncated` と `actionFailure` 以外の `diagnostics` を引き継ぐように書き換える）
- 操作の失敗: `perform` と `markAllRead` で結果が `.succeeded` 以外のとき（トークンが無くて送らなかったときを含む。止まっていて送らなかったときは除く）、`ActionFailure(action:kind:at:)` を `state.actionFailure` と `state.diagnostics.lastActionFailure` の両方に入れて `publish` する。あわせて actor の中だけに `noticeClearsFromFetch = fetchCount` を持つ（`readThroughs` と同じ「結果が出た時点の `fetchCount`」）
- 知らせる失敗の消去: `fetch` が返す取得の番号を `handle` に渡し、`.updated` か `.notModified` で番号が `noticeClearsFromFetch` 以上なら `state.actionFailure = nil` にする。`stop(as:)` でも消す

取得を最初からやり直す（`NotificationStore.restart`、無効から有効に戻す）ときは、ポーラーを作り直すので、新しいポーラーの値はすべて既定値から始まる。spec の「取得を最初からやり直したときは消す」は、これで満たす。

代替案: 操作の失敗を `NotificationStore` が持つ。→ 「失敗の結果が出た後に送った取得」の判断には取得の番号が要り、それはポーラーの中にしかない。ポーラーの中で決めて `FeedState` で渡すほうが、既存の `readThroughs` と同じ考え方で揃う。

### D4. gh の検出の結果を `AccountStore` に届ける

`AccountDiscovering` に `func ghDiagnostics() async -> GhDiagnostics` を足す。`AccountDiscovery` は `discover` の中で、`locate` の結果（`GhLocation?`）、確かめたバージョン、使う設定ディレクトリ（`GhConfigDirectory.Resolved?`）を `lastGhDiagnostics` に書く。途中で返る（gh が見つからない、上書きの設定ディレクトリが使えない）ときは、その先の値を `nil` にして書く（前の読み直しの値を残さない）。`AccountStore.reload` は `discovery.reload` が終わった後に `ghDiagnostics()` を読み、`@Observable` な `gh: GhDiagnostics` に入れる。Diagnostics タブはこの値を読むだけなので、タブを開いても gh は実行されない。

バージョンを毎回取り直さないために、`verifiedGhPath` と一緒に `verifiedVersion` を持つ。`verifyVersion` が `gh --version` を実行しないで返る（同じパスで確かめ済み）ときは `verifiedVersion` を使う。古いバージョンのときは `verifiedGhPath` を `nil` にする今の動きを変えず、読んだバージョンは `lastGhDiagnostics` に入れる。

`GhLocator.locate` の戻り値を `GhLocation?` にし、見つけ方を `override` / `standardLocation` / `loginShell` で返す。`GhConfigDirectory.resolve` は `Resolved`（`url` と `source`）を返すようにし、`AccountDiscovery` は既定の設定ディレクトリを `Resolved` で持つ。上書きのときの `source` は `override`。

代替案 1: `DiscoveryState.accounts` などの連想値に gh の情報を足す。→ `DiscoveryState` の変化は `onStateChange` でポーラーの同期を起こすので、診断の値の変化で同期を走らせたくない。またフィクスチャの書き換えが広い。

代替案 2: `reload` の `update` コールバックの引数に gh の情報を足す。→ `update` は途中経過も含めて何度も呼ばれ、`FakeDiscovery` やテストのすべての呼び出しを変える必要がある。読み直しの終わりに 1 回読むほうが小さい。

### D5. `DiagnosticsReport`（表示とコピーの中身）

`DiagnosticsReport` は `Sendable` な値の型で、入力（`GhDiagnostics`、`DiscoveryState`、`[AccountID: FeedState]`、アカウントごとの `AccountPreferences`、`now`、Mewbell と macOS のバージョン）から、節（`gh`、アカウントごと）と行（ラベルと値の文字列）を作る。Diagnostics タブはこの行を `Form` に並べ、Copy はこの行を `ラベル: 値` のテキストにして `Redaction.redactTokens(in:)` を通してから `NSPasteboard.general` に入れる。

行の値に入れてよいのは、spec（diagnostics「Diagnostics に出してはならないもの」）が許すものだけにする。`DiagnosticsReport` を作る関数は `FeedState.threads` の件数だけを読み、件名は読まない。API の URL を作る `APIEndpoints` は使わない。

表示の時刻は、タブではローカルの時刻（`Text(date, style: .time)` と相対時刻）、コピーでは ISO 8601（UTC）にする（貼った先で時差があっても読めるように）。

代替案: View の中で直接 `FeedState` を描き、コピーは別に組み立てる。→ 表示とコピーで項目がずれ、出してはならないものの確認が 2 か所になる。

### D6. actor / `@MainActor` の境界

| 何を | どこで |
| --- | --- |
| 打ち切り・間隔・スコープ・失敗の記録 | `AccountPoller`（actor）。`onUpdate` で `FeedState` を `@MainActor` の `NotificationStore` に渡す（今と同じ経路） |
| gh の検出の結果の記録 | `AccountDiscovery`（actor）。`AccountStore`（`@MainActor`）が読み直しの後に `await` で読む |
| `DiagnosticsReport` の組み立て、Copy、表示 | `@MainActor`（View の `body` とボタンのアクション）。純粋な関数なので、テストでは任意のスレッドから呼べる |

新しい actor や `Task` のループは作らない。

### D7. UI

- `SettingsView` に `notifications: NotificationStore` を足し、4 つ目の `Tab("Diagnostics", systemImage: "stethoscope")` で `DiagnosticsSettingsView` を出す。`MewbellApp` の `Settings` シーンで `appDelegate.notificationStore` を渡す。ウィンドウの大きさは今の 520×420 のままにし、Diagnostics は `Form` の中でスクロールさせる
- 相対時刻（「12 秒前」など）は `TimelineView(.periodic(from:by: 1))` で更新する（`FeedState` が変わらない間も時刻の表示が進むように）
- `FeedStatusView` に `isTruncated` を渡し、`.loaded` と `.retrying` で打ち切りの 1 行を出す
- `AccountSectionView` で `feed.actionFailure` があれば `ActionFailureView` を出す。文は操作と 3 分類から決める（例: `Could not mark a thread as done. It will reappear after the next fetch.`）。認証エラーのときは `CommandRow(command: "gh auth login --hostname <host>")` を添える
- `MarkAllReadButton` の `participatingOnly` を `includesUnlisted`（`participatingOnly || isTruncated`）に置き換え、確認の表示・ツールチップ・アクセシビリティのラベルをそれで決める

### D8. テストでの差し替え

- ネットワーク: 既存の `HTTPTransport` プロトコルと `FakeHTTPTransport` を使う。10 ページの `Link` 付きレスポンスを返して打ち切りを、`pausedMethod` で取得を止めて「失敗の前に送った取得」を作る
- gh サブプロセス: 既存の `ProcessRunning` と `FakeProcessRunner` を使い、`gh --version` の回数と記録したバージョンを確かめる。`GhLocator` の見つけ方は、既存の `GhLocatorTests` と同じく一時ディレクトリの実行ファイルと fake のログインシェルで確かめる
- 設定ディレクトリの決め方は `GhConfigDirectory.resolve(environment:homeDirectory:)` に環境の辞書を渡して確かめる
- `AccountDiscovering` に足すメソッドは `FakeDiscovery` に実装し、返す値をテストから決められるようにする
- `DiagnosticsReport` は値を渡して行とテキストを確かめる（伏せ字、出してはならないものが無いこと）

## セキュリティ

### トークンの流れ

この change はトークンの流れを変えない。トークンは今までどおり `gh auth token --hostname <host> --user <user>` の標準出力から取得し（`GhClient.token`）、`CredentialStore`（actor）のメモリにだけ持ち、`GitHubAPIClient.send` でリクエストごとに `Authorization` に付けてアカウントの API ベースにだけ送り、アカウントの無効化・削除・設定ディレクトリの変更・401 の後・終了時に捨てる。診断の値（`FeedDiagnostics`、`ActionFailure`、`GhDiagnostics`、`DiagnosticsReport`）はトークンを受け取らず、トークンの状態は既存の `TokenState` だけを使う。

### `.claude/rules/security.md` の各項目

- トークンの扱い: `hosts.yml` の読み方は変えない。トークンを永続化しない（診断の値もメモリにだけ持ち、UserDefaults に新しいキーを足さない）。トークン専用の型（`AccessToken`）の伏せ字も変えない。ログは今までどおり `Logger` と `.private` で、新しいログは足さない。gh の標準出力・標準エラー出力は診断に持たず（バージョンは数字だけ）、コピーするテキストは `Redaction.redactTokens(in:)` を通す。テストのトークンは `test-token` などのダミーにする
- gh サブプロセス: 実行するコマンド・引数・環境変数の除去・パスの検証・タイムアウト・出力の上限は変えない。見つけ方を返すために `GhLocator` の戻り値を変えるが、候補の順序と検証は変えない。`gh --version` の実行回数も変えない（D4）
- ネットワーク: 送り先の検査、HTTPS、リダイレクトの拒否、キャッシュなしは変えない。レスポンスから読むのは、`rel="next"` の有無、`X-Poll-Interval` の数字、`X-OAuth-Scopes` のスコープの名前、状態コードの数字だけで、ヘッダーの生の値・`Link` の URL・ボディは持たない。API の URL は Diagnostics に出さない
- URL を開く処理: 触れない
- アプリとビルドの設定: entitlement、Hardened Runtime、Info.plist は変えない。クリップボードへの書き込みに entitlement は要らない（App Sandbox は無効）
- 依存: 外部のパッケージを足さない
- レビュー: PR 本文に「セキュリティ上の確認」の節を設け、上の項目を書く。伏せ字（コピーのテキスト）、出してはならないもの（API の URL・件名・トークンが `DiagnosticsReport` に無いこと）、gh の出力を持たないこと（`GhDiagnostics` に文字列が無いこと）をユニットテストで確かめる

## Risks / Trade-offs

- [コピーしたテキストに、ホームディレクトリのユーザー名を含むパス、ホスト名、GitHub のユーザー名が入る] → ユーザーが押したときだけクリップボードに入れ、自動ではどこにも送らない。Diagnostics タブにコピーされる内容を並べてあるので、貼る前に見られる。トークンは伏せ字にする
- [伏せ字の規則（40 桁の 16 進数）が、パスの一部を伏せてしまう] → 診断のためのテキストなので、伏せすぎは許容する。トークンを漏らさないことを優先する
- [`FeedState` に値を足すことで、`feeds` の比較が少し重くなる] → 比べる値は件数の少ないスカラーと小さな集合だけで、スレッドの配列の比較に比べて無視できる
- [知らせる失敗が、ポップオーバーを開く前に次の取得で消える] → 失敗したスレッドはその取得で一覧に戻るので、ユーザーから見て状態は一貫する。何が起きたかは Diagnostics の「最後の操作の失敗」で見られる
- [GitHub が通知を `updated_at` の新しい順に返すことに頼る（打ち切り時のすべて既読の説明）] → GitHub の REST API のドキュメント（List notifications for the authenticated user）が「sorted by most recently updated」と書いている。順序が違っても、`last_read_at` は表示中の最新のスレッドの時刻なので、それより新しい未読を既読にすることは無い（ツールチップの説明が控えめになるだけ）
