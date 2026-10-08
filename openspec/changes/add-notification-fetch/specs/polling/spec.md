# Spec Delta

## Purpose

アカウントごとに Notifications API を繰り返し問い合わせるときの約束を定める。ポーリングの開始と停止、`If-Modified-Since` と `X-Poll-Interval` に従った間隔、失敗したときの待ち方、401 のときのトークンの取り直し、スコープ不足と認証エラーで止めることと再開のタイミングを対象とする。

## ADDED Requirements

### Requirement: ポーリングの開始と停止

Mewbell は、トークンをメモリに持っている（「使える」）アカウントごとに、独立してポーリングしなければならない（SHALL）。アカウントが「使える」になったらすぐに最初の取得を始め（SHALL）、アカウントが一覧から消えたとき、全体の状態が「アカウントあり」以外になったとき、アプリが終了するときに、そのアカウントのポーリングを止めて取得した通知を捨てなければならない（MUST）。1 つのアカウントで同時に走らせる取得は 1 つまでにしなければならない（MUST）。1 つのアカウントの失敗が、ほかのアカウントのポーリングに影響してはならない（MUST NOT）。

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

### Requirement: 条件付きリクエスト

Mewbell は、アカウントごとに最後に受け取った `200` のレスポンスの `Last-Modified` の値をメモリに持ち、次の取得の 1 ページ目に `If-Modified-Since` として付けなければならない（MUST）。値を持っていないとき（最初の取得、トークンを取り直した後）は `If-Modified-Since` を付けてはならない（MUST NOT）。`304` を受け取ったときは、そのアカウントの通知の一覧を変えてはならない（MUST NOT）。`Last-Modified` は、すべてのページを取り終えたときだけ更新しなければならない（MUST）。

#### Scenario: 2 回目の取得

- **GIVEN** `github.com/alice` の最初の取得の 200 のレスポンスに `Last-Modified: Thu, 08 Oct 2026 12:00:00 GMT` があった
- **WHEN** Mewbell が次の取得をする
- **THEN** 1 ページ目のリクエストに `If-Modified-Since: Thu, 08 Oct 2026 12:00:00 GMT` が付く

#### Scenario: 304 では一覧を変えない

- **GIVEN** `alice` の通知が 3 件表示されている
- **WHEN** 次の取得で API が `304` を返す
- **THEN** 表示は 3 件のまま変わらない

#### Scenario: 途中のページで失敗する

- **GIVEN** 1 ページ目の 200 に `Last-Modified: A` と `rel="next"` があり、2 ページ目の取得が失敗する
- **WHEN** Mewbell が次の取得をする
- **THEN** `If-Modified-Since` には前回すべてのページを取り終えたときの値（無ければ付けない）が付き、`A` は付かない

### Requirement: ポーリングの間隔

Mewbell は、成功した取得（`200` か `304`）の後、レスポンスの `X-Poll-Interval` の秒数と 60 秒の大きいほうだけ待ってから次の取得をしなければならない（MUST）。`X-Poll-Interval` が無いか数値でないときは 60 秒としなければならない（MUST）。ユーザーの操作（ポップオーバーを開く、再読み込みを押す）で、この間隔より早く取得してはならない（MUST NOT）。待っている間にスリープしていた場合、復帰したときに間隔が過ぎていれば次の取得をしなければならない（SHALL）。

#### Scenario: X-Poll-Interval に従う

- **GIVEN** 最後の取得のレスポンスに `X-Poll-Interval: 120` があった
- **WHEN** 最後の取得から 60 秒たつ
- **THEN** まだ次の取得はしない
- **AND** 120 秒たったところで次の取得をする

#### Scenario: 下限は 60 秒

- **GIVEN** 最後の取得のレスポンスに `X-Poll-Interval: 10` があった
- **WHEN** 最後の取得から 10 秒たつ
- **THEN** まだ次の取得はしない
- **AND** 60 秒たったところで次の取得をする

#### Scenario: 再読み込みで早めない

- **GIVEN** `alice` の最後の取得から 20 秒しかたっていない
- **WHEN** ユーザーが再読み込みを押す
- **THEN** `alice` の `GET /notifications` は送られない

### Requirement: 失敗したときの待ち方

Mewbell は、取得が失敗したとき、そのアカウントで最後に取得できた通知の一覧を残したまま、次のように待ってから再び取得しなければならない（MUST）。

- レート制限（`403`）: `Retry-After` の秒数、または `X-RateLimit-Reset` の時刻まで待つ。どちらも 60 秒より短ければ 60 秒待つ
- 拒否（レート制限でない `403`）、リクエストの誤り（`422`）、一時的な失敗、トークンを送る相手の確認やリダイレクトでの失敗: 60 秒から始めて失敗が続くたびに 2 倍にし、15 分を上限とする

成功した取得の後は、待ち時間を 60 秒からに戻さなければならない（MUST）。

#### Scenario: 通信の失敗が続く

- **GIVEN** `ghe.example.com/dave` の取得が 3 回続けて通信の失敗になった
- **WHEN** Mewbell が次の取得の時刻を決める
- **THEN** 3 回目の失敗から 240 秒後に次の取得をする
- **AND** `dave` の一覧には最後に取得できた通知が残っている

#### Scenario: レート制限

- **GIVEN** API が `403` と `Retry-After: 300` を返した
- **WHEN** Mewbell が次の取得の時刻を決める
- **THEN** 300 秒後まで次の取得をしない

### Requirement: 401 のときのトークンの取り直し

Mewbell は、API が `401` を返したとき、そのアカウントのトークンをメモリから捨て、gh からトークンを 1 回だけ取り直して、すぐに取得をやり直さなければならない（MUST）。やり直すとき `If-Modified-Since` を付けてはならない（MUST NOT）。取り直したトークンでも `401` が返ったとき、またはトークンを取り直せなかったときは、そのアカウントを「認証エラー」にしてポーリングを止めなければならない（MUST）。止めたアカウントについて、ポーリングを自動で再開してはならず（MUST NOT）、ポーリングのためにトークンを取り直してもならない（MUST NOT）。ただし、トークンを捨てた後は、ポップオーバーを開いたときなどの通常の読み直しで、トークンを持っていないアカウントとして gh からトークンを取得してよい（MAY。accounts「読み直しのタイミング」）。

#### Scenario: トークンが失効していた

- **GIVEN** `github.com/alice` のトークンが失効し、gh には新しいトークンがある
- **WHEN** `alice` の取得で API が `401` を返す
- **THEN** Mewbell は `gh auth token --hostname github.com --user alice` を 1 回実行して新しいトークンを受け取る
- **AND** 新しいトークンで `If-Modified-Since` を付けずに取得をやり直し、通知が表示される

#### Scenario: 取り直しても 401

- **GIVEN** gh の `alice` のトークンも失効している
- **WHEN** `alice` の取得で API が `401` を返し、取り直したトークンでも `401` が返る
- **THEN** `alice` は「認証エラー」になり、ポーリングが止まる
- **AND** その後、ユーザーが再読み込みを押すまで `alice` の `GET /notifications` は送られない（ポップオーバーを開いたときの読み直しで `alice` のトークンが取得されても、ポーリングは再開しない）

### Requirement: スコープ不足で止める

Mewbell は、スコープの確認で「スコープ不足」になったアカウントのポーリングを止めなければならない（MUST）。止めたアカウントについて、自動で取得を繰り返してはならない（MUST NOT）。

#### Scenario: スコープの無いトークン

- **GIVEN** `github.com/alice` のトークンの `X-OAuth-Scopes` が `gist, read:org`
- **WHEN** `alice` の最初の取得が終わる
- **THEN** `alice` は「スコープ不足」になり、以後 `GET /notifications` は送られない

### Requirement: 止めたアカウントの再開

Mewbell は、「スコープ不足」か「認証エラー」で止めたアカウントについて、ユーザーが再読み込みを押したときに、トークンを捨てて gh から取り直し、`If-Modified-Since` を付けずに取得を再開しなければならない（MUST）。ポップオーバーを開いただけでは再開してはならない（MUST NOT）。

#### Scenario: スコープを足した後に再読み込みする

- **GIVEN** `github.com/alice` が「スコープ不足」で、ユーザーがターミナルで `gh auth refresh --hostname github.com --scopes repo` を済ませた
- **WHEN** ユーザーが再読み込みを押す
- **THEN** Mewbell は `alice` のトークンを gh から取り直し、`GET /notifications` を送る
- **AND** スコープが足りていれば `alice` の通知が表示される

#### Scenario: ポップオーバーを開いただけでは再開しない

- **GIVEN** `github.com/alice` が「スコープ不足」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `alice` の `gh auth token` と `GET /notifications` は実行されない

### Requirement: 取得の状態

Mewbell はアカウントごとに、通知の取得について次のいずれかの状態を持たなければならない（MUST）: 最初の取得中、取得できた（最後に成功した時刻を持つ）、失敗して待っている（最後に取得できた通知と、次の取得の時刻を持つ）、スコープ不足、認証エラー。状態と通知は、アプリを終了したら残してはならない（MUST NOT）。

#### Scenario: 失敗して待っている

- **GIVEN** `github.com/alice` の通知を 12:00 に取得でき、12:01 の取得が通信の失敗になった
- **WHEN** Mewbell が `alice` の状態を決める
- **THEN** 状態は「失敗して待っている」で、12:00 に取得した通知と次の取得の時刻を持つ
