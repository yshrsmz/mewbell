# Tasks

## 1. ポーラー

- [x] 1.1 `AccountPoller` の待ちを、起こせる待ちにする（design.md D1）。`sleepTask` と `lastFetchStartedAt` を持ち、ループの停止では今までどおり抜け、起こされたときは前の取得の開始から 10 秒までの残りを待ってから次の取得に進む。確認: `PollingTests` などの既存のテストがそのまま通る。停止（`stop()`）で待ち中のループが抜けるテストが通る
- [x] 1.2 `fetchNow()` と待ち手（`fetchWaiters`）を足す（D2）。確認: `PollerFixture` で次のテストを足して通す: (a) 待っているときに呼ぶと、すぐ `If-Modified-Since` なしの `GET` が送られ、その取得が終わると戻る、(b) 前の取得の開始から 3 秒で呼ぶと、残りの 7 秒を待ってから送られる（`ManualSleeper.durations` で見る）、(c) 取得の途中（`pausedMethod`）で呼ぶと、その取得の後にもう 1 回、10 秒の下限を守って条件なしで送られ、その取得の後で戻る、(d) レート制限で待っているときは送らずにすぐ戻り、次の取得は条件なしになる、(e) 止まっているときはすぐ戻る、(f) 待ち手がいる間に `stop()` すると戻る、(g) 401 でトークンを取り直してやり直すときは、やり直しが終わってから戻る、(h) 押した後の成功からは、また `X-Poll-Interval` と 60 秒の大きいほうだけ待つ

## 2. ストアと UI

- [x] 2.1 `NotificationStore.refresh()` と `isRefreshing` を足す（D3）。印 → 再開 → 全ポーラーの `fetchNow()` を並べて待ち、終わったら下ろす。`isRefreshing` の間は何もしない。確認: `NotificationStore` のテストで、(a) 押すとすぐ全アカウントの `GET` が送られ、全部終わるまで `isRefreshing` が立つ、(b) 1 つのアカウントの取得が失敗しても下りる、(c) 止まっていたアカウントは再開の最初の取得まで待つ、(d) 立っている間の 2 回目は何も送らない、(e) `stopAll()` で下りる
- [x] 2.2 再読み込みボタンを `refresh()` に替え、押した反応のボタンスタイルと、読み込み中の表示（`ProgressView`、固定の枠、`accessibilityLabel("Reloading")`）を入れる。`help` の文言を直す（D4）。確認: SwiftUI プレビュー（読み込み中と通常の 2 つ）を足し、ビルドが通る。手元の確認は 4.3

## 3. ドキュメント

- [x] 3.1 CLAUDE.md の「ポーリングは API の指示に従う」と README の「通知の取得」に、再読み込みのときだけすぐ取り直すこと（10 秒に 1 回まで、レート制限中は早めない）を書き足す（D5）。確認: 差分を読む

## 4. 最終確認

- [x] 4.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [x] 4.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 4.3 手元で起動して確認した: (a) 再読み込みを押すとボタンが押した反応を見せ、読み込み中の表示に替わって、取得が終わると戻る、(b) 押した直後に `log show` で `Fetching ... without If-Modified-Since` が出る（次の予定を待たない）、(c) 続けて押しても 10 秒より短い間隔では取得しない、(d) Web で 1 件既読にしてから押すと、すぐ一覧から消える

## 5. 別コンテキストでのレビュー

- [ ] 5.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 5.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 5.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認を PR 本文に書いた
