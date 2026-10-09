# Spec Delta

## MODIFIED Requirements

### Requirement: 条件付きリクエスト

Mewbell は、アカウントごとに最後に受け取った `200` のレスポンスの `Last-Modified` の値をメモリに持ち、次の取得の 1 ページ目に `If-Modified-Since` として付けなければならない（MUST）。ただし、次のときは `If-Modified-Since` を付けてはならない（MUST NOT）: 値を持っていないとき（最初の取得、トークンを取り直した後）、そのアカウントで最後に条件なしの取得（`If-Modified-Since` を付けずにすべてのページを取り終えた取得）をしてから 5 分以上たったとき、最後の取得の後にユーザーが再読み込みを押したとき。`304` を受け取ったときは、そのアカウントの通知の一覧を変えてはならない（MUST NOT）。`Last-Modified` は、すべてのページを取り終えたときだけ更新しなければならない（MUST）。

GitHub は `Last-Modified` に未読スレッドの `updated_at` の最新値を返すので、それより古いスレッドが後から未読になったときや、スレッドがほかの場所で既読になったときも `304` が返る。条件なしの取得は、そのずれを直すために行う。

#### Scenario: 2 回目の取得

- **GIVEN** `github.com/alice` の最初の取得の 200 のレスポンスに `Last-Modified: Thu, 08 Oct 2026 12:00:00 GMT` があった
- **WHEN** Mewbell が 60 秒後に次の取得をする
- **THEN** 1 ページ目のリクエストに `If-Modified-Since: Thu, 08 Oct 2026 12:00:00 GMT` が付く

#### Scenario: 304 では一覧を変えない

- **GIVEN** `alice` の通知が 3 件表示されている
- **WHEN** 次の取得で API が `304` を返す
- **THEN** 表示は 3 件のまま変わらない

#### Scenario: 途中のページで失敗する

- **GIVEN** 1 ページ目の 200 に `Last-Modified: A` と `rel="next"` があり、2 ページ目の取得が失敗する
- **WHEN** Mewbell が次の取得をする
- **THEN** `If-Modified-Since` には前回すべてのページを取り終えたときの値（無ければ付けない）が付き、`A` は付かない

#### Scenario: 5 分ごとに条件なしで取り直す

- **GIVEN** `alice` の最後の条件なしの取得から 5 分たち、その間の取得はすべて `304` だった
- **AND** その間に、`Last-Modified` より古い `updated_at` のスレッド `B` が未読になった
- **WHEN** Mewbell が次の取得をする
- **THEN** 1 ページ目のリクエストに `If-Modified-Since` が付かない
- **AND** 200 のレスポンスで一覧が置き換わり、`B` が表示される

#### Scenario: ほかの場所で既読にしたスレッドが消える

- **GIVEN** `alice` の一覧にスレッド `C` が表示されていて、ユーザーが Web で `C` を既読にした
- **WHEN** 最後の条件なしの取得から 5 分たった後の取得をする
- **THEN** `C` は一覧から消える

#### Scenario: 再読み込みの後は条件なしで取得する

- **GIVEN** `alice` の最後の取得から 20 秒しかたっていない
- **WHEN** ユーザーが再読み込みを押す
- **THEN** その時点では `alice` の `GET /notifications` は送られない
- **AND** 間隔（`X-Poll-Interval` と 60 秒の大きいほう）がたったところの取得には `If-Modified-Since` が付かない
