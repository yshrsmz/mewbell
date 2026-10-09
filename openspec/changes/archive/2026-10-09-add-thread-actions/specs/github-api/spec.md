# Spec Delta

## ADDED Requirements

### Requirement: スレッドを Done にするリクエスト

Mewbell は、スレッドを Done にするとき、`DELETE <API ベース URL>/notifications/threads/<threadId>` をそのスレッドのアカウントのトークンを付けて送らなければならない（SHALL）。リクエストのヘッダーとオリジン検査は `GET /notifications` と同じにしなければならない（MUST。「トークンをリクエストごとに付ける」「トークンを送る相手の制限」「リダイレクトとキャッシュ」）。`threadId` は 1〜20 桁の数字でなければならず、それ以外のときはリクエストを送らずに失敗として扱わなければならない（MUST）。レスポンスは次のように扱わなければならない（MUST）。

- `204`: Done にできた
- `404`: スレッドがもう無い（すでに Done にした、など）として、Done にできたものと同じに扱う
- `401`: 認証の失敗
- `403`: レート制限（`X-RateLimit-Remaining: 0` か `Retry-After` があるとき）か拒否
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
- `403`: レート制限（`X-RateLimit-Remaining: 0` か `Retry-After` があるとき）か拒否
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
