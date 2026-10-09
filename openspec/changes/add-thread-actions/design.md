# Design

## Context

M3 の時点の構成（動機は proposal.md の Why、満たすべき振る舞いは `specs/github-api`、`specs/polling`、`specs/notifications`、`specs/ui`）:

- `GitHubAPIClient`（状態なしの struct）の `send(_:method:endpoints:token:ifModifiedSince:)` が、トークンを付ける唯一の場所。オリジン検査（`APIEndpoints.isAllowedRequestURL`）とリダイレクトの失敗扱いもここで掛かる。リクエストのボディを渡す口は無い
- 既読化は `GitHubAPIClient.markThreadRead` → `MarkReadResult`（`.read` / `.unauthorized` / `.rateLimited` / `.failed`）
- `AccountPoller`（actor）の `markRead(threadID:)` が、一覧から外す・`hidden` で取得の結果から隠す・`PATCH` を送る・次の取得を条件なしにする、を受け持つ。`hidden` は「終わっていない既読化の数」か「この番号以降の取得の 200 まで」を持ち、取得には連番（`fetchCount`）を振っている
- `NotificationStore`（`@MainActor @Observable`）の `markRead(_:in:)` は private。`feeds` からすぐ外し、`ThreadNotifying.threadRead` で macOS の通知を取り下げ、ポーラーに頼む。ポーラーがまだ無ければ `pendingReads` に取っておく（通知のクリック用）
- `NotificationStore.apply` は、ポーラーから届いた `FeedState` を `ThreadNotifying.feedChanged(for:from:to:)` に渡す。`SystemNotifier` は `.loaded` → `.loaded` で `threads` が変わると、`NotificationTracker.update` で「今の一覧から消えたスレッド」を取り下げる
- `ThreadRow` は行全体が `Button(.plain)`。中にボタンを入れると、クリックを行のボタンと奪い合う
- `SWIFT_APPROACHABLE_CONCURRENCY` が有効。テストの fake で同期的に待つと actor が塞がる（`FakeHTTPTransport.pausedMethod` で async に止める）

GitHub の前提（GHES 3.13 のドキュメントでも同じ）:

- `DELETE /notifications/threads/{thread_id}` は成功で `204`
- `PUT /notifications` のボディは `last_read_at`（それより後に更新されたものは既読にしない。省略すると今の時刻）と `read`。成功は `205`。件数が多いと `202` を返し、GitHub が後から非同期に既読にする。ほかに `304` / `401` / `403`

## Goals / Non-Goals

**Goals:**

- 既読・Done・すべて既読を、`AccountPoller` の 1 つの「操作の後に一覧から隠す」仕組みに通し、取得との競合の扱いを 1 か所にまとめる
- 新しい 2 つのリクエストも `GitHubAPIClient.send` を通し、トークンを付ける場所を増やさない
- 行の操作と行のクリックが、クリックを奪い合わない作りにする

**Non-Goals:**

- macOS の通知のバナーに「既読」「Done」のアクションボタンを付ける（`UNNotificationCategory`）。必要になったら別の change で扱う
- 操作の失敗をユーザーに知らせる表示。ログに残し、次の条件なしの取得で一覧に戻ることで分かるようにする。Diagnostics（`add-settings`）で扱うかを考える
- リポジトリ単位のすべて既読（`PUT /repos/{owner}/{repo}/notifications`）、複数スレッドの選択
- 取り消し（Undo）。GitHub の API に Done を戻す手段が無い

## Decisions

### D1. モジュールと型の分担

| 置き場所 | 型 | 役割 |
| --- | --- | --- |
| `GitHubAPI/` | `GitHubAPIClient.markThreadDone(endpoints:token:threadID:)`、`markAllRead(endpoints:token:lastReadAt:)` | 新しい 2 つのリクエスト。`send` にボディの引数を足して共有する（D2） |
| `GitHubAPI/` | `ThreadActionResult`（`MarkReadResult` を改名） | 既読・Done・すべて既読で共通の結果。`.succeeded` / `.unauthorized` / `.rateLimited` / `.failed(FetchFailure)` |
| `Polling/` | `AccountPoller.perform(_ action: ThreadAction)`、`markAllRead()` | 一覧から外す・隠す・送る・次の取得を条件なしにする（D3、D4）。`ThreadAction` は `.read(threadID)` / `.done(threadID)` |
| `Polling/` | `NotificationStore.markRead(_:in:)`、`markDone(_:in:)`、`markAllRead(in:)`、`FeedState.canMarkAllRead` | UI からの入り口。既存の `open` と `openFromNotification` も同じ経路に通す（D5） |
| `Notifications/` | `ThreadNotifying.threadRemoved(_:for:)`（`threadRead` を改名） | 既読・Done にしたスレッドの通知を取り下げる。すべて既読は既存の `feedChanged` の差分で取り下がる（D6） |
| `UI/` | `ThreadRow`、`ThreadActionButtons`、`MarkAllReadButton` | 行のホバーのボタンとコンテキストメニュー、見出しの 2 段階のボタン（D7、D8） |

### D2. `send` にボディを渡し、結果の分類を共有する

`send` に `body: Data? = nil` を足し、ボディがあるときだけ `httpBody` と `Content-Type: application/json` を付ける。ほかのヘッダー・オリジン検査・リダイレクトの扱いは変えない。

`markAllRead` のボディは `JSONSerialization` ではなく `Encodable` の小さな struct（`last_read_at: String`、`read: Bool`）を `JSONEncoder` で作る。`last_read_at` は `Date.ISO8601FormatStyle`（UTC、秒まで）で文字列にする。ボディはトークンを含まないが、ログには出さない（パス・ホスト・状態コードだけ。今と同じ）。

3 つの操作の状態コードの分類は、`classifyAction(_ response:, success: Set<Int>)` にまとめる。`401` → `.unauthorized`、`403` に `X-RateLimit-Remaining: 0` か秒数の `Retry-After` がある・`429` → `.rateLimited`、`success` に入る状態コード → `.succeeded`、それ以外 → `.failed(.unexpectedStatus)`。`success` は、既読が `205/304/404`、Done が `204/404`、すべて既読が `202/205/304`。

- 代替案: 操作ごとに結果の enum を分ける → 呼び出し側（ポーラー）が成功かどうかしか見ないので、分ける価値が無い。すべて既読の `202` と `205` を区別する必要も無い（どちらも D4 の「成功」の扱い）

### D3. 既読と Done を同じ「隠す」仕組みに通す

今の `markRead(threadID:)` を `perform(_ action: ThreadAction)` に一般化する。中身は今と同じで、送るリクエストだけを `action` で選ぶ。

- `hidden[threadID]` の `.requestsInFlight(n)` / `.fetch(number)` をそのまま使う。同じスレッドに既読と Done が重なっても、数で数えるので、両方が終わるまで隠し続ける（spec「スレッドの Done」の重なり）
- 止まっている・トークンが無いときは送らずに、隠して印を立てるだけにする（今の既読と同じ）
- 結果が `.succeeded` 以外ならログに残す（`ThreadAction` の種類と結果だけ。スレッド ID は `.private`）

### D4. すべて既読は「時刻で隠す」

すべて既読はスレッド ID の集合ではなく `last_read_at` で決まる（GitHub の側も時刻で既読にする）ので、`hidden` とは別に、ポーラーに 1 つだけ `readThrough: ReadThrough?` を持つ。

```
struct ReadThrough { cutoff: Date; until: Until }
enum Until {
  case requestInFlight          // 結果が出るまで、どの取得の結果からも cutoff 以前を除く
  case fetchesStartedBefore(Date)  // 成功: この時刻（結果 + 5 分）より前に始めた取得の結果から除く
  case fetchesBefore(Int)       // 失敗: この番号より前に始めた取得の結果からだけ除く
}
```

`markAllRead()` の流れ（actor の中）:

1. 止まっている、トークンが無い、`state.threads` が空 → 何もしない（spec: 送らない・外さない）
2. `cutoff = state.threads.map(\.updatedAt).max()`。`readThrough = ReadThrough(cutoff, .requestInFlight)`。`state.threads` から `updatedAt <= cutoff` を外して `publish`
3. `PUT` を送る（`await`。この間も取得は進む）
4. 結果が `.succeeded` なら `.fetchesStartedBefore(now() + 300 秒)`、それ以外なら `.fetchesBefore(fetchCount)`
5. 条件なしの印を立てる

`revealOrHide` で、取得の結果に `hidden` の除外に加えて `readThrough` の除外を掛ける。取得の開始時刻は、`fetch(with:)` の頭で連番と一緒に取っておく。期限が過ぎた・番号を越えた `readThrough` は `revealOrHide` で消す。`stop(as:)` でも消す（止まると一覧が空になり、再開後の最初の取得をそのまま信じてよいため）。

すべて既読が終わる前にもう一度すべて既読が押されたときは、新しい `cutoff`（大きい方）と `.requestInFlight` で上書きする。先に終わった方の結果で `until` を書き換えないように、`readThrough` に通し番号を持たせ、自分の番号のときだけ 4 を行う。

- 5 分の根拠: 条件なしの取得の間隔（`unconditionalFetchInterval`）と同じ。`202` の非同期の処理がそれより長くかかると、残りのスレッドが一度一覧に戻るが、次の取得で消える（Risks）
- 代替案: 成功したら期限なしで除き続ける → GitHub の非同期の処理が失敗したときに、未読のスレッドが二度と一覧に出ない。期限を付ける
- 代替案: 既存の `hidden` に、外したスレッドの ID を全部入れる → `202` の後に「既読化の後に始めた取得の 200」で戻ってしまう。また、ページの上限の外にあって一覧に無かったスレッドは隠せない
- `cutoff` を `Last-Modified` から取る案: `Last-Modified` は直近の 200 の値で、隠しているスレッドを除いた後の一覧とずれることがある。一覧に見えているものの最大値の方が、ユーザーが見たものと一致する

### D5. `NotificationStore` の入り口

- `markRead(_ threadID:, in:)` を `perform(.read(id), in:)` にし、`markDone` を足す。どちらも `feeds` からすぐ外し、`notifier?.threadRemoved` を呼び、ポーラーの `perform` を `Task` で呼ぶ。ポーラーが無いときの `pendingReads` は既読（通知のクリックの経路）のときだけ使い、Done ではポーラーが無ければ何もしない（UI に行が出るのはポーラーがあるときだけ）
- `markAllRead(in:)` は `feeds` を自分では書き換えず、ポーラーの `markAllRead()` を呼ぶだけにする。外した結果はポーラーの `publish` → `apply` で届く（actor への 1 回の往復で、手で外すのと見た目は変わらない）。こうすると「止まっている・トークンが無いときは外さない」の判断がポーラーの 1 か所で済み、`cutoff` もポーラーの状態から取れる
- `FeedState.canMarkAllRead` は `.loaded` で `threads` が空でないとき true。UI のボタンの有効・無効と、`markAllRead(in:)` の前提の確認に使う

### D6. macOS の通知の取り下げ

- 既読・Done: 今の `threadRead` を `threadRemoved` に改名して両方から呼ぶ（取り下げの理由で振る舞いは変わらない）
- すべて既読: ポーラーの `publish` で `.loaded` → `.loaded`（スレッドが減った）が届き、`SystemNotifier.feedChanged` の `NotificationTracker.update` が、消えたスレッドを `retract` に入れて取り下げる。新しい口は作らない
- 代替案: `threadsRemoved(_ ids: Set<String>, for:)` を足して store から直接呼ぶ → `feedChanged` と二重に取り下げることになるだけで、得るものが無い

### D7. スレッドの行（`ThreadRow`）

行のクリックとボタンを奪い合わないように、行の `Button` の中にはボタンを入れず、`Button` に `.overlay(alignment: .trailing)` で操作のボタンを重ねる。重ねたボタンは `Button` より手前にあるので、そこでのクリックは行のクリックにならない。

- ホバーは `.onHover` で `@State isHovering` を切り替え、`true` の間だけ `ThreadActionButtons`（`envelope.open`「Mark as read」と `checkmark`「Mark as done」、`.borderless`、`.help` と `.accessibilityLabel` 付き）を出す。件名の上に重なるので、ボタンの後ろに `.background(.background)` を敷き、件名の折り返しは変えない（ホバーのたびに行の高さが変わらないように）
- `.contextMenu` に「Open in Browser」「Mark as Read」「Mark as Done」を入れる
- `ThreadRow` は `open`・`markRead`・`markDone` の 3 つのクロージャを受け取る。`AccountSectionView` と `NotificationListView` は、それを `NotificationStore` に渡すだけ
- 代替案: `HStack` で行のボタンと操作のボタンを横に並べる → 操作のボタンの幅だけ件名が常に狭くなる。ホバーのときだけ幅を変えると、件名の折り返しが変わって行が跳ねる

### D8. すべて既読のボタン（`MarkAllReadButton`）

見出しの `Spacer` の後ろに置く。`count: Int`、`isEnabled: Bool`、`action: () -> Void` を受け取り、確認の状態は View の `@State` に持つ（ストアに持たない。ポップオーバーを閉じれば消えてよい状態なので）。

- 1 回目: `confirming = true` にし、5 秒後に `false` に戻す `Task` を始める（`.task(id: confirming)` で、`confirming` が変わったら前のものは取り消される）
- 2 回目（`confirming` のまま）: `action()` を呼び、`confirming = false`
- `.onDisappear` で `confirming = false`。`isEnabled` が `false` になったら（`onChange`）`confirming = false`
- 表示: 通常は `checkmark.circle` のアイコン（`help`「Mark all as read」）、確認中は `Mark \(count) as read?` の文字で `.tint` を強める。押せないときは `.disabled`
- アカウントごとに別の View なので、確認の状態はほかのアカウントに広がらない
- 代替案: `confirmationDialog` → `MenuBarExtra` の window スタイルではダイアログの出方とフォーカスが不安定になりうる（2 段階のボタンにすることはユーザーと決めた）

### D9. テストでの差し替え

- ネットワーク: 既存の `FakeHTTPTransport` で、`DELETE` と `PUT` のメソッド・URL・ヘッダー・`httpBody`（JSON を読み直して `last_read_at` と `read` を確かめ、トークンの文字列が含まれないことも確かめる）を見る。状態コードごとの結果、`ThreadID` の拒否、`307` / `302` の拒否、オリジン検査をテストする
- ポーラー: 既存の `PollingFakes`（偽のトークン、`sleep`、`now`）と `FakeHTTPTransport.pausedMethod`（`"PUT"` や `"DELETE"` の応答を止める）で、取得中の操作、`202` の後の取得、5 分の期限（`now` を進める）、失敗の後に戻ること、`If-Modified-Since` が付かないことを確かめる
- `NotificationStore`: 既存の偽の `PollerFactory` で、`markDone` の後の `feeds` と `notifier` の呼び出し、`FeedState.canMarkAllRead` を確かめる
- 通知: 既存の偽の `UserNotificationCenter` で、すべて既読の後の `feedChanged` で取り下がることを確かめる
- UI: ホバーと 2 段階のボタンはプレビューと手元で確かめる。2 段階の状態の遷移は View の中の `@State` なので、ユニットテストはしない

## セキュリティ

トークンの流れ:

- 取得: 変わらない（`gh auth token` の標準出力から `AccountDiscovery` が取得し、`CredentialStore` に入れる）
- 保持: 変わらない（`CredentialStore` の中だけ）。`AccountPoller.perform` と `markAllRead` は、送る直前に `TokenProviding.currentToken` で受け取り、リクエストの組み立てにだけ使う
- 送り先: 今のものに加えて `DELETE <API ベース>/notifications/threads/<id>` と `PUT <API ベース>/notifications`。どれも `GitHubAPIClient.send` を通り、送る前にオリジン検査をする
- 破棄: 変わらない（アカウントの削除・終了時）。操作の失敗（`401` を含む）ではトークンを捨てず、取り直しもしない（取り直しは取得の `401` だけが行う）

security.md の各項目:

- トークンを型で伏せる・ログに出さない: 既存の `AccessToken` をそのまま使う。新しいリクエストのログはメソッド・パス・ホスト・状態コード（`.private`）だけで、`PUT` のボディも出さない。ボディにトークンが入らないことをテストで確かめる
- 共有の `URLSession` にトークンを入れない、キャッシュを使わない、HTTPS のみ: `send` と `URLSessionTransport` の共有で満たす（変更しない）
- オリジン検査: `DELETE` と `PUT` にも掛かることをテストする。スレッド ID は URL のパスに入れる前に `ThreadID.isValid` で確かめる
- リダイレクトの拒否: `DELETE` の `307` と `PUT` の `302` のテストを足す
- URL を開く: 触れない（新しい操作はブラウザを開かない。「Open in Browser」のメニューは既存の `open` を呼ぶ）
- gh サブプロセス: 触れない
- 通知の本文: 変えない
- 永続化: しない。`readThrough` と `hidden` はポーラーの中にだけあり、終了で消える
- Hardened Runtime と entitlement: 変えない

## Risks / Trade-offs

- [`202` の非同期の処理が 5 分より長くかかると、まだ既読になっていないスレッドが一度一覧に戻る] → 次の取得以降で消える。GitHub の処理時間は分からないので、困ったら期限を延ばす
- [すべて既読は、ページの上限（500 件）の外にあって一覧に出ていない古い未読も既読にする] → `last_read_at` より前に更新されたものはすべて対象になるのが GitHub の仕様。ユーザーの意図（そのアカウントを片付けたい）とずれないので受け入れる
- [`add-settings` で `participating=true` の一覧に切り替えると、一覧に出ていない（自分が参加していない）未読もすべて既読になる] → `PUT /notifications` に絞り込みが無いため。`add-settings` の design で、ボタンの説明に出すか、`participating=true` のときは件数の表示を変えるかを決める
- [Done にした後、そのスレッドに新しい動きがあると、GitHub は未読の一覧に戻す] → GitHub の仕様どおり。`updated_at` が進むので、通知も出し直される（M3 の規則のまま）
- [ホバーのボタンが件名の末尾を隠す] → ホバー中だけで、`help` で件名は読める。行の高さは変えない
- [`MenuBarExtra` の window で `.onHover` や `.onDisappear` が期待どおりに呼ばれない] → 手元で確かめる。`.onDisappear` が呼ばれないなら、5 秒の期限だけで戻るので、誤操作の防止は保たれる
- [UI の操作がポーラーを経由するので、すべて既読の見た目の反映に actor の往復の分だけ遅れがある] → 1 フレーム程度で、spec の「すぐに」を満たす

## Migration Plan

保存するデータが無いので、移行は要らない。戻すときは前のビルドに戻せばよい（GitHub の側で Done・既読にしたものは戻らない）。
