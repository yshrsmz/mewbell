## ADDED Requirements

### Requirement: リリースのタグの取得のリクエスト

Mewbell は、リリースの ID を持つ Release のスレッド（polling「スレッドのイベントの取得」の条件を満たすもの）についてだけ、タグを求めるために `GET <API ベース URL>/repos/{owner}/{name}/releases/{ID}` を送らなければならない（SHALL）。リクエストの URL は、`subject.url` をそのまま使わず、検証済みのリポジトリの `owner/name` と検証済みの ID（1〜20 桁の数字）から組み立てなければならない（MUST）。組み立てた URL にも「トークンを送る相手の制限」の確認をしなければならず（MUST）、「トークンをリクエストごとに付ける」「リダイレクトとキャッシュ」「通信の内容をログに出さない」を同じく適用しなければならない（MUST）。1 つのスレッドについて送るリクエストは、この 1 回だけにしなければならない（MUST）。レスポンスのうち、使ってよいのは `tag_name` だけで、`html_url` などの URL や本文（`body`）を保持・表示・ログ出力してはならない（MUST NOT）。

`tag_name` は、次のすべてを満たすときだけタグとして受け付けなければならない（MUST）。満たさなければ、そのスレッドのタグは「無い」として扱わなければならない（MUST）。

- 空でなく、UTF-8 で 255 バイト以下
- 空白と制御文字を含まない
- `/` で区切った要素に、空のもの・`.`・`..` が無い

レスポンスは、スレッドのイベントの取得のリクエスト（「スレッドのイベントの取得のリクエスト」）と同じく次のように扱わなければならない（MUST）。

- `200`: ボディを読む。JSON のオブジェクトでない、`tag_name` が文字列でないなど形が崩れていれば一時的な失敗として扱う
- `404` / `410`: そのスレッドのタグは「無い」として扱う（削除された、見られなくなったなど）
- `401`: 認証の失敗として扱う
- `403`: `X-RateLimit-Remaining: 0` または `Retry-After` があればレート制限として扱い、制限が解ける時刻を返す（「ステータスコードの扱い」と同じ判定）。待ち時間のヘッダーが無くても、本文の `message` が二次レート制限（`secondary rate limit`）を示すときはレート制限として扱う。それ以外の `403` と `422` はタグが「無い」として扱う
- `429`: レート制限として扱う
- それ以外の状態コード、リダイレクト、通信の失敗、タイムアウト、レスポンスが大きすぎる: 一時的な失敗として扱う

#### Scenario: リリースのタグを取る

- **GIVEN** `github.com/alice` の種類が Release のスレッドのリポジトリが `openai/codex`、`subject.url` が `https://api.github.com/repos/openai/codex/releases/413167889`
- **WHEN** Mewbell がそのスレッドのタグを取り、API が `200` と `tag_name: rust-v0.163.0-alpha.10.1` を返す
- **THEN** リクエストは `https://api.github.com/repos/openai/codex/releases/413167889` に `alice` のトークンを付けて送られる
- **AND** そのスレッドのタグは `rust-v0.163.0-alpha.10.1` になる

#### Scenario: GHES のリリースのタグを取る

- **GIVEN** `ghe.example.com/dave` の種類が Release のスレッドのリポジトリが `team/svc`、`subject.url` が `https://ghe.example.com/api/v3/repos/team/svc/releases/12`
- **WHEN** Mewbell がそのスレッドのタグを取る
- **THEN** リクエストは `https://ghe.example.com/api/v3/repos/team/svc/releases/12` に送られる

#### Scenario: 削除されたリリース

- **GIVEN** `GET /repos/octo/app/releases/12` が `404` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのタグは「無い」になる

#### Scenario: 検証を通らないタグ

- **GIVEN** `GET /repos/octo/app/releases/12` が `200` と `tag_name: ../../settings` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのタグは「無い」になる

#### Scenario: html_url は使わない

- **GIVEN** `GET /repos/octo/app/releases/12` が `200` と `tag_name: v1.0.0`、`html_url: https://evil.example.com/octo/app/releases/tag/v1.0.0` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドのタグは `v1.0.0` になり、`evil.example.com` の URL は覚えない

#### Scenario: リリースのタグの取得のレート制限

- **GIVEN** リリースのタグの取得に API が `403` と `X-RateLimit-Remaining: 0`、`X-RateLimit-Reset: <10 分後の時刻>` を返す
- **WHEN** Mewbell がレスポンスを受け取る
- **THEN** そのスレッドの結果は「レート制限」になり、10 分後の時刻が得られる
