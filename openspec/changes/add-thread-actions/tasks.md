# Tasks

## 1. ドキュメントの準備

- [x] 1.1 `SETUP.md` の M4 の行を `add-thread-actions`（既読・Done・すべて既読）と `add-settings`（Settings シーン、participating の切替、アカウントの ON/OFF、ログイン時起動、gh のパスの上書き、Diagnostics）の 2 行に分ける。確認: 差分を読み、元の M4 の要点がどちらかの行に入っている

## 2. Done とすべて既読のリクエスト（GitHubAPI）

- [x] 2.1 `MarkReadResult` を `ThreadActionResult`（`.succeeded` など）に改名し、状態コードの分類を `classifyAction(_:success:)` にまとめる。`send` に `body: Data?` を足し、ボディがあるときだけ `httpBody` と `Content-Type: application/json` を付ける（D2）。確認: 既存の `MarkThreadReadTests` と `GitHubAPIClientTests` が、改名に合わせた修正だけで通る。`GET` と `PATCH` に `Content-Type` が付かない
- [x] 2.2 `markThreadDone(endpoints:token:threadID:)` を実装する。確認: テストを足して通す: (a) `DELETE https://api.github.com/notifications/threads/123` が `Authorization`・`Accept`・`X-GitHub-Api-Version`・`User-Agent` 付きで送られる、(b) GHE Cloud では `https://api.acme.ghe.com/notifications/threads/77`、(c) `204`・`404` は `.succeeded`、`401` は `.unauthorized`、`403`（`X-RateLimit-Remaining: 0`）と `429` は `.rateLimited`、`205`・`422`・`500` は `.failed`、(d) `307` はリダイレクトとして失敗し、`Location` のホストには送らない、(e) 数字でない ID では何も送らない
- [x] 2.3 `markAllRead(endpoints:token:lastReadAt:)` を実装する（`Encodable` のボディ、`last_read_at` は UTC の `YYYY-MM-DDTHH:MM:SSZ`）。確認: テストを足して通す: (a) `PUT https://api.github.com/notifications` に `Content-Type: application/json` と、`{"last_read_at": "2026-10-09T12:34:56Z", "read": true}` と読めるボディが付く、(b) ボディにトークンの文字列（`test-token`）が含まれない、(c) GHES では `https://ghe.example.com/api/v3/notifications`、(d) `202`・`205`・`304` は `.succeeded`、`401` は `.unauthorized`、`403`（`Retry-After: 60`）は `.rateLimited`、`422`・`500` は `.failed`、(e) `302` は失敗

## 3. ポーラーでの操作（Polling）

- [x] 3.1 `AccountPoller.markRead(threadID:)` を `perform(_ action: ThreadAction)`（`.read` / `.done`）に一般化する（D3）。確認: 既存の `MarkReadPollingTests` が `.read` で通る。テストを足して通す: (a) `.done` で一覧からすぐ外れ、`DELETE` が送られ、次の取得に `If-Modified-Since` が付かない、(b) `DELETE` が `500` のとき、次の取得で返ったスレッドが一覧に戻る、(c) `DELETE` の応答を止めている間（`pausedMethod = "DELETE"`）に終わった取得が同じスレッドを返しても戻らない、(d) 同じスレッドに `.read` と `.done` を続けて行い、片方だけが終わった後の取得では戻らない、(e) 止まっているときは送らない
- [x] 3.2 `AccountPoller.markAllRead(through:)` と `readThroughs` を実装し、`revealOrHide` と `stop(as:)` に組み込む。取得の開始時刻を取得の連番と一緒に覚える（D4）。確認: テストを足して通す: (a) `updated_at` が 12:00 と 12:30 の一覧で呼ぶと、一覧が空になって `onUpdate` が呼ばれ、`last_read_at` が 12:30 の `PUT` が送られる、(b) 次の取得に `If-Modified-Since` が付かない、(c) `202` の後の取得が 12:00 と 12:45 を返すと、12:45 だけが残る、(d) `now` を 5 分以上進めた後に始めた取得では 12:00 が戻る、(e) `PUT` が通信の失敗のとき、その後に始めた取得で 12:00 と 12:30 が戻る、(f) `PUT` の応答を止めている間に終わった取得からも 12:00 と 12:30 が除かれる、(g) 一覧が空・止まっている・トークンが無いときは何も送らず一覧も変えない、(h) 1 回目の `PUT` の応答を止めたまま 2 回目を呼び、1 回目が失敗で終わっても 2 回目の除外が続く、(i) どの場合も取得の待ち時間（`sleep` に渡る値）が変わらない
- [x] 3.3 `NotificationStore` に `markRead(_:in:)`、`markDone(_:in:)`、`markAllRead(in:)` と `FeedState.canMarkAllRead` を足し、`open` と `openFromNotification` を同じ経路に通す。`ThreadNotifying.threadRead` を `threadRemoved` に改名する（D5、D6）。確認: 偽の `PollerFactory` でテストを足して通す: (a) `markDone` で `feeds` からすぐ外れ、`threadRemoved` とポーラーの `perform(.done)` が呼ばれ、URL は開かれない、(b) `markRead` も同じで `perform(.read)`、(c) `markAllRead` の後、ポーラーの `publish` で `feeds` が空になる、(d) `FeedState.canMarkAllRead` は `.loaded` で 1 件以上のときだけ true（`.retrying`・`.loading`・0 件・止まっているときは false）、(e) 既存の `NotificationStoreOpenTests` が通る

## 4. macOS の通知（Notifications）

- [x] 4.1 すべて既読と Done で通知が取り下がることを確かめる（D6。コードは 3.3 の改名だけのはず）。確認: 偽の `UserNotificationCenter` でテストを足して通す: (a) `alice` の 2 件と `bob` の 1 件の通知がある状態で、`alice` の `feedChanged` が空の一覧で届くと `alice` の 2 件だけが `remove` される、(b) `threadRemoved` でそのスレッドの通知が `remove` され、`NotificationTracker` の今の一覧からも外れる（同じスレッドが次の取得で返っても、`updated_at` が同じなら出し直さない）

## 5. UI

- [x] 5.1 `ThreadRow` に `.overlay` のホバーのボタン（`ThreadActionButtons`）と `.contextMenu`（Open in Browser / Mark as Read / Mark as Done）を足し、`open`・`markRead`・`markDone` を `AccountSectionView` と `NotificationListView` を通して `NotificationStore` に渡す（D7）。確認: プレビューでホバーのボタンの見た目を見る（件名が長い行で、行の高さが変わらない）。行の操作のボタンのクリックで行が開かないことは 6.3 で確かめる。結果: Xcode の RenderPreview は未承認で使えず、一時テストの `ImageRenderer` で描いた。ホバーの有無で行の高さが変わらないことは見えたが、`ImageRenderer` は `Button` をプレースホルダーで描くので、ボタンの見た目は 6.3 で見る
- [x] 5.2 `MarkAllReadButton` を作り、アカウントの見出しに置く（D8）。押せる条件は `FeedState.canMarkAllRead`。確認: プレビューに「通常」「確認中（`Mark 3 as read?`）」「押せない」を並べて見る。5 秒で戻ること、閉じると戻ることは 6.3 で確かめる。結果: 5.1 と同じく `ImageRenderer` では `Button` を描けず、見出しの右端に置かれることだけを見た。見た目は 6.3 で見る
- [x] 5.3 README の現状の説明を更新する（一覧から既読・Done・すべて既読ができること）。確認: 差分を読み、CLAUDE.md の約束と食い違いが無い

## 6. 最終確認

- [x] 6.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [x] 6.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 6.3 手元で起動して確認した: (a) 行にマウスを載せるとボタンが出て、外すと消える、(b) 「Mark as read」でブラウザが開かずに一覧・バッジ・通知センターから消え、Web でも既読になっている、(c) 「Mark as done」で同じく消え、Web の受信箱からも消えている、(d) 右クリックのメニューの 3 つが動く、(e) 「すべて既読」は 1 回目で確認の表示になり、5 秒で戻る。ポップオーバーを閉じても戻る。2 回目でそのアカウントの一覧が空になり、ほかのアカウントは変わらない。Web でも既読になっている、(f) 次の取得の後も、既読・Done にしたスレッドが戻らない。`log show` でトークンとレスポンスボディ・リクエストボディが出ていないことも見る

## 7. 別コンテキストでのレビュー

- [x] 7.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 7.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 7.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認を PR 本文に書いた
