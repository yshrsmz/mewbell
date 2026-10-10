## MODIFIED Requirements

### Requirement: ポーリングの開始と停止

Mewbell は、トークンをメモリに持っている（「使える」）アカウントごとに、独立してポーリングしなければならない（SHALL）。アカウントが初めて「使える」になったらすぐに最初の取得を始め（SHALL）、その後アカウントのトークンの状態が「取得中」や「トークンを取れない」に変わっても、ポーリングの状態（止まっていることを含む）を保たなければならない（MUST）。アカウントが一覧から消えたとき、全体の状態が「アカウントあり」以外になったとき、ユーザーが設定でそのアカウントを無効にしたとき、アプリが終了するときに、そのアカウントのポーリングを止めて取得した通知を捨てなければならない（MUST）。無効のアカウントをポーリングしてはならない（MUST NOT）。有効にし直したアカウントは、トークンを得たら初めて「使える」になったときと同じく最初の取得から始めなければならない（SHALL）。

ユーザーが設定でアカウントの「参加しているスレッドだけにする」を切り替えたときは、そのアカウントのポーリングを止めて取得した通知を捨て、新しい `participating` の値で最初の取得から始め直さなければならない（MUST）。始め直した最初の取得には `If-Modified-Since` を付けてはならない（MUST NOT。切り替える前の `Last-Modified` は別の一覧のものなので）。持っているトークンは捨てずに使い続けなければならない（MUST）。ただし、そのアカウントの取得が「スコープ不足」か「認証エラー」で止まっているときは、新しい `participating` の値を覚えるだけで取得を始めてはならず（MUST NOT）、「止めたアカウントの再開」のときに新しい値で始めなければならない（MUST）。レート制限で待っているときは、始め直した最初の取得を、切り替える前に予定していた再試行の時刻より早めてはならない（MUST NOT）。

1 つのアカウントで同時に走らせる取得は 1 つまでにしなければならない（MUST）。1 つのアカウントの失敗が、ほかのアカウントのポーリングに影響してはならない（MUST NOT）。

#### Scenario: 起動直後に取得を始める

- **GIVEN** Mewbell を起動し、`github.com/alice` のトークンを取得した
- **WHEN** `alice` が「使える」になる
- **THEN** すぐに `alice` の `GET /notifications` を送る

#### Scenario: ログアウトしたアカウント

- **GIVEN** `github.com/alice` と `github.com/bob` をポーリングしている
- **WHEN** ユーザーが `gh auth logout --user bob` を実行し、Mewbell がアカウントを読み直す
- **THEN** `bob` のポーリングは止まり、`bob` の通知は一覧から消える
- **AND** `alice` のポーリングは続く

#### Scenario: 1 つのアカウントだけ失敗する

- **GIVEN** `github.com/alice` と `ghe.example.com/dave` をポーリングしていて、`ghe.example.com` に接続できない
- **WHEN** 次の取得の時刻になる
- **THEN** `dave` の取得は失敗し、`alice` の取得はいつもどおり行われる

#### Scenario: 無効にしたアカウント

- **GIVEN** `github.com/alice` と `github.com/bob` をポーリングしている
- **WHEN** ユーザーが設定で `bob` を無効にする
- **THEN** `bob` のポーリングはすぐに止まり、`bob` の通知は一覧から消える
- **AND** その後 `bob` の `GET /notifications` は送られない
- **AND** `alice` のポーリングは続く

#### Scenario: 参加しているスレッドだけにする

- **GIVEN** `github.com/alice` を `participating=false` でポーリングしていて、一覧に 8 件ある
- **WHEN** ユーザーが設定で `alice` の「参加しているスレッドだけにする」をオンにする
- **THEN** `alice` の一覧はいったん最初の取得中の表示になり、すぐに `If-Modified-Since` を付けない `GET /notifications?all=false&participating=true&per_page=50` が送られる
- **AND** `alice` のための `gh auth token` は実行されない

#### Scenario: 止まっているアカウントで切り替える

- **GIVEN** `github.com/alice` が「スコープ不足」で止まっている
- **WHEN** ユーザーが設定で `alice` の「参加しているスレッドだけにする」をオンにする
- **THEN** `alice` の `GET /notifications` は送られず、「スコープ不足」の表示のまま
- **AND** その後ユーザーが「再読み込み」を押すと、`participating=true` で取得が再開する

#### Scenario: レート制限で待っているときに切り替える

- **GIVEN** `github.com/alice` の取得がレート制限で失敗し、2 分後に再試行する予定になっている
- **WHEN** ユーザーが設定で `alice` の「参加しているスレッドだけにする」をオンにする
- **THEN** `participating=true` の最初の取得は、その再試行の時刻まで送られない
