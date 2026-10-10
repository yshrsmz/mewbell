# github-api Specification

## Purpose
GitHub / GHE の REST API にアカウントのトークンを付けて問い合わせるときの約束を定める。API と Web のベース URL の導出、トークンを送ってよい相手の制限、リダイレクトとキャッシュの扱い、`GET /notifications` の取得とページネーション、ステータスコードとスコープの扱いを対象とする。

## Requirements

### Requirement: API ベース URL と Web ベース URL の導出

Mewbell はアカウントのホストから、次の規則で API ベース URL を導かなければならない（MUST）: `github.com` は `https://api.github.com`、`.ghe.com` で終わるホストは `https://api.<host>`、それ以外のホストは `https://<host>/api/v3`。Web ベース URL は、どのホスト種別でも `https://<host>` としなければならない（MUST）。ホストは M1 で検証済みの小文字の DNS 名だけを使い、スキームは常に `https` にしなければならない（MUST）。

#### Scenario: 3 種類のホストの API ベース URL

- **GIVEN** `github.com`、`acme.ghe.com`、`github.example.com` のアカウントがある
- **WHEN** Mewbell が API ベース URL を導く
- **THEN** それぞれ `https://api.github.com`、`https://api.acme.ghe.com`、`https://github.example.com/api/v3` になる

#### Scenario: Web ベース URL

- **GIVEN** `github.com` と `acme.ghe.com` のアカウントがある
- **WHEN** Mewbell が Web ベース URL を導く
- **THEN** それぞれ `https://github.com`、`https://acme.ghe.com` になる

### Requirement: トークンをリクエストごとに付ける

Mewbell は API へのリクエストを送るたびに、そのリクエストのアカウントのトークンを `Authorization: Bearer <token>` ヘッダーとしてそのリクエストにだけ付けなければならない（MUST）。複数のリクエストで共有する設定（セッションの既定のヘッダーなど）にトークンを入れてはならない（MUST NOT）。あるアカウントのリクエスト（ページネーションの続きを含む）に、別のアカウントのトークンを付けてはならない（MUST NOT）。リクエストには `Accept: application/vnd.github+json`、`X-GitHub-Api-Version: 2022-11-28`、Mewbell を示す `User-Agent` を付けなければならない（MUST）。

#### Scenario: 同じホストの 2 アカウントを交互に取得する

- **GIVEN** `github.com/alice` と `github.com/bob` が使え、どちらの通知も 2 ページある
- **WHEN** 2 つのアカウントの取得が同時に進む
- **THEN** `alice` の 1 ページ目と 2 ページ目のリクエストには `alice` のトークンだけが付く
- **AND** `bob` の 1 ページ目と 2 ページ目のリクエストには `bob` のトークンだけが付く

### Requirement: トークンを送る相手の制限

Mewbell は、トークンを付けたリクエストを送る前に、リクエスト先の URL のスキームが `https` で、ホストとポートがそのアカウントの API ベース URL と一致し、パスが API ベース URL のパスの下にあることを確かめなければならない（MUST）。一致しないときは、リクエストを送らずに失敗として扱わなければならない（MUST）。API のレスポンスに含まれる URL（`Link` ヘッダーの続きのページなど）にリクエストを送るときも、同じ確認をしなければならない（MUST）。

#### Scenario: 続きのページが別のホストを指している

- **GIVEN** `github.com/alice` の `GET /notifications` のレスポンスの `Link` ヘッダーの `rel="next"` が `https://evil.example.com/notifications?page=2` を指している
- **WHEN** Mewbell が続きのページを取得しようとする
- **THEN** `evil.example.com` へのリクエストは送られない
- **AND** その回の取得は失敗として扱われる

#### Scenario: 続きのページが http を指している

- **GIVEN** `rel="next"` が `http://api.github.com/notifications?page=2` を指している
- **WHEN** Mewbell が続きのページを取得しようとする
- **THEN** リクエストは送られず、その回の取得は失敗として扱われる

### Requirement: リダイレクトとキャッシュ

Mewbell は API へのリクエストのリダイレクト（3xx の `Location`）をたどってはならない（MUST NOT）。リダイレクトのレスポンスは失敗として扱わなければならない（MUST）。API のレスポンスをディスクやメモリの HTTP キャッシュに保存してはならず（MUST NOT）、Cookie を保存・送信してはならない（MUST NOT）。HTTPS 以外の通信を許す設定（ATS の例外など）を入れてはならない（MUST NOT）。

#### Scenario: 別のホストへのリダイレクト

- **GIVEN** API が `302` と `Location: https://evil.example.com/` を返す
- **WHEN** Mewbell がそのレスポンスを受け取る
- **THEN** Mewbell は `evil.example.com` にリクエストを送らない
- **AND** その回の取得は失敗として扱われる

#### Scenario: 認証付きのレスポンスを残さない

- **GIVEN** Mewbell が `GET /notifications` の 200 を受け取った
- **WHEN** Mewbell を終了する
- **THEN** Mewbell の HTTP キャッシュ（`~/Library/Caches/com.codingfeline.mewbell` など）にそのレスポンスは残っていない

### Requirement: 通知の取得

Mewbell は `GET <API ベース URL>/notifications` に `all=false`、`participating`、`per_page=50` を付けて、未読の通知スレッドを取得しなければならない（SHALL）。`participating` は、そのアカウントの設定「参加しているスレッドだけにする」がオンなら `true`、オフなら `false` にしなければならない（MUST）。ページネーションの続きのページ（`Link` の `rel="next"` の URL）にも、同じ `participating` の値が付いていなければならない（MUST。GitHub は `Link` にクエリを引き継いで返す）。レスポンスの `Link` ヘッダーに `rel="next"` があるときは、そのページを順にたどらなければならない（SHALL）。1 回の取得でたどるのは 10 ページまでとし、それを超える分は取得しなくてよい（MAY）。ページの間で同じ ID のスレッドが返ったときは、最初のものだけを残さなければならない（MUST）。スレッドからは ID、理由（`reason`）、更新日時（`updated_at`）、件名（`subject.title`）、種類（`subject.type`）、件名の API URL（`subject.url`、無いこともある）、リポジトリの `owner/name`（`repository.full_name`）を読み取り、必須の値が欠けているか `full_name` が `owner/name` の形でないスレッドは読み飛ばさなければならない（MUST）。1 ページのレスポンスボディが上限のサイズ（5 MiB）を超えたら、その回の取得は失敗として扱わなければならない（MUST）。

#### Scenario: 2 ページの通知

- **GIVEN** 1 ページ目の 200 のレスポンスに 50 件のスレッドと `rel="next"` があり、2 ページ目に 3 件のスレッドがある
- **WHEN** Mewbell が通知を取得する
- **THEN** 53 件のスレッドが得られる

#### Scenario: 形の崩れたスレッドを読み飛ばす

- **GIVEN** 200 のレスポンスに 3 件のスレッドがあり、1 件は `repository.full_name` が無い
- **WHEN** Mewbell がレスポンスを読む
- **THEN** 2 件のスレッドが得られ、残りの取得は続く

#### Scenario: 参加しているスレッドだけにしたアカウント

- **GIVEN** `acme.ghe.com/dave` は「参加しているスレッドだけにする」がオンで、`github.com/alice` はオフ
- **WHEN** Mewbell が両方の通知を取得する
- **THEN** `dave` の 1 ページ目は `GET https://api.acme.ghe.com/notifications?all=false&participating=true&per_page=50` になる
- **AND** `alice` の 1 ページ目は `GET https://api.github.com/notifications?all=false&participating=false&per_page=50` になる

### Requirement: ステータスコードの扱い

Mewbell は `GET /notifications` のレスポンスを次のように扱わなければならない（MUST）。

- `200`: スレッドを読み、`Last-Modified` と `X-Poll-Interval` の値を返す
- `304`: 変化なしとして扱う（1 ページ目に `If-Modified-Since` を付けたときだけ起こる）
- `401`: 認証の失敗（トークンが無効）として扱う
- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、`Retry-After` の秒数か `X-RateLimit-Reset` の時刻を返す。それ以外は拒否として扱う
- `429`: レート制限（二次レート制限）として扱い、`Retry-After` があればその秒数を返す
- `422`: リクエストの誤りとして扱う
- それ以外の状態コード、通信の失敗、タイムアウト（30 秒）: 一時的な失敗として扱う

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

#### Scenario: 422

- **GIVEN** API が `422` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「リクエストの誤り」になる

### Requirement: スコープの確認

Mewbell は、トークンを受け取ってから最初の `200` のレスポンスの `X-OAuth-Scopes` ヘッダーを読み、`repo` も `notifications` も含まれていなければ「スコープ不足」として扱わなければならない（MUST）。ヘッダーが無いとき（classic 系でないトークン）も「スコープ不足」として扱わなければならない（MUST）。「スコープ不足」のとき、そのレスポンスのスレッドを一覧に出してはならない（MUST NOT）。レート制限でない `403` のレスポンスに `X-OAuth-Scopes` があり、`repo` も `notifications` も含まれていないときも「スコープ不足」として扱わなければならない（MUST）。

#### Scenario: repo スコープがある

- **GIVEN** 最初の 200 のレスポンスの `X-OAuth-Scopes` が `gist, read:org, repo, workflow`
- **WHEN** Mewbell がスコープを確かめる
- **THEN** スコープは足りているとして扱う

#### Scenario: notifications スコープだけがある

- **GIVEN** `X-OAuth-Scopes` が `notifications`
- **WHEN** Mewbell がスコープを確かめる
- **THEN** スコープは足りているとして扱う

#### Scenario: スコープが無くて 403 が返る

- **GIVEN** `GET /notifications` が `403` と `X-OAuth-Scopes: gist, read:org` を返す（レート制限のヘッダーは無い）
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** 「スコープ不足」になる

#### Scenario: どちらも無い

- **GIVEN** `X-OAuth-Scopes` が `gist, read:org`
- **WHEN** Mewbell がスコープを確かめる
- **THEN** 「スコープ不足」になり、そのレスポンスのスレッドは一覧に出ない

### Requirement: 通信の内容をログに出さない

Mewbell は、HTTP のリクエストヘッダー（特に `Authorization`）とレスポンスボディをログに出してはならない（MUST NOT）。ログに残してよいのは、アカウントの識別子、エンドポイントのパス、状態コード、失敗の種類だけとし、可変の値は公開しない設定（`.private`）で記録しなければならない（MUST）。

#### Scenario: 401 のログ

- **GIVEN** `github.com/alice` のリクエストに API が `401` と JSON のエラーボディを返す
- **WHEN** Mewbell がログを残す
- **THEN** ログには状態コード `401` とエンドポイントのパスは残るが、トークンとレスポンスボディは残らない

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
