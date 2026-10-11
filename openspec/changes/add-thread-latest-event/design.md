# Design

## Context

- 通知のスレッドは `AccountPoller`（actor、アカウントごと）が `GitHubAPIClient.fetchNotifications` で取り、`FeedState` として `onUpdate` で `NotificationStore`（`@MainActor`）に知らせる。`ThreadChangeDispatcher` は `.loaded` の状態を受け取ったときに `NotificationTracker` で新着を判定し、その場で macOS の通知を出す。つまり、macOS の通知にイベントを入れるには、新着を含む一覧を知らせる前にイベントを付けておく必要がある
- `GitHubAPIClient.send` はトークンを付ける唯一の場所で、`APIEndpoints.isAllowedRequestURL` でオリジンを検査し、リダイレクトを失敗にする。`LinkHeader` は `rel="next"` しか読まない
- スレッドの番号は `ThreadWebURL.subjectNumber` が `subject.url` を検証して求めている（API ベースの下、リポジトリの一致、`pulls|issues/<数字>`）
- 実物の Timeline（`cli/cli`）で確かめたこと:
  - `Link` の URL は `https://api.github.com/repositories/<id>/issues/<n>/timeline?...&page=N` の形で、`rel="last"` がある
  - マージは `merged` と `closed` が同じ時刻でこの順に並ぶ
  - `reviewed` は `actor` が無く `user` と `submitted_at` を持つ。`committed` は `actor` も `created_at` も無く、`author.name`（git の名前）と `committer.date` を持つ
  - Issue の作成は Timeline に出ない。Pull request の作成は、作成前の日付の `committed` と、作成と同時の `review_requested` / `labeled` として出る
  - 実行者には `dependabot[bot]` や `Copilot` がいる（`GhIdentifier.isValidUser` は `[` `]` を拒否する）
  - 実際の通知（`yshrsmz/since-android`、`nuxt/cli`）では、スレッドの `updated_at` はきっかけのイベントの時刻より 20〜36 秒遅れていた
  - Issue のレスポンスは、Pull request でも `state`・`state_reason`・`draft`・`pull_request.merged_at` を持つ
- Gitify は GraphQL で Pull request のコメントとレビューを取り、`updated_at` にいちばん近いものの投稿者を出し、件名の状態をアイコンで出す。push・クローズなどは実行者の候補にしない

## Goals / Non-Goals

**Goals:**

- 新着の macOS の通知に、ほとんどの場合イベントが入っている（新着は 1 回のポーリングで数件なので、上限の 10 件に収まる）
- 一覧の表示を、イベントの取得で遅らせない（最初の一覧は待たずに出す）
- イベントの取得の失敗が、通知の取得や表示に影響しない

**Non-Goals:**

- 未読の間に起きた複数のイベントをすべて出すこと（`updated_at` に近い 1 つだけ）
- ユーザー自身の操作を除くこと（自分の操作でスレッドが未読になることは通常ない）
- Diagnostics にイベントの取得の状態を出すこと

## Decisions

### 1. Issue と Timeline の REST API で、`updated_at` を基準に決める

`GET /repos/{o}/{r}/issues/{n}`（作成日時と作成者）と `GET .../issues/{n}/timeline` を使う。Pull request も Issue の番号で取れる。

- 代替: GraphQL の `timelineItems(last:)` は 1 リクエストで済み Discussion にも使えるが、GraphQL のエンドポイント（ホスト種別ごとに `/graphql` と `/api/graphql`）とオリジン検査を新しく足すことになり、ユーザーと相談して見送った
- 代替: Issue の状態（open / closed / merged）と `latest_comment_url` だけを使う方法は、リクエストは少ないが「今回の更新が何だったか」が分からない
- イベントは Timeline の最後ではなく、`updated_at` の −180 秒〜+60 秒（近さの幅）に入る候補のうち、`updated_at` にいちばん近いものにする（Gitify と同じく近さで選ぶ）。通知は通知を生まない出来事（`cross-referenced` など）の後でも最後の通知の時刻のままなので、基準を付けないと後の出来事を拾う。幅の下側を広く取るのは、`updated_at` がイベントより遅れるため
- 近さの幅に候補が無ければ、遠い候補で代用せずに「無い」にする（Gitify はいちばん近いものを距離に関係なく使う）。`committed` の時刻はコミットの時刻で push の時刻ではないので、作ってから時間を置いて push したコミットのスレッドで、古いコメントなどを拾わないため。その代わり、そうした push は「Pushed commits」と出ずに理由だけになる。rebase して直後に push する場合（Renovate など）は、コミットの時刻が push の直前になるので拾える
- 作成日時 + 60 秒以前の候補を除くことで、Pull request の作成に付随する `review_requested` や作成前のコミットを「Opened」として扱える
- Timeline は古い順にしか返らないので、`per_page=100` の 1 ページ目を取り、`rel="last"` があれば最後のページ、そこに候補が無ければその前のページを取る（最大 3 ページ）。ほとんどのスレッドは 100 件未満で、Issue と合わせて 2 リクエストで済む
- 候補が見つからず、まだ読んでいないページがあり、`updated_at` が作成直後でもないときは、「Opened」と決めつけずに「無い」にする

### 2. 型と置き場所

- `GitHubAPI/ThreadEvent.swift`: `struct ThreadEvent: Hashable, Sendable { let kind: Kind; let actor: String? }`。`Kind` は spec の表の 14 種類の enum（`opened`、`commented`、`approved`、`changesRequested`、`reviewed`、`closed`、`reopened`、`merged`、`readyForReview`、`convertedToDraft`、`reviewRequested`、`assigned`、`pushedCommits`、`forcePushed`）。文字列の `event` は型に残さない
- `GitHubAPI/SubjectState.swift`: `enum SubjectState { case open, draft, merged, closed, closedCompleted, closedNotPlanned }`（Pull request は open / draft / merged / closed、Issue は open / closedCompleted / closedNotPlanned を使う）。Issue のレスポンスの DTO（`created_at`・`user.login`・`state`・`state_reason`・`draft`・`pull_request.merged_at` だけ。`body` は載せない）から決める
- `ThreadDetails: Hashable, Sendable { let state: SubjectState?; let event: ThreadEvent? }`。キャッシュと `NotificationThread` にはこの組を持たせる
- `GitHubAPI/ThreadEventResolver.swift`: Issue の DTO と Timeline のページ（デコード済みの最小限の DTO の配列）と `updated_at` から `ThreadEvent?` を決める純粋関数。DTO は `event`、`created_at`、`submitted_at`、`state`、`actor.login`、`user.login`、`committer.date` だけを持ち、`body` などは型に載せない（コメントの本文をメモリに残さない）
- `GitHubAPIClient.fetchEvent(for:endpoints:token:) async -> ThreadEventFetchResult`。結果は `.found(ThreadDetails)`、`.none`（404 / 410 など。状態もイベントも無い）、`.unauthorized`、`.rateLimited(retryAt:)`、`.failed(FetchFailure)`。URL は `thread.repository` と `thread.subjectNumber`（検証済み）から `apiURL(path:)` で組み立て、`subjectNumber == nil` なら送らずに `.none` を返す。レート制限の判定は既存の `isRateLimited` / `retryAfterSeconds` / `X-RateLimit-Reset` の読み方を共通にして使う
- `LinkHeader` に `lastURL(in:)` を足す（`nextURL` と同じ読み方を `rel` の値で切り替える）
- ログイン名の検証は `GhIdentifier.isValidActor`（`isValidUser`、または末尾の `[bot]` を除いた値が `isValidUser`）を足す
- `NotificationThread` に `var details: ThreadDetails?` を足す（API のデコードでは常に nil）。`Hashable` なので、イベントを付けて知らせ直すと `old?.threads != new.threads` になるが、`NotificationTracker` は `updated_at` が進んでいないスレッドを新着にしないので、通知は出し直されない（テストで確かめる）
- 表示の文言は `UI/ThreadEventText.swift`（`ThreadReason` と同じ形の enum）に置き、`ThreadRow` と `ThreadNotificationContent` の両方が使う
- 行のアイコンは `ThreadRow.symbol` を種類と状態から決める形に変える。記号は形で区別できるものを選ぶ（案: Pull request は open が `arrow.triangle.pull`、draft が `circle.dashed`、merged が `arrow.triangle.merge`、closed が `xmark.circle`。Issue は open が今の `smallcircle.filled.circle`、completed が `checkmark.circle`、not planned が `slash.circle`）。色は GitHub に合わせて open を緑、merged と completed を紫、closed（Pull request）を赤、draft と not planned を灰色にする。macOS 26 にその記号があるかは実装のときに SF Symbols で確かめ、無ければ形の違う別の記号にする。`accessibilityLabel` に種類と状態を入れる

### 3. `AccountPoller` での取得

`Polling/ThreadEventCache.swift` に、キャッシュと「待っている」スレッドの選び方を値型で置く（`HiddenThreads` と同じく、actor の中で `inout` で使う）。

- `entries: [threadID: (updatedAt, ThreadDetails?)]`。「無い」も nil として入れる。一時的な失敗・認証の失敗は入れない
- `pausedUntil: Date?`（レート制限）
- `previous: [threadID: updatedAt]`（前に知らせた一覧。新着の判定に使う。最初の一覧の前は nil）
- `attach(to threads:) -> [NotificationThread]`: ID と `updated_at` が一致する分を付ける
- `pending(in threads:, newOnly:, limit:)`: 番号を持ち、キャッシュに無いスレッドを更新日時の新しい順に選ぶ

ループの流れ（`run` の中）:

1. `fetch(with:)` が `.updated` を返したら、`handle` の前に `prefetchNewThreadEvents(threads, token:)` を呼ぶ。`previous` があるときだけ、新着のうち待っている最大 10 件を取る。`withTaskGroup` で同時 4 件まで、全体を 20 秒で打ち切る（打ち切りは `Task.sleep` の子タスクと競わせ、終わらなかった分は結果を捨てる）。`Task.isCancelled` なら結果を捨てる
2. `handle` が `state.threads` に一覧を入れるところで、キャッシュを付け、`previous` を更新し、一覧に無い ID をキャッシュから捨てる
3. `.wait` で待ち始める前（`announceNextFetch` の前）に `fillEvents(token:)` で、待っているものを最大 30 件取り、取れたものがあれば今の `state.threads` に `attach` して `publish` する。今の `state.threads` に付けるので、取っている間に `perform` / `markAllRead` で外したスレッドは戻らない
4. `stop(as:)` でキャッシュを空にする。`resume` で作り直したループでは `previous` も捨てる（次の一覧を最初の一覧として扱う）

レート制限が返ったら `pausedUntil` を立て、残りのスレッドは送らずに待っているまま残す。`state.phase`、`consecutiveFailures`、`recorder` には触れない。

actor / スレッドの境界: イベントの取得は `AccountPoller` の actor の上で始め、`withTaskGroup` の子タスクの中で `GitHubAPIClient`（`Sendable` の値）を呼ぶ。結果はグループから actor に戻してからキャッシュに入れる。`NotificationStore` と `ThreadChangeDispatcher` は `@MainActor` のまま変えない。

- 代替: `NotificationStore` 側（`@MainActor`）で取る案は、トークンとクライアントを持つのがポーラーなので、トークンの流れが広がる。採らない
- 代替: 新着の通知だけをイベントの取得まで遅らせる（一覧は先に出す）案は、`ThreadChangeDispatcher` に「保留中」の状態が増えて複雑になる。新着は少なく待ちも短いので、一覧ごと待つ方を採る

### 4. テストでの差し替え

ネットワークは今までどおり `HTTPTransport` のプロトコルで `FakeHTTPTransport` に差し替え、URL のパスで `/notifications`・`/issues/<n>`・`/timeline` に応答を振り分ける。Timeline の応答の JSON を作るヘルパーを `FakeHTTPTransport` に足す。20 秒の打ち切りは、`AccountPoller` に打ち切りの時間を引数で渡し、テストでは短くする（同期的な待ちは使わず、`pausedMethod` と同じく async で止める）。gh サブプロセスには触れない。

## セキュリティ

トークンの流れ:

- 取得: 今までどおり `TokenProviding.currentToken(for:)`（`gh auth token` の標準出力から取ったものをメモリに持つ）。イベントの取得はトークンが無ければ行わない
- 保持: `AccountPoller` の中で、取得の間だけ引数として持つ。イベントのキャッシュにはトークンを入れない（イベント名とログイン名だけ）
- 送り先: `GitHubAPIClient.send` だけが `Authorization` を付ける。URL は検証済みのリポジトリ名と番号から `apiURL(path:)` で組み立て、`Link` の `rel="last"` の URL も `isAllowedRequestURL` を通す（`/repositories/<id>/...` も API ベースの下なので通る）
- 破棄: 今までどおり（アカウントの削除・無効化・終了でトークンを捨てる）。イベントのキャッシュは止まったときとポーラーを捨てたときに消える

`.claude/rules/security.md` への対応:

- トークンの扱い: 新しくトークンを保持する場所は作らない。ログには `print` を使わず、今の `Logger` の書き方（パスと状態コードだけ、可変値は `.private`）に従う。Timeline のボディ（コメントの本文を含む）はログに出さず、DTO にも載せない。テストのトークンは `test-token`
- gh サブプロセス: 触れない
- ネットワーク: オリジン検査は `send` の既存の検査をそのまま通る。リダイレクトは失敗にする（既存）。`subject.url` は URL として使わず、番号の検証にだけ使う。キャッシュは使わない（既存の `URLSession` の設定）
- API レスポンスの値を表示する: 出すのは enum のイベント名と、検証を通ったログイン名だけ。知らない `event` を出さない
- アプリとビルドの設定、依存とサプライチェーン: 変更なし

## Risks / Trade-offs

- [新着の一覧の表示がイベントの取得の分だけ遅れる] → 新着だけ・最大 10 件・同時 4 件・20 秒で打ち切る。最初の一覧は待たない
- [API の消費が増える] → `updated_at` が変わったスレッドだけ、通常 1 スレッド 2 リクエスト。最初の一覧の 500 件でも 30 件ずつ（1 回の取得あたり最大 60〜120 リクエスト）に分かれる。レート制限ならイベントだけ止める
- [`updated_at` とイベントの時刻のずれで違うイベントを拾う、または拾えない] → 実測の遅れ（最大 36 秒）に余裕を足して −180 秒〜+60 秒にする。外れても表示が少し違うか理由だけになるだけで、通知の取得には影響しない
- [時間を置いて push したコミットは Pushed commits と出ない] → 誤ったイベントを出すよりは理由だけを出す方を取る。force-push は push の時刻を持つので出る
- [Timeline が長く、最後の 2 ページに候補が無い] → 「無い」にして理由だけを出す（誤って Opened にしない）
- [Timeline の 1 ページ（100 件）のボディが大きい] → 既存の 5 MB の上限で、超えたら一時的な失敗として扱う
- [`closed` と `merged` の並びが変わる] → `closed` の時刻の 60 秒前からその時刻までの `merged` を探す（同時刻なら順序が逆でも拾えるよう、時刻で比べる）
