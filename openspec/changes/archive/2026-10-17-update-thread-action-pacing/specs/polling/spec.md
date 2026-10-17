## MODIFIED Requirements

### Requirement: リポジトリのグループの既読化と Done のリクエストの順

対象のスレッドへのリクエストは、一覧の並び順（更新日時が新しい順）に 1 件ずつ送らなければならない（SHALL）。1 件目は待たずに送り、2 件目以降は、前のリクエストの結果が出てから 1 秒待って送らなければならない（SHALL。二次レート制限を避けるため。前の結果が失敗でも同じ）。リクエストの結果が認証エラー（`401`）かレート制限（`403` のレート制限、`429`）になったら、残りのスレッドへのリクエストは送ってはならない（MUST NOT）。送らなかったスレッドは、失敗したスレッドと同じく、その後に送った取得の結果で未読のままなら一覧に戻さなければならない（SHALL）。それ以外の失敗（`500` などの状態コード、通信の失敗、タイムアウト）では、残りのスレッドへのリクエストを続けなければならない（SHALL）。

#### Scenario: 2 件目からは 1 秒空けて送る

- **GIVEN** `github.com/alice` の `octo/app` のグループにスレッド `1`（12:30）、`2`（12:00）、`3`（11:30）がある
- **WHEN** ユーザーがグループを Done にする
- **THEN** `DELETE /notifications/threads/1` は待たずに送られる
- **AND** `DELETE /notifications/threads/2` は、`1` の結果が出てから 1 秒後に送られる
- **AND** `DELETE /notifications/threads/3` は、`2` の結果が出てから 1 秒後に送られる

#### Scenario: 1 件だけのグループは待たない

- **GIVEN** `octo/app` のグループにスレッド `1` だけがある
- **WHEN** ユーザーがグループを既読にする
- **THEN** `PATCH /notifications/threads/1` は待たずに送られ、その後に 1 秒の待ちは入らない

#### Scenario: 前のリクエストが失敗しても 1 秒空ける

- **GIVEN** `octo/app` のグループにスレッド `1` と `2` がある
- **WHEN** ユーザーがグループを既読にし、`PATCH /notifications/threads/1` が `500` を返す
- **THEN** `PATCH /notifications/threads/2` は、`1` の結果が出てから 1 秒後に送られる

#### Scenario: 待っている間にアカウントを無効にする

- **GIVEN** `octo/app` のグループにスレッド `1` と `2` があり、ユーザーがグループを Done にして、`DELETE /notifications/threads/1` の結果が出た後の 1 秒を待っている
- **WHEN** ユーザーが `alice` を無効にし、Mewbell が `alice` のポーリングを止めてトークンを捨てる
- **THEN** 1 秒が過ぎても `DELETE /notifications/threads/2` は送られない

#### Scenario: すべて Done でも 1 秒空けて送る

- **GIVEN** `github.com/alice` の一覧に、`octo/app` のスレッド `1`（12:30）と `octo/lib` のスレッド `2`（12:00）がある
- **WHEN** ユーザーが `alice` のスレッドをすべて Done にする
- **THEN** `DELETE /notifications/threads/1` は待たずに送られ、`DELETE /notifications/threads/2` は `1` の結果が出てから 1 秒後に送られる

#### Scenario: 途中でレート制限になる

- **GIVEN** `octo/app` のグループにスレッド `1`、`2`、`3` がある
- **WHEN** ユーザーがグループを Done にし、`DELETE /notifications/threads/1` がレート制限の `403` を返す
- **THEN** `2` と `3` へのリクエストは送られない
- **AND** `alice` に、Done が「レート制限」で失敗したことが 1 つの知らせとして記録される
- **AND** その後に送った取得の結果で `1`、`2`、`3` が未読のまま返れば、一覧に戻る

#### Scenario: 途中のスレッドが失敗しても続ける

- **GIVEN** `octo/app` のグループにスレッド `1`、`2`、`3` がある
- **WHEN** ユーザーがグループを既読にし、`PATCH /notifications/threads/1` と `PATCH /notifications/threads/2` が `500` を返す
- **THEN** `PATCH /notifications/threads/3` も送られる
- **AND** 知らせる失敗は、既読が「HTTP 500」で失敗したことの 1 つだけになる
