# Tasks

## 1. API クライアントの分類

- [ ] 1.1 `Mewbell/GitHubAPI/GitHubAPIClient.swift` で、`NotificationsFetchResult.rateLimited` の連想値を `retryAt: Date?` にし、doc コメントに `nil` が「待ち時間が分からない」ことを書く（design.md D1）。`403` / `429` を「時刻が分かる」「待ち時間が分からない」「レート制限でない」に分ける `private` の判定を 1 つ置き、`classifyFailure`・`classifyAction`・`get` をその判定から決める形にする（D2 の表）。`isSecondaryRateLimit(_:)` の本文の扱い（`message` だけを読み、残さない）は変えない。`FeedDiagnostics` など、`.rateLimited(let retryAt)` を取り出している箇所をコンパイルが通るように直す（ポーラーの待ちは 2.1 で変える）。
- [ ] 1.2 `MewbellTests/GitHubAPIClientTests.swift` に、一覧の取得で、待ち時間のヘッダーの無い二次レート制限の `403`（`X-OAuth-Scopes: repo` 付き）が `.rateLimited(retryAt: nil)` に、待ち時間のヘッダーの無い `429` が `.rateLimited(retryAt: nil)` に、ほかの本文の `403` が `.forbidden` になるテストを足す。二次レート制限の本文がログにも結果にも残らないことは、結果の enum に本文が入らないことで確かめる。`MewbellTests/ThreadActionRequestTests.swift` に、既読・Done・すべて既読で、ヘッダーの無い二次レート制限の `403` が `.rateLimited` に、ほかの本文の `403` が `.failed(.unexpectedStatus(403))` になるテストを足す。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/GitHubAPIClientTests -only-testing:MewbellTests/ThreadActionRequestTests -only-testing:MewbellTests/ThreadDetailsRequestTests` を通し、`ThreadDetailsRequestTests` が変更なしで通ることも確かめる（結果のスイート数も確かめる）。

## 2. ポーラーの待ち方

- [ ] 2.1 `Mewbell/Polling/AccountPoller.swift` の `handle` で、`.rateLimited(retryAt: nil)` を受けたら `consecutiveFailures` を 1 増やし、`PollSchedule.afterFailure` の時間だけ待ち、`phase` を `rateLimited: true` にする（D3）。`retryAt` があるときは今のまま。
- [ ] 2.2 ポーラーのテストを足す。待ち時間のヘッダーの無い二次レート制限の `403` が 2 回続くと、2 回目の後に 120 秒待つこと、`phase` が `retrying(rateLimited: true)` になり、最後の取得の失敗がレート制限になり、一覧が残ること（`PollingTests` か `PollingDiagnosticsTests` の、近いテストのあるファイルに置く）。その待ちの間に再読み込みを押しても、予定の時刻まで取得を送らないこと（`RefreshNowTests`）。成功の後は 60 秒からに戻ること。`xcodebuild ... test -only-testing:` で該当のスイートを通す。

## 3. 確認

- [ ] 3.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [ ] 3.2 `bash scripts/run.sh` で起動し、手元のアカウントで通知の一覧が今までどおり取得でき、既読・Done が今までどおり動くことを確かめる（二次レート制限は手元で起こせないので、その振る舞いは 1.2 と 2.2 のテストで確かめる）。

## 4. レビュー

- [ ] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する。
