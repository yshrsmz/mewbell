# Design

## Context

- `GitHubAPIClient`（`Mewbell/GitHubAPI/GitHubAPIClient.swift`）は、`403` / `429` を経路ごとに別の関数で分類している。
  - 通知の一覧の取得: `classifyFailure(_:)`。`rateLimitedUntil(_:)` がヘッダーから時刻を出せれば `.rateLimited(retryAt:)`、出せなければ `.forbidden(scopes:)`。`429` は、ヘッダーが無くても今の時刻で `.rateLimited` になる。
  - 操作（既読・Done・すべて既読）: `classifyAction(_:success:)`。`403 where isRateLimited(response), 429` が `.rateLimited`、ほかは `.failed(.unexpectedStatus(403))`。
  - スレッドの状態とイベントの取得: `get(_:endpoints:token:)`。ヘッダーで分からなければ `isSecondaryRateLimit(_:)` で本文の `message` を見て、`.rateLimited(retryAt: now())` にする（`ThreadDetailsCache` が最短 60 秒に延ばす）。
- `AccountPoller.handle(_:fetchNumber:refreshedToken:)` は、`.rateLimited` を `PollSchedule.afterRateLimit`（60 秒〜1 時間に丸める）で待ち、`phase` を `retrying(rateLimited: true)` にする。`.forbidden` は `consecutiveFailures` を増やして `PollSchedule.afterFailure`（60 秒から倍々、上限 900 秒）で待ち、`rateLimited: false` にする。
- 再読み込み（`refreshNow()`）と、作り直したポーラーへの待ちの持ち越し（`CarriedWait`）は、`FeedPhase.isRateLimited` を見て早めるかを決める。診断の失敗の種類（`FailureKind`）は、`NotificationsFetchResult` と `ThreadActionResult` から決まる。
- 操作の失敗の文（`ActionFailureMessage`）は、すでに `FailureKind.rateLimited` に「because of the rate limit」を出す。

## Goals / Non-Goals

**Goals:**

- 待ち時間のヘッダーが無い二次レート制限の `403` を、一覧の取得と操作でもレート制限として扱う。本文で見分ける判定を 1 か所にする。
- 一覧の取得では、待ち時間が分からないレート制限を、倍々で延ばしながら待ち、再読み込みなどで早めない。

**Non-Goals:**

- スレッドの状態とイベントの取得の待ち方（ヘッダーで分からなければ 60 秒）を変えること。
- 待ち時間が分かるレート制限の待ち方（`Retry-After` / `X-RateLimit-Reset` まで、60 秒〜1 時間）を変えること。
- UI の文言を変えること。取得の状態と操作の失敗は、すでにレート制限を出し分けている。

## Decisions

### D1. 一覧の取得の結果は `rateLimited(retryAt: Date?)` にし、`nil` を「待ち時間が分からない」にする（A8、A9）

`NotificationsFetchResult.rateLimited(retryAt: Date)` の連想値を `Date?` にする。ヘッダーで時刻が分かれば今までどおりその時刻を入れ、待ち時間のヘッダーの無い二次レート制限の `403` と、待ち時間のヘッダーの無い `429` は `nil` にする。`FailureKind` への変換は、今の `.rateLimited` の行のまま変わらない。

採らなかった案:

- `.rateLimited(retryAt: now())` にする: `PollSchedule.afterRateLimit` が 60 秒に丸めるので、続いても毎回 60 秒で叩き直すことになり、拒否として扱っている今の倍々の待ちが無くなる。GitHub の推奨（続けば待ちを延ばしていく）にも合わない。
- 新しい case（`rateLimitedWithoutWait` など）を足す: 呼び出し側で「レート制限」として扱う箇所（診断、ポーラー）がすべて 2 つの case を並べることになる。待ち時間が分かるかどうかはレート制限の属性なので、連想値で表す。

### D2. 二次レート制限の判定を 1 か所にし、3 つの分類から使う（A6、A10）

`GitHubAPIClient` の中に、`403` / `429` のレスポンスをレート制限かどうかに分ける `private` の関数を 1 つ置く。結果は、時刻の分かるレート制限、待ち時間の分からないレート制限、レート制限でない、の 3 つにする（`private` の enum）。

- 時刻が分かる: `X-RateLimit-Remaining: 0` か `Retry-After` がある（今の `isRateLimited(_:)` と `rateLimitedUntil(_:)` の判定）
- 待ち時間が分からない: それらが無く、`429` であるか、本文の `message` が `secondary rate limit` を大文字と小文字を区別せずに含む（今の `isSecondaryRateLimit(_:)`）
- レート制限でない: それ以外の `403`

3 つの分類はこの結果から次のように決める。

| 結果 | 一覧（`classifyFailure`） | 操作（`classifyAction`） | 状態とイベント（`get`） |
|---|---|---|---|
| 時刻が分かる | `.rateLimited(retryAt: 時刻)` | `.rateLimited` | `.rateLimited(retryAt: 時刻)` |
| 待ち時間が分からない | `.rateLimited(retryAt: nil)` | `.rateLimited` | `.rateLimited(retryAt: now())`（今と同じ） |
| レート制限でない | `.forbidden(scopes:)` | `.failed(.unexpectedStatus(403))` | `.unavailable` |

状態とイベントの取得の振る舞いは変わらない（ヘッダーの無い `429` は今も `now()`、二次レート制限の `403` も今と同じ）。本文は判定のためだけに `JSONDecoder` で `message` を読み、保持もログ出力もしない。今の `isSecondaryRateLimit(_:)` の扱いのまま、呼び出す場所が増えるだけになる。

採らなかった案:

- 経路ごとに `isSecondaryRateLimit(_:)` を呼び足す: 同じ判定の並びが 3 か所に分かれ、今回のように 1 か所だけ違う状態に戻りやすい。

### D3. 待ち時間が分からないレート制限は、失敗の回数で倍々に待ち、`rateLimited: true` にする（A2、A7）

`AccountPoller.handle` で `.rateLimited(retryAt: nil)` を受けたら、`.forbidden` と同じく `consecutiveFailures` を 1 増やして `PollSchedule.afterFailure(consecutiveFailures:)` の時間だけ待ち、`phase` を `retrying(after:rateLimited: true, now:)` にする。`retryAt` があるときは今のまま（`afterRateLimit`、`consecutiveFailures` は変えない）。成功で `consecutiveFailures` を 0 に戻すのも今のまま。

`phase` が `rateLimited: true` になるので、再読み込み（`refreshNow()`）と `CarriedWait`（参加しているスレッドだけにするの切り替え、無効にして有効に戻す）は、今のレート制限と同じく早めない。新しい分岐は足さない。

判断はポーラーの actor の上で、今の `.rateLimited` と `.forbidden` の分岐の並びに書く。待ち時間の計算は今ある純粋な関数（`PollSchedule.afterFailure`）を使う。

採らなかった案:

- レート制限だけの回数を別に数える: 拒否と二次レート制限が交互に続くことはまず無く、待ちの上限（15 分）も同じなので、数え分ける要件もテストも無い（A9）。
- ヘッダーで時刻の分かるレート制限を受けたら `consecutiveFailures` を 0 に戻す: 今の振る舞い（数えない、戻さない）を変える要件が無い。
- 待ちの上限を 1 時間（待ち時間が分かるレート制限の上限）にする: 二次レート制限は数分で解けることが多く、GitHub も具体的な上限を示していない。拒否などと同じ 15 分にして、表の数を増やさない。

### D4. 操作は判定を共有するだけで、呼び出し側は変えない（A8）

`classifyAction` を D2 の判定に置き換える。`ThreadActionResult.rateLimited` は今もあり、ポーラーの操作の記録と `ActionFailureMessage` はすでにレート制限を出し分けているので、Polling と UI は変えない。既読化の `429` は今のコードでもレート制限になっているので、spec に書き足すだけで振る舞いは変わらない。

### D5. 文書の更新は要らない

`docs/architecture.md` に、名前を変える・消す関数（`isRateLimited`、`isSecondaryRateLimit`、`rateLimitedUntil`）はバッククォートで書かれていない（grep で確かめた）。D1〜D4 は今の原則（A2、A6〜A10）の範囲で、ほかの機能を足すときに同じ問いが出る新しい判断は無いので、原則も足さない。

## テストの差し替え

ネットワークは今までどおり `HTTPTransport` プロトコルの偽物（`FakeHTTPTransport`）で差し替え、状態コード・ヘッダー・本文を指定したレスポンスを返す。gh サブプロセスには触れない。

- `GitHubAPIClientTests`: 一覧の取得で、ヘッダーの無い二次レート制限の `403` が `.rateLimited(retryAt: nil)` に、ヘッダーの無い `429` が `.rateLimited(retryAt: nil)` に、ほかの本文の `403` が `.forbidden` になること。
- `ThreadActionRequestTests`: 既読・Done・すべて既読で、ヘッダーの無い二次レート制限の `403` が `.rateLimited` に、ほかの本文の `403` が `.failed(.unexpectedStatus(403))` になること。
- `ThreadDetailsRequestTests`: 今のテストがそのまま通ること（振る舞いを変えないことの確認）。
- `PollingTests` など: 待ち時間が分からないレート制限が 2 回続くと 120 秒待つこと、`phase` が `rateLimited: true` になり、最後の失敗の種類がレート制限になること。`RefreshNowTests`: その待ちの間に再読み込みを押しても早めないこと。

## Risks / Trade-offs

- [本文の文言が変わると見分けられなくなる] → 見分けられなくても、一覧は今と同じ拒否の倍々の待ちに、操作は今と同じ状態コードの失敗に戻るだけで、今より悪くはならない。GitHub のドキュメントと Gitify が同じ文言（`secondary rate limit`）を使っていることを確かめた。
- [GHES の古い版で文言が違う] → 上と同じく、今の振る舞いに戻るだけ。
- [スコープの確認との関係] → github-api「スコープの確認」は「レート制限でない `403`」だけを見るので、二次レート制限の `403` に `X-OAuth-Scopes` が付いていても「スコープ不足」にはしない。今は、スコープの揃ったトークンなら `.forbidden` の倍々の待ちになるだけだった。

## セキュリティ

トークンの流れは変えない。トークンは `AccountPoller` が `TokenProviding` から受け取り、取得や操作のたびに引数で `GitHubAPIClient` に渡す。送るのは `send(_:method:endpoints:token:...)` の中だけで、送り先の検査（`isAllowedRequestURL`）、リダイレクトの拒否、キャッシュを使わないこと、ヘッダーの付け方は変えない。破棄の時機（アカウントの削除・無効化・終了）も変えない。

`.claude/rules/security.md` の項目への対応:

- トークンの扱い: 触れない。トークンは永続化せず、メモリにだけ持つ。
- エラーの本文: 二次レート制限を見分けるために、レスポンスの本文から `message` だけを読む。結果の enum にもログにも本文を入れず、UI には `FailureKind` から決めた固定の文言だけを出す（A8）。今の状態とイベントの取得と同じ扱い。
- gh サブプロセス、URL を開く処理、アプリとビルドの設定、依存: 触れない。
- ネットワーク: 応答の分類だけを変え、送り先・オリジン検査・リダイレクト・キャッシュは変えない。
