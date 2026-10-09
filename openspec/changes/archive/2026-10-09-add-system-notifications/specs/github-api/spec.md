# Spec Delta

## ADDED Requirements

### Requirement: スレッドの既読化のリクエスト

Mewbell は、スレッドを既読にするとき、`PATCH <API ベース URL>/notifications/threads/<threadId>` をそのスレッドのアカウントのトークンを付けて送らなければならない（SHALL）。リクエストのヘッダーとオリジン検査は `GET /notifications` と同じにしなければならない（MUST。「トークンをリクエストごとに付ける」「トークンを送る相手の制限」「リダイレクトとキャッシュ」）。`threadId` は 1〜20 桁の数字でなければならず、それ以外のときはリクエストを送らずに失敗として扱わなければならない（MUST）。レスポンスは次のように扱わなければならない（MUST）。

- `205`: 既読にできた
- `304`: すでに既読だったとして、既読にできたものと同じに扱う
- `404`: スレッドがもう無い（Done にした、など）として、既読にできたものと同じに扱う
- `401`: 認証の失敗
- `403`: レート制限（`X-RateLimit-Remaining: 0` か `Retry-After` があるとき）か拒否
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
