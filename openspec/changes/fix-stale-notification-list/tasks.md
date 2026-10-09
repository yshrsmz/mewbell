# Tasks

## 1. ポーラー

- [ ] 1.1 `AccountPoller` に `lastUnconditionalFetch` と、再読み込みの印（`nonisolated` の `Mutex<Bool>`）と `requestUnconditionalFetch()` を足す。取得の直前に D1 の規則で `If-Modified-Since` を付けるかを決め、条件なしの `updated` を受け取ったら時刻を記録して印を下ろす。トークンを取り直したとき・止めたときは時刻も消す。確認: `PollingTests` に次のテストを足して通す（`FakeHTTPTransport` でリクエストの `If-Modified-Since` を見る）: (a) 5 分たつまでは付く、(b) 5 分たった次の取得では付かず、200 で一覧が置き換わる、(c) 条件なしの取得が失敗したら次もまた条件なし、(d) 印を立てても取得は早まらず、次の取得で付かない、(e) 印を立てた後の取得が成功したら、その次はまた付く
- [ ] 1.2 `NotificationStore` に `requestUnconditionalFetch()` を足し、止まっていないポーラーすべてに伝える。再読み込みボタンで `resumeStopped()` に続けて呼ぶ。確認: 止まっていないアカウントのポーラーにだけ伝わるテストが通る

## 2. ドキュメント

- [ ] 2.1 CLAUDE.md の「ポーリングは API の指示に従う」と README の「通知の取得」に、5 分ごとと再読み込みの後は条件なしで取り直すことを書き足す。確認: 差分を読む

## 3. 最終確認

- [ ] 3.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [ ] 3.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 3.3 手元で起動して確認した: (a) 起動して API の未読（`gh api notifications --jq length`）と同じ件数が一覧に出る、(b) Web で 1 件既読にし、5 分ほど待つと一覧から消える、(c) Web で 1 件既読にした後に再読み込みを押すと、次の取得（60 秒以内）で消える。`log show` で、条件なしの取得のログが 5 分ごとに出ていることも見る

## 4. 別コンテキストでのレビュー

- [ ] 4.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 4.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 4.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認を PR 本文に書いた
