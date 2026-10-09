# Design

## Context

再読み込みボタン（`MenuBarContentView`）は今、次の 3 つを呼ぶだけで、取得の完了は待たない。

1. `AccountStore.reload(userInitiated: true)`: gh とアカウントの読み直し（`isReloading` の間はボタンを押せない）
2. `NotificationStore.requestUnconditionalFetch()`: 止まっていないポーラーの `unconditionalRequested`（`Atomic<Bool>`）を立てる
3. `NotificationStore.resumeStopped()`: 止まっているポーラーを `resume()` で起動し直す（トークンを取り直してから取得）

`AccountPoller` のループは、取得 → `handle` → `try await sleep(delay)` を繰り返す。`sleep` は注入された `Sleep`（本番は `Task.sleep`、テストは `ManualSleeper`）で、ループのタスクを止めるとキャンセルで抜けて終わる。待ちを途中で起こす手段は無い。

`fix-stale-notification-list` の D2 で「ループを起こし直さない」と決めたが、押しても何も変わらないように見えるので、この change で変える。

## Goals / Non-Goals

**Goals:**

- 再読み込みを押すと、取得を続けているアカウントがすぐ条件なしで取得する
- 押したことによる取得は、アカウントごとに 10 秒に 1 回まで。レート制限中は早めない
- 押してから、読み直しと各アカウントの取得が終わるまで、ボタンの位置に読み込み中の表示を出す

**Non-Goals:**

- ポップオーバーを開いたときに取得を早めること
- 取得中であることを、再読み込みを押していないとき（定期の取得）にも表示すること
- 読み直しで新しく現れたアカウントの最初の取得を、読み込み中の表示で待つこと（新しいアカウントの区画には、もともと最初の取得中の表示が出る）

## Decisions

### D1. ループの待ちを、起こせる待ちにする

`AccountPoller` の待ちを次の形にする。

- `sleep(delay)` を子のタスク（`sleepTask`）で走らせ、ループは `withTaskCancellationHandler` でその完了を待つ。ループが止められたら子も止める（今までどおりループを抜ける）
- `wake` は `sleepTask` だけを止める。ループは「自分が止められていない」ことを `Task.isCancelled` で確かめ、止められていなければ待ちを終えたものとして次へ進む
- 起こされた後は、前の取得を始めた時刻（`lastFetchStartedAt`）から 10 秒（`minimumUserFetchInterval`）たっていなければ、残りの時間だけもう一度待つ（この待ちは起こせない）。時刻は注入した `now` で測る

ループの外から待ちを起こすのは actor のメソッド（`fetchNow()`）にする。`sleepTask` は actor の状態なので、ループが待っている間（actor は空いている）に入れる。

代わりの案:

- (a) ループごと止めて、`run` を作り直す（`resume()` と同じ）。取得の途中で押されると、その取得の結果を捨てることになり、`fetchCount` や隠しているスレッドの扱いとも絡むので採らない
- (b) `AsyncStream` で「起きろ」を送り、`sleep` と競争させる。待ちごとに `TaskGroup` が要り、(D1) より大きくなる

### D2. `fetchNow()` は押したことによる取得の終わりを待つ

`AccountPoller` に `func fetchNow() async` を足す。

1. `unconditionalRequested` を立てる
2. 状態が止まっている（`isStopped`）か、レート制限で待っている（`.retrying(rateLimited: true)`）なら、すぐ戻る（印だけ残るので、次の取得は条件なしになる）
3. 「この取得番号以降の取得が終わったら起こす」待ち手（`CheckedContinuation`）を `fetchWaiters` に足す。番号は、取得中なら今の取得の次（`fetchCount`）、待っているなら次に始める取得（`fetchCount`）。どちらも `fetchCount` でよい（取得中は、もう `fetchCount` を進めてある）
4. 待っているなら `sleepTask` を止めて起こす。取得中なら何もしない（取得が終わった後の待ちに入ったところで、待ち手があれば起こさずに 10 秒の下限だけ待つ）
5. 待ち手が起こされるまで待つ

ループは `handle` の後（状態を publish した後）に、終わった取得の番号以上を待っている待ち手を起こす。`retryNow`（401 でトークンを取り直してすぐやり直す）のときは、やり直しの取得が終わるまで起こさない。ループが終わるとき（止めた・止められた）は、残っている待ち手をすべて起こす。止まっているアカウントを `resume()` で起こし直したときの最初の取得も、同じ待ち手で待てる（`resume()` の後に `fetchNow()` を呼ぶ）。

取得中に押されたときの「終わった後にもう 1 回」は、待ちに入るときに待ち手があるかで決める。待ち手がいて、その待ち手の番号の取得をまだ始めていなければ、`delay` の代わりに 10 秒の下限までの残りだけ待つ。

### D3. `NotificationStore.refresh()` と読み込み中の状態

再読み込みボタンの処理を `NotificationStore.refresh()`（`@MainActor`）にまとめる。

- `isRefreshing: Bool`（`@Observable` で見せる）を立てる
- `requestUnconditionalFetch()` と `resumeStopped()` を今までどおりの順で呼ぶ（止まっているアカウントに印を立てないため、再開より先に印）
- `Task` の中で、そのときのポーラーすべてに `fetchNow()` を `withTaskGroup` で並べて呼び、すべて戻ったら `isRefreshing` を下ろす。続けて押されないよう、`isRefreshing` の間は `refresh()` を何もしない

`AccountStore.reload(userInitiated:)` はボタンから今までどおり呼ぶ。ボタンは `store.isReloading || notifications.isRefreshing` の間、読み込み中の表示にして押せなくする。読み直しで新しいアカウントが現れても、`refresh()` を呼んだ時点のポーラーだけを待つ（Non-Goals）。

`stopAll()` や同期でポーラーを止めたときは、D2 のとおり待ち手が起こされるので、`isRefreshing` が立ったままにはならない。

### D4. ボタンの見た目

- 押した反応: 今の `.borderless` は押しても見た目がほとんど変わらないので、押している間に背景を付けるボタンスタイル（小さな `ButtonStyle`、`configuration.isPressed` で背景の不透明度を変える）にする。ホバーでも薄く背景を付ける
- 読み込み中: アイコンの代わりに `ProgressView().controlSize(.small)` を同じ大きさの枠に出す（枠の大きさを固定し、ヘッダーの高さを変えない）。`accessibilityLabel("Reloading")` を付ける。回る表示を必須にはしない（spec は「読み込み中と分かること」）が、標準のインジケーターを使う
- `help` の文言を「gh の読み直し、止まったアカウントの再開、すぐの取り直し」に直す

### D5. CLAUDE.md の約束を書き足す

「ポーリングは API の指示に従う」に「ユーザーが再読み込みを押したときだけは間隔を待たずに取り直す（アカウントごとに 10 秒に 1 回まで、レート制限中は早めない）」を足す。README の「通知の取得」も合わせる。

## スレッドとアクター

- 待ち（`sleepTask`）、待ち手（`fetchWaiters`）、`lastFetchStartedAt` は `AccountPoller`（actor）の中だけで読み書きする。`fetchNow()` は actor のメソッドで、ループが `await` している間に入る（actor の再入）
- `unconditionalRequested` は今までどおり `nonisolated` の `Atomic<Bool>`
- `NotificationStore.refresh()` と `isRefreshing` は `@MainActor`。`fetchNow()` を待つ `Task` は `@MainActor` を継承し、終わったら `isRefreshing` を下ろす
- `SWIFT_APPROACHABLE_CONCURRENCY` のため、テストの fake で同期的に待たない。`ManualSleeper` はキャンセルで抜ける作りなので、そのまま使える

## テストでの差し替え

- ネットワークは今までどおり `HTTPTransport`（`FakeHTTPTransport`）。取得の途中で押す場合は `pausedMethod` で応答を止める
- 待ちは `Sleep`（`ManualSleeper`）、時刻は `now`（`PollerFixture.clock`）で差し替える。起こされた待ちはキャンセルで終わるので、`ManualSleeper` の `durations` で 10 秒の下限の待ち（残りの秒数）を確かめられる

## セキュリティ

- トークンの流れ: 変えない。トークンは `TokenProviding`（gh から取得してメモリに持つ）からリクエストごとに取り出し、`GitHubAPIClient` が `Authorization` に付けて、アカウントの API ベース URL にだけ送る。永続化しない。止まっているアカウントの再開で gh から取り直すのも今までどおり
- ネットワーク: 送るのは今までどおりの `GET /notifications` で、送る時刻が早まるだけ。オリジン検査・リダイレクトの拒否・キャッシュを使わないことは `GitHubAPIClient` / `URLSessionTransport` のまま変えない
- gh サブプロセス、URL を開く処理、ログ、通知の本文: 触れない。新しいログを足すなら、可変値は `.private` のままにする
- API の利用量: 押したことによる取得はアカウントごとに 10 秒に 1 回まで。レート制限中は早めないので、`Retry-After` / `X-RateLimit-Reset` の指示は守る

## Risks / Trade-offs

- [GitHub の `X-Poll-Interval` の指示より早く叩く] → ユーザーが押したときだけで、10 秒の下限を付ける。Gitify など他のクライアントも手動の取り直しはすぐ行う。レート制限中は早めない
- [取得がタイムアウトまで返らないと、読み込み中の表示が長く続く] → `URLSession` のタイムアウトで終わる。その間もボタンが押せないだけで、一覧の操作はできる
- [待ちを子のタスクにする分、ループの抜け方が複雑になる] → ループの停止（キャンセル）と起こす（子だけのキャンセル）を `Task.isCancelled` で区別し、両方をテストで確かめる
