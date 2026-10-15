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

Mewbell は `GET <API ベース URL>/notifications` に `all=false`、`participating`、`per_page=50` を付けて、未読の通知スレッドを取得しなければならない（SHALL）。`participating` は、そのアカウントの設定「参加しているスレッドだけにする」がオンなら `true`、オフなら `false` にしなければならない（MUST）。ページネーションの続きのページ（`Link` の `rel="next"` の URL）にも、同じ `participating` の値が付いていなければならない（MUST。GitHub は `Link` にクエリを引き継いで返す）。レスポンスの `Link` ヘッダーに `rel="next"` があるときは、そのページを順にたどらなければならない（SHALL）。1 回の取得でたどるのは 10 ページまでとし、それを超える分は取得しなくてよい（MAY）。10 ページ目のレスポンスにも `rel="next"` があったときは、取得の結果に「打ち切った」ことを含めなければならない（MUST）。10 ページ目までに `rel="next"` が無くなったときは「打ち切っていない」としなければならない（MUST）。打ち切ったかどうかは、ページの数とスレッドの件数ではなく、`rel="next"` の有無で決めなければならない（MUST。読み飛ばしたスレッドや重複で件数が 500 件より少なくても、続きがあれば打ち切りになる）。ページの間で同じ ID のスレッドが返ったときは、最初のものだけを残さなければならない（MUST）。スレッドからは ID、理由（`reason`）、更新日時（`updated_at`）、件名（`subject.title`）、種類（`subject.type`）、件名の API URL（`subject.url`、無いこともある）、リポジトリの `owner/name`（`repository.full_name`）を読み取り、必須の値が欠けているか `full_name` が `owner/name` の形でないスレッドは読み飛ばさなければならない（MUST）。1 ページのレスポンスボディが上限のサイズ（5 MiB）を超えたら、その回の取得は失敗として扱わなければならない（MUST）。

#### Scenario: 2 ページの通知

- **GIVEN** 1 ページ目の 200 のレスポンスに 50 件のスレッドと `rel="next"` があり、2 ページ目に 3 件のスレッドがある
- **WHEN** Mewbell が通知を取得する
- **THEN** 53 件のスレッドが得られる
- **AND** 結果は「打ち切っていない」

#### Scenario: 10 ページで打ち切る

- **GIVEN** 1 ページ目から 10 ページ目までの 200 のレスポンスに、それぞれ 50 件のスレッドと `rel="next"` がある
- **WHEN** Mewbell が通知を取得する
- **THEN** 10 ページ目までの 500 件のスレッドが得られ、11 ページ目は要求されない
- **AND** 結果は「打ち切った」

#### Scenario: ちょうど 10 ページで終わる

- **GIVEN** 1 ページ目から 9 ページ目までに `rel="next"` があり、10 ページ目には `rel="next"` が無い
- **WHEN** Mewbell が通知を取得する
- **THEN** 結果は「打ち切っていない」

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

### Requirement: スレッドのイベントの取得のリクエスト

Mewbell は、番号を持つスレッド（ui「アカウント一覧の表示」の条件を満たして `#<番号>` を出すスレッド。Issue と Pull request）についてだけ、イベントを求めるために次のリクエストを送らなければならない（SHALL）。番号を持たないスレッド（Commit・Release・Discussion・CheckSuite、`subject.url` が検証を通らないものなど）には、これらのリクエストを送ってはならない（MUST NOT）。

- `GET <API ベース URL>/repos/{owner}/{name}/issues/{番号}`（件名の作成日時・作成者・状態を得る）
- `GET <API ベース URL>/repos/{owner}/{name}/issues/{番号}/timeline?per_page=100`（1 ページ目）

リクエストの URL は、`subject.url` をそのまま使わず、検証済みのリポジトリの `owner/name` と番号から組み立てなければならない（MUST）。Timeline の 1 ページ目の `Link` ヘッダーに `rel="last"` があり、それが 2 ページ目以降を指すときは、その最後のページを取得しなければならない（MUST）。`Link` からはページ番号だけを読み、最後のページとその前のページの URL は 1 ページ目と同じ規則で組み立てなければならない（MUST）（API が返した URL にはトークンを送らない）。最後のページに、時刻（`created_at` か `submitted_at`。コミットの `committer.date` は Timeline の並びと合わないので使わない）が近さの幅（「スレッドのイベントの決定」）の始まりより前の項目が無いとき（近さの幅が前のページにかかりうるとき）は、その前のページも使わなければならない（MUST）。その前のページが 1 ページ目なら取得済みの 1 ページ目を使い、2 ページ目以降なら取得しなければならない（MUST）。1 つのスレッドについて Timeline を 3 ページより多く取得してはならない（MUST NOT）。組み立てた URL にも、「トークンを送る相手の制限」の確認をしなければならない（MUST）。これらのリクエストにも、「トークンをリクエストごとに付ける」「リダイレクトとキャッシュ」「通信の内容をログに出さない」を同じく適用しなければならない（MUST）。Timeline のレスポンスにはコメントの本文が含まれるので、本文を保持・表示・ログ出力してはならない（MUST NOT）。

レスポンスは次のように扱わなければならない（MUST）。

- `200`: ボディを読む。形が崩れていれば一時的な失敗として扱う
- `404` / `410`: そのスレッドのイベントは「無い」として扱う（削除された、見られなくなったなど）
- `401`: 認証の失敗として扱う
- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、制限が解ける時刻を返す（「ステータスコードの扱い」と同じ判定）。待ち時間のヘッダーが無くても、本文の `message` が二次レート制限（`secondary rate limit`）を示すときはレート制限として扱う。それ以外の `403` と `422` はイベントが「無い」として扱う
- `429`: レート制限として扱う
- それ以外の状態コード、リダイレクト、通信の失敗、タイムアウト、レスポンスが大きすぎる: 一時的な失敗として扱う

1 つのスレッドについて送るリクエストのどれかが「無い」以外の失敗になったら、そのスレッドの結果はその失敗にしなければならない（MUST）。最後のページの前のページが「無い」ときは、取得済みのページだけでイベントを決めなければならない（MUST）。

#### Scenario: Issue のイベントを取る

- **GIVEN** `github.com/alice` のスレッドのリポジトリが `octo/app`、`subject.url` が `https://api.github.com/repos/octo/app/issues/7`
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** `https://api.github.com/repos/octo/app/issues/7` と `https://api.github.com/repos/octo/app/issues/7/timeline?per_page=100` に `alice` のトークンを付けたリクエストが送られる

#### Scenario: Pull request も issues のパスで取る

- **GIVEN** `ghe.example.com/dave` のスレッドの `subject.url` が `https://ghe.example.com/api/v3/repos/team/svc/pulls/42`
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** リクエストは `https://ghe.example.com/api/v3/repos/team/svc/issues/42` と `.../issues/42/timeline?per_page=100` に送られる

#### Scenario: 番号を持たないスレッド

- **GIVEN** `github.com/alice` に、種類が Release のスレッドと、`subject.url` が `https://evil.example.com/repos/octo/app/issues/7` のスレッドがある
- **WHEN** Mewbell がイベントを取るスレッドを選ぶ
- **THEN** どちらのスレッドにもイベントのリクエストは送られない

#### Scenario: 最後のページを取る

- **GIVEN** Timeline の 1 ページ目の `Link` に `rel="last"` で `https://api.github.com/repositories/1/issues/7/timeline?per_page=100&page=5` がある
- **WHEN** Mewbell がそのスレッドのイベントを取る
- **THEN** 5 ページ目を取得し、2〜4 ページ目は、5 ページ目が近さの幅の始まりより前まで届いていないときの 4 ページ目を除いて取得しない

#### Scenario: 最後のページが別のホストを指している

- **GIVEN** Timeline の 1 ページ目の `rel="last"` が `https://evil.example.com/timeline?page=5` を指している
- **WHEN** Mewbell が最後のページを取ろうとする
- **THEN** `evil.example.com` へのリクエストは送られず、5 ページ目は `https://api.github.com/repos/octo/app/issues/7/timeline?per_page=100&page=5` から取る

#### Scenario: 削除された Issue

- **GIVEN** `GET /repos/octo/app/issues/7` が `404` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのイベントは「無い」になる

#### Scenario: レート制限

- **GIVEN** Timeline の取得に API が `403` と `X-RateLimit-Remaining: 0`、`X-RateLimit-Reset: <10 分後の時刻>` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの結果は「レート制限」になり、10 分後の時刻が得られる

### Requirement: スレッドの状態の決定

Mewbell は、イベントを取るときに得た Issue のレスポンスから、スレッドの件名の今の状態を次の規則で決めなければならない（MUST）。Issue のレスポンスを得られなかったスレッドの状態は「分からない」にしなければならない（MUST）。

- Pull request（`pull_request` がある）: `pull_request.merged_at` があれば Merged、`state` が `closed` なら Closed、`draft` が `true` なら Draft、それ以外の `open` なら Open
- Issue: `state` が `open` なら Open、`closed` で `state_reason` が `completed` か無いなら Closed as completed、それ以外（`not_planned`・`duplicate` など）の `closed` なら Closed as not planned
- 上のどれにも当たらない値（知らない `state` など）は「分からない」

#### Scenario: マージした Pull request

- **GIVEN** `GET /repos/cli/cli/issues/14634` が `state: closed`、`pull_request.merged_at: 2026-10-09T14:47:45Z` を返す
- **WHEN** Mewbell が状態を決める
- **THEN** 状態は Merged になる

#### Scenario: 対応しないで閉じた Issue

- **GIVEN** Issue のレスポンスが `state: closed`、`state_reason: not_planned` で、`pull_request` が無い
- **WHEN** Mewbell が状態を決める
- **THEN** 状態は Closed as not planned になる

#### Scenario: 下書きの Pull request

- **GIVEN** Issue のレスポンスが `state: open`、`draft: true` で、`pull_request.merged_at` が `null`
- **WHEN** Mewbell が状態を決める
- **THEN** 状態は Draft になる

### Requirement: スレッドのイベントの決定

Mewbell は、Issue と Timeline のレスポンスから、スレッドの `updated_at` を更新したイベントを次の規則で 1 つ決めなければならない（MUST）。スレッドの `updated_at` は、きっかけになったイベントの時刻より数十秒遅れることがあるので、その分の幅を取る。

Timeline の項目のうち、次の `event` だけを候補にしなければならない（MUST）。ほかの `event`（`labeled`、`cross-referenced`、`referenced`、`mentioned`、`subscribed`、知らない値など）は候補にしてはならない（MUST NOT）。

| `event` | イベント | 時刻 | 実行者 |
|---|---|---|---|
| `commented` | Commented | `created_at` | `actor.login` |
| `reviewed`（`state: approved`） | Approved | `submitted_at` | `user.login` |
| `reviewed`（`state: changes_requested`） | Requested changes | `submitted_at` | `user.login` |
| `reviewed`（`state: commented`） | Reviewed | `submitted_at` | `user.login` |
| `closed` | Closed | `created_at` | `actor.login` |
| `reopened` | Reopened | `created_at` | `actor.login` |
| `merged` | Merged | `created_at` | `actor.login` |
| `ready_for_review` | Marked ready for review | `created_at` | `actor.login` |
| `convert_to_draft` | Converted to draft | `created_at` | `actor.login` |
| `review_requested` | Requested review | `created_at` | `actor.login` |
| `assigned` | Assigned | `created_at` | `actor.login` |
| `committed` | Pushed commits | `committer.date` | なし |
| `head_ref_force_pushed` | Force-pushed | `created_at` | `actor.login` |

- 候補は、時刻が「件名の作成日時 + 60 秒」より後で（作成と同時に起きる `review_requested` や、作成前のコミットを除くため）、かつ「スレッドの `updated_at` − 180 秒」から「スレッドの `updated_at` + 60 秒」までの幅（以下「近さの幅」）に入るものに限らなければならない（MUST）。時刻を読めない項目は候補にしてはならない（MUST NOT）。近さの幅に入らない候補を、近いものが無いからといって代わりに使ってはならない（MUST NOT）（作成から時間がたってから push したコミットのように、時刻が `updated_at` を表さない項目で、古い別のイベントを拾わないため）
- 候補があれば、時刻がスレッドの `updated_at` にいちばん近い候補をイベントにしなければならない（MUST）。近さが同じ候補が複数あれば、取得したページを古い順につなげたときに後ろにあるものにしなければならない（MUST）。それが `closed` で、その時刻の 60 秒前からその時刻までに `merged` があるときは、`merged` の実行者で Merged にしなければならない（MUST）。取得したページに `merged` が無くても、Issue の `pull_request.merged_at` がその幅に入るときは、`closed` の実行者で Merged にしなければならない（MUST）
- 候補が無く、件名の作成日時が近さの幅に入るときは、件名の作成者（Issue の `user.login`）で Opened にしなければならない（MUST）
- それ以外のときは、イベントは「無い」にしなければならない（MUST）

実行者のログイン名は、GitHub のログイン名として妥当な値（gh-cli のユーザー名の検証と同じ規則）か、それに `[bot]` を付けた値のときだけ使わなければならない（MUST）。ログイン名が無い（`null`、削除されたユーザーなど）か妥当でないときは、イベントは実行者なしにしなければならない（MUST）。

#### Scenario: コメント

- **GIVEN** Issue `octo/app#7` の作成日時が 10:00、スレッドの `updated_at` が 12:00:30 で、Timeline の作成より後の候補が 11:30 の `labeled`（候補にしない）と 12:00 の `commented`（`actor.login: bob`）
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Commented、実行者は `bob` になる

#### Scenario: マージ

- **GIVEN** Pull request の Timeline の最後が、14:47:45 の `merged`（`williammartin`）、14:47:45 の `closed`（`williammartin`）、14:47:47 の `head_ref_deleted` で、スレッドの `updated_at` が 14:47:45
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Merged、実行者は `williammartin` になる

#### Scenario: updated_at の後の出来事は使わない

- **GIVEN** スレッドの `updated_at` が 12:00 で、Timeline に 11:59 の `closed`（`alice`）と 15:00 の `commented`（`bob`）がある
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Closed、実行者は `alice` になる

#### Scenario: 開かれた Pull request

- **GIVEN** Pull request の作成日時が 19:39:42、作成者が `BagToad`、スレッドの `updated_at` が 19:39:42 で、Timeline には作成前のコミットの `committed` と 19:39:43 の `review_requested` しか無い
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Opened、実行者は `BagToad` になる

#### Scenario: いちばん近い候補を選ぶ

- **GIVEN** Pull request の作成日時が 16:12:06、スレッドの `updated_at` が 16:18:08 で、Timeline に 16:17:15 の `commented`（`github-actions[bot]`）、16:17:32 の `merged` と `closed`（`yshrsmz`）、16:17:46 の `commented`（`sincetimer-android-app[bot]`）がある
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Commented、実行者は `sincetimer-android-app[bot]` になる

#### Scenario: 遠い候補は使わない

- **GIVEN** Pull request の作成日時が 09:00、スレッドの `updated_at` が 12:00 で、Timeline の作成より後の候補は 10:00 の `commented`（`bob`）と、`committer.date` が 11:00 の `committed`（12:00 に push された）だけ
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは「無い」になる（Commented by `bob` も Pushed commits も出さない）

#### Scenario: 候補にしないイベントだけ

- **GIVEN** Issue の作成日時が 10:00、スレッドの `updated_at` が 12:00 で、Timeline の 10:00 より後の項目は 12:00 の `labeled` と `cross-referenced` だけ
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは「無い」になる（`labeled` や `cross-referenced` は出さない）

#### Scenario: ボットの実行者

- **GIVEN** 最後の候補が `commented` で、`actor.login` が `dependabot[bot]`
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは Commented、実行者は `dependabot[bot]` になる

#### Scenario: 妥当でない実行者

- **GIVEN** 最後の候補が `closed` で、`actor` が `null`
- **WHEN** Mewbell がイベントを決める
- **THEN** イベントは実行者なしの Closed になる
