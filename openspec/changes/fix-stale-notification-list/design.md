# Design

## Context

`AccountPoller`（actor）は、最後に全ページを取り終えた `200` の `Last-Modified` を `lastModified` に持ち、毎回の 1 ページ目に `If-Modified-Since` として付けている。GitHub はこの値を「未読スレッドの `updated_at` の最新値」として返すので、古い `updated_at` のスレッドが後から未読になっても、ほかの場所で既読になっても `304` が返り続け、一覧が直らない（proposal）。

再読み込みボタンは `AccountStore.reload(userInitiated:)` と `NotificationStore.resumeStopped()` を呼ぶ。`resumeStopped()` は止まっているアカウントだけを再開し、続いているポーラーには何もしない。

## Goals / Non-Goals

**Goals:**

- 一覧のずれが、何もしなくても最大でおよそ 5 分（と次の取得までの間隔）で直る
- 再読み込みを押すと、次の取得でずれが直る
- 取得の間隔（`X-Poll-Interval`、下限 60 秒）は今までどおり守る。再読み込みで取得を早めない

**Non-Goals:**

- `If-Modified-Since` をやめること。条件付きリクエストの `304` はレート制限に数えられないので、普段は使い続ける
- 既読化（`PATCH /notifications/threads/{id}`）。M3 で扱う
- 5 分の間隔を設定で変えられるようにすること

## Decisions

### D1. 条件なしにするかはポーラーが取得の直前に決める

`AccountPoller` に次の 2 つを持たせる。

- `lastFullFetch: Date?`: 最後に `200` で全ページを取り終えた時刻（条件付きでも `200` なら一覧はすべて取り直されるので、条件の有無は問わない）
- `unconditionalRequested`: 次の取得を条件なしにする印（再読み込みで立てる）

取得の直前に印を読んで下ろし、印が立っていたか、`lastFullFetch` が無いか 5 分以上前なら（時計が戻って差が負になったときも） `If-Modified-Since` を付けない。`lastModified` が nil のとき（最初の取得、トークンの取り直しの後、止めた後）は、もともと条件なしになる。`lastModified` と `lastFullFetch` はどちらも `updated` で入るので、トークンの取り直しや停止で `lastModified` を消せば、`lastFullFetch` を消さなくても次は条件なしになる。

`updated` を受け取ったら、条件の有無にかかわらず `lastFullFetch = now()` にする。取り終えられなかったときは時刻を変えないので、5 分を過ぎた分の取得は次もまた条件なしになる。印を立てた取得が取り終えられなかったときは、印を立て直す。印を送る前に下ろすのは、取得の途中で押された再読み込みを、その前に始めた取得の成功で消さないため。

判断をポーラーの中に閉じ込めるのは、`lastModified` と同じ actor の状態で、取得のループだけが読み書きするから。時刻は今ある `now` を使うので、テストでは固定できる。スリープから戻ったときも、壁時計の差で判断するので 5 分を過ぎていれば条件なしになる。時計が戻って差が負になったときも条件なしにする（戻った分だけ取り直しが遅れないように）。

代わりの案:

- (a) 5 分ごとに `lastModified = nil` にするタイマーを別に走らせる。ループが 2 つになり、取り合いを考える必要が出るので採らない
- (b) 条件なしの取得を「N 回ごと」で数える。`X-Poll-Interval` が変わると時間がずれるので、時刻で判断する

### D2. 再読み込みからの指示はロックで渡す

`AccountPoller` に `nonisolated func requestUnconditionalFetch()` を足す。`nonisolated` の `Atomic<Bool>` で印を持ち、ループが取得の直前に `exchange(false)` で読んで下ろす。`@MainActor` の `NotificationStore` から、`await` も `Task` も作らずに呼べる。

ループを起こし直す（sleep を途中で止める）ことはしない。印を立てるだけなので、取得は次の予定の時刻に行われ、間隔より早まらない。

`NotificationStore` には `requestUnconditionalFetch()` を足し、ポーラーすべてに伝える。止まっているポーラーに印が残っても害はない（再開時はトークンを取り直して `lastModified` が消えるので、どのみち条件なしになる）。再読み込みボタンは、`resumeStopped()` に続けてこれを呼ぶ。止まっていたアカウントは `resume()` でトークンを取り直すので、`lastModified` が消えて、もともと条件なしになる。

### D3. CLAUDE.md の約束を書き足す

CLAUDE.md の「ポーリングは API の指示に従う」に「5 分ごとと再読み込みの後は `If-Modified-Since` を付けずに取り直す（`Last-Modified` が未読の `updated_at` の最新値なので、古いスレッドの増減を `304` が隠すため）」を足す。

## スレッドとアクター

- 判断と状態（`lastModified`、`lastFullFetch`）は `AccountPoller`（actor）の中だけで読み書きする
- 再読み込みの印は `nonisolated` の `Atomic<Bool>` に置き、`@MainActor` の `NotificationStore` から同期的に立てる。読むのはポーラーのループだけ
- ネットワークは今までどおり `GitHubAPIClient` が `HTTPTransport` 経由で送る。テストは `FakeHTTPTransport` で `If-Modified-Since` の有無を確かめ、時刻は `now` の差し替え、待ちは `ManualSleeper` で進める

## セキュリティ

- トークンの流れは変えない。gh から取り、`CredentialStore`（actor）のメモリにだけ持ち、取得ごとに `GitHubAPIClient` がそのリクエストにだけ付ける。終了時と 401 のときに捨てる
- 送り先は今までどおり、アカウントの API ベースの `GET /notifications` と、オリジン検査を通った `Link` の続きのページだけ。変わるのは `If-Modified-Since` を付けるかどうかだけ
- リダイレクトの拒否、キャッシュなし、ATS の例外なし、ログの `.private` は変えない。新しいログは「条件なしで取得する」ことだけを、アカウントを `.private` にして残す
- gh サブプロセス、URL を開く処理、`hosts.yml` の解析には触れない

## Risks / Trade-offs

- ずれは最大で 5 分と次の取得までの間隔ぶん残る → 再読み込みを押せば次の取得で直る。M3 でアプリから既読にしたスレッドは、アプリ側の一覧から直接消す
- 条件なしの取得はレート制限に数えられる → アカウントあたり 1 時間に 12 回ほどで、上限 5,000 回に比べて小さい
- 再読み込みを押しても、すぐには直らない（間隔を守るため）→ 次の取得の時刻は一覧の状態表示に出ているので、待てば直る
