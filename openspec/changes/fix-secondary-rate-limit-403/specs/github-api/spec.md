## MODIFIED Requirements

### Requirement: ステータスコードの扱い

Mewbell は `GET /notifications` のレスポンスを次のように扱わなければならない（MUST）。

- `200`: スレッドを読み、`Last-Modified` と `X-Poll-Interval` の値を返す
- `304`: 変化なしとして扱う（1 ページ目に `If-Modified-Since` を付けたときだけ起こる）
- `401`: 認証の失敗（トークンが無効）として扱う
- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、`Retry-After` の秒数か `X-RateLimit-Reset` の時刻を返す。待ち時間のヘッダーが無くても、本文の `message` が二次レート制限（`secondary rate limit`。大文字と小文字は区別しない）を示すときは、待ち時間が分からないレート制限として扱う。それ以外は拒否として扱う
- `429`: レート制限（二次レート制限）として扱い、`Retry-After` があればその秒数を返す。待ち時間のヘッダーが無ければ、待ち時間が分からないレート制限として扱う
- `422`: リクエストの誤りとして扱う
- それ以外の状態コード、通信の失敗、タイムアウト（30 秒）: 一時的な失敗として扱う

本文で二次レート制限を見分ける判定は、操作（「スレッドの既読化のリクエスト」「スレッドを Done にするリクエスト」「すべて既読のリクエスト」）とスレッドのイベントの取得（「スレッドのイベントの取得のリクエスト」）と同じにしなければならない（MUST）。見分けるために読んだ本文は、保持・ログ出力してはならない（MUST NOT）。

Mewbell は API のエラーレスポンスのボディを UI に出してはならない（MUST NOT）。

#### Scenario: 401

- **GIVEN** API が `401` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「認証の失敗」になる

#### Scenario: レート制限の 403

- **GIVEN** API が `403` と `X-RateLimit-Remaining: 0`、`X-RateLimit-Reset: <10 分後の時刻>` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「レート制限」になり、10 分後の時刻が得られる

#### Scenario: 429

- **GIVEN** API が `429` と `Retry-After: 600` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「レート制限」になり、600 秒後の時刻が得られる

#### Scenario: 待ち時間のヘッダーが無い二次レート制限の 403

- **GIVEN** API が `403` を返し、`X-RateLimit-Remaining: 0` も `Retry-After` も無く、本文の `message` が `You have exceeded a secondary rate limit. Please wait a few minutes before you try again.` で、`X-OAuth-Scopes: repo, read:org` がある
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「拒否」ではなく、待ち時間が分からない「レート制限」になる
- **AND** 本文はログにも結果にも残らない

#### Scenario: 待ち時間のヘッダーが無い 429

- **GIVEN** API が `429` を返し、`Retry-After` も `X-RateLimit-Remaining: 0` も無い
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は、待ち時間が分からない「レート制限」になる

#### Scenario: 二次レート制限でない 403

- **GIVEN** API が `403` を返し、待ち時間のヘッダーが無く、本文の `message` が `Resource not accessible by integration` である
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「拒否」になる

#### Scenario: 422

- **GIVEN** API が `422` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「リクエストの誤り」になる

### Requirement: スレッドの既読化のリクエスト

Mewbell は、スレッドを既読にするとき、`PATCH <API ベース URL>/notifications/threads/<threadId>` をそのスレッドのアカウントのトークンを付けて送らなければならない（SHALL）。リクエストのヘッダーとオリジン検査は `GET /notifications` と同じにしなければならない（MUST。「トークンをリクエストごとに付ける」「トークンを送る相手の制限」「リダイレクトとキャッシュ」）。`threadId` は 1〜20 桁の数字でなければならず、それ以外のときはリクエストを送らずに失敗として扱わなければならない（MUST）。レスポンスは次のように扱わなければならない（MUST）。

- `205`: 既読にできた
- `304`: すでに既読だったとして、既読にできたものと同じに扱う
- `404`: スレッドがもう無い（Done にした、など）として、既読にできたものと同じに扱う
- `401`: 認証の失敗
- `403`: レート制限（`X-RateLimit-Remaining: 0` か `Retry-After` があるとき、またはそれらが無くても本文の `message` が二次レート制限を示すとき。「ステータスコードの扱い」と同じ判定）か拒否
- `429`: レート制限
- `422`、それ以外の状態コード、リダイレクト、通信の失敗、タイムアウト: 失敗

既読化のリクエストが失敗しても、トークンを取り直してはならず（MUST NOT）、そのアカウントのポーリングを止めてはならない（MUST NOT）。

#### Scenario: 既読にする

- **GIVEN** `github.com/alice` のスレッド `123`
- **WHEN** Mewbell がスレッド `123` を既読にする
- **THEN** `PATCH https://api.github.com/notifications/threads/123` が `Authorization: Bearer <alice のトークン>` 付きで送られる
- **AND** API が `205` を返したら、既読にできたものとして扱う

#### Scenario: GHES のスレッドを既読にする

- **GIVEN** `ghe.example.com/dave` のスレッド `77`
- **WHEN** Mewbell がスレッド `77` を既読にする
- **THEN** `PATCH https://ghe.example.com/api/v3/notifications/threads/77` が `dave` のトークンで送られる

#### Scenario: スレッド ID が数字でない

- **GIVEN** スレッド ID が `123/../../user`
- **WHEN** Mewbell がそのスレッドを既読にしようとする
- **THEN** リクエストは送られず、失敗として扱う

#### Scenario: 既読化でリダイレクトされる

- **GIVEN** `PATCH /notifications/threads/123` に API が `307` と `Location: https://evil.example.com/` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** `evil.example.com` にはリクエストを送らず、失敗として扱う

#### Scenario: Done にしたスレッド

- **GIVEN** スレッド `123` は Web で Done にされている
- **WHEN** Mewbell がスレッド `123` を既読にし、API が `404` を返す
- **THEN** 既読にできたものとして扱う

#### Scenario: 既読化が二次レート制限になる

- **GIVEN** `PATCH /notifications/threads/123` に API が `403` を返し、待ち時間のヘッダーが無く、本文の `message` が二次レート制限を示す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は状態コードの失敗ではなく「レート制限」になり、トークンは取り直さず、ポーリングも止めない

### Requirement: スレッドを Done にするリクエスト

Mewbell は、スレッドを Done にするとき、`DELETE <API ベース URL>/notifications/threads/<threadId>` をそのスレッドのアカウントのトークンを付けて送らなければならない（SHALL）。リクエストのヘッダーとオリジン検査は `GET /notifications` と同じにしなければならない（MUST。「トークンをリクエストごとに付ける」「トークンを送る相手の制限」「リダイレクトとキャッシュ」）。`threadId` は 1〜20 桁の数字でなければならず、それ以外のときはリクエストを送らずに失敗として扱わなければならない（MUST）。レスポンスは次のように扱わなければならない（MUST）。

- `204`: Done にできた
- `404`: スレッドがもう無い（すでに Done にした、など）として、Done にできたものと同じに扱う
- `401`: 認証の失敗
- `403`: レート制限（`X-RateLimit-Remaining: 0` か `Retry-After` があるとき、またはそれらが無くても本文の `message` が二次レート制限を示すとき。「ステータスコードの扱い」と同じ判定）か拒否
- `429`: レート制限
- それ以外の状態コード、リダイレクト、通信の失敗、タイムアウト: 失敗

Done のリクエストが失敗しても、トークンを取り直してはならず（MUST NOT）、そのアカウントのポーリングを止めてはならない（MUST NOT）。

#### Scenario: Done にする

- **GIVEN** `github.com/alice` のスレッド `123`
- **WHEN** Mewbell がスレッド `123` を Done にする
- **THEN** `DELETE https://api.github.com/notifications/threads/123` が `Authorization: Bearer <alice のトークン>` 付きで送られる
- **AND** API が `204` を返したら、Done にできたものとして扱う

#### Scenario: GHE Cloud のスレッドを Done にする

- **GIVEN** `acme.ghe.com/dave_acme` のスレッド `77`
- **WHEN** Mewbell がスレッド `77` を Done にする
- **THEN** `DELETE https://api.acme.ghe.com/notifications/threads/77` が `dave_acme` のトークンで送られる

#### Scenario: Done でスレッド ID が数字でない

- **GIVEN** スレッド ID が `123/../../user`
- **WHEN** Mewbell がそのスレッドを Done にしようとする
- **THEN** リクエストは送られず、失敗として扱う

#### Scenario: Done でリダイレクトされる

- **GIVEN** `DELETE /notifications/threads/123` に API が `307` と `Location: https://evil.example.com/` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** `evil.example.com` にはリクエストを送らず、失敗として扱う

#### Scenario: Done の 401

- **GIVEN** `DELETE /notifications/threads/123` に API が `401` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は「認証の失敗」になり、トークンは取り直さず、ポーリングも止めない

### Requirement: すべて既読のリクエスト

Mewbell は、アカウントの通知をすべて既読にするとき、`PUT <API ベース URL>/notifications` をそのアカウントのトークンを付けて送らなければならない（SHALL）。ボディは `Content-Type: application/json` の `{"last_read_at": "<日時>", "read": true}` にしなければならない（MUST）。`<日時>` は UTC の ISO 8601（`YYYY-MM-DDTHH:MM:SSZ`）で、呼び出し元が渡した時刻にしなければならない（MUST）。ボディにトークンを入れてはならない（MUST NOT）。リクエストのヘッダーとオリジン検査は `GET /notifications` と同じにしなければならない（MUST）。レスポンスは次のように扱わなければならない（MUST）。

- `205`: 既読にできた
- `202`: 受け付けられた（GitHub が後から非同期に既読にする）。既読にできたものと同じに扱う
- `304`: 既読にするものが無かったとして、既読にできたものと同じに扱う
- `401`: 認証の失敗
- `403`: レート制限（`X-RateLimit-Remaining: 0` か `Retry-After` があるとき、またはそれらが無くても本文の `message` が二次レート制限を示すとき。「ステータスコードの扱い」と同じ判定）か拒否
- `429`: レート制限
- それ以外の状態コード（`422` を含む）、リダイレクト、通信の失敗、タイムアウト: 失敗

すべて既読のリクエストが失敗しても、トークンを取り直してはならず（MUST NOT）、そのアカウントのポーリングを止めてはならない（MUST NOT）。

#### Scenario: すべて既読にする

- **GIVEN** `github.com/alice`
- **WHEN** Mewbell が `alice` の通知を `2026-10-09T12:34:56Z` まで既読にする
- **THEN** `PUT https://api.github.com/notifications` が `Authorization: Bearer <alice のトークン>` 付きで送られる
- **AND** ボディは `{"last_read_at": "2026-10-09T12:34:56Z", "read": true}` で、トークンを含まない
- **AND** API が `205` を返したら、既読にできたものとして扱う

#### Scenario: GHES ですべて既読にする

- **GIVEN** `ghe.example.com/dave`
- **WHEN** Mewbell が `dave` の通知をすべて既読にする
- **THEN** `PUT https://ghe.example.com/api/v3/notifications` が `dave` のトークンで送られる

#### Scenario: 非同期に受け付けられる

- **GIVEN** `alice` の未読が多い
- **WHEN** Mewbell がすべて既読のリクエストを送り、API が `202` を返す
- **THEN** 既読にできたものとして扱う

#### Scenario: すべて既読でリダイレクトされる

- **GIVEN** `PUT /notifications` に API が `302` と `Location: https://evil.example.com/` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** `evil.example.com` にはリクエストを送らず、失敗として扱う

#### Scenario: すべて既読のレート制限

- **GIVEN** `PUT /notifications` に API が `403` と `X-RateLimit-Remaining: 0` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は「レート制限」になり、ポーリングの待ち時間は変わらない

#### Scenario: すべて既読が二次レート制限になる

- **GIVEN** `PUT /notifications` に API が `403` を返し、待ち時間のヘッダーが無く、本文の `message` が二次レート制限を示す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** 結果は「レート制限」になり、ポーリングの待ち時間は変わらない
