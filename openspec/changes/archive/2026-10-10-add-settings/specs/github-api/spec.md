## MODIFIED Requirements

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
