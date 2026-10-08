# Spec Delta

## Purpose

GitHub / GHE の REST API にアカウントのトークンを付けて問い合わせるときの約束を定める。API と Web のベース URL の導出、トークンを送ってよい相手の制限、リダイレクトとキャッシュの扱い、`GET /notifications` の取得とページネーション、ステータスコードとスコープの扱いを対象とする。

## ADDED Requirements

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

Mewbell は `GET <API ベース URL>/notifications` に `all=false`、`participating=false`、`per_page=50` を付けて、未読の通知スレッドを取得しなければならない（SHALL）。レスポンスの `Link` ヘッダーに `rel="next"` があるときは、そのページを順にたどらなければならない（SHALL）。1 回の取得でたどるのは 10 ページまでとし、それを超える分は取得しなくてよい（MAY）。スレッドからは ID、理由（`reason`）、更新日時（`updated_at`）、件名（`subject.title`）、種類（`subject.type`）、件名の API URL（`subject.url`、無いこともある）、リポジトリの `owner/name`（`repository.full_name`）を読み取り、必須の値が欠けているか `full_name` が `owner/name` の形でないスレッドは読み飛ばさなければならない（MUST）。1 ページのレスポンスボディが上限のサイズ（5 MiB）を超えたら、その回の取得は失敗として扱わなければならない（MUST）。

#### Scenario: 2 ページの通知

- **GIVEN** 1 ページ目の 200 のレスポンスに 50 件のスレッドと `rel="next"` があり、2 ページ目に 3 件のスレッドがある
- **WHEN** Mewbell が通知を取得する
- **THEN** 53 件のスレッドが得られる

#### Scenario: 形の崩れたスレッドを読み飛ばす

- **GIVEN** 200 のレスポンスに 3 件のスレッドがあり、1 件は `repository.full_name` が無い
- **WHEN** Mewbell がレスポンスを読む
- **THEN** 2 件のスレッドが得られ、残りの取得は続く

### Requirement: ステータスコードの扱い

Mewbell は `GET /notifications` のレスポンスを次のように扱わなければならない（MUST）。

- `200`: スレッドを読み、`Last-Modified` と `X-Poll-Interval` の値を返す
- `304`: 変化なしとして扱う（1 ページ目に `If-Modified-Since` を付けたときだけ起こる）
- `401`: 認証の失敗（トークンが無効）として扱う
- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、`Retry-After` の秒数か `X-RateLimit-Reset` の時刻を返す。それ以外は拒否として扱う
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

#### Scenario: 422

- **GIVEN** API が `422` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** その結果は「リクエストの誤り」になる

### Requirement: スコープの確認

Mewbell は、トークンを受け取ってから最初の `200` のレスポンスの `X-OAuth-Scopes` ヘッダーを読み、`repo` も `notifications` も含まれていなければ「スコープ不足」として扱わなければならない（MUST）。ヘッダーが無いとき（classic 系でないトークン）も「スコープ不足」として扱わなければならない（MUST）。「スコープ不足」のとき、そのレスポンスのスレッドを一覧に出してはならない（MUST NOT）。

#### Scenario: repo スコープがある

- **GIVEN** 最初の 200 のレスポンスの `X-OAuth-Scopes` が `gist, read:org, repo, workflow`
- **WHEN** Mewbell がスコープを確かめる
- **THEN** スコープは足りているとして扱う

#### Scenario: notifications スコープだけがある

- **GIVEN** `X-OAuth-Scopes` が `notifications`
- **WHEN** Mewbell がスコープを確かめる
- **THEN** スコープは足りているとして扱う

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
