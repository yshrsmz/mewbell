# Spec Delta

## MODIFIED Requirements

### Requirement: 通知のスレッドを開く

ポップオーバーの一覧でスレッドをクリックすると、Mewbell はそのスレッドの Web ページを既定のブラウザで開き、続けてそのスレッドを既読にしなければならない（SHALL。polling「スレッドの既読化」）。開く URL は、API のレスポンスに含まれる URL をそのまま使わず、アカウントの Web ベース URL、リポジトリの `owner/name`、`subject.url` のパスから次のように組み立てなければならない（MUST）。

- `subject.url` が API ベース URL と同じオリジンで、パスが API ベース URL のパスに続く `repos/<owner>/<name>/pulls/<番号>` のとき: `<Web ベース>/<owner>/<name>/pull/<番号>`
- 同じく `.../issues/<番号>` のとき: `<Web ベース>/<owner>/<name>/issues/<番号>`
- 同じく `.../commits/<16 進の SHA>` のとき: `<Web ベース>/<owner>/<name>/commit/<SHA>`
- 種類が Release のとき: `<Web ベース>/<owner>/<name>/releases`
- 種類が Discussion のとき: `<Web ベース>/<owner>/<name>/discussions`
- それ以外（`subject.url` が無い、形が合わない、`subject.url` の `<owner>/<name>` がスレッドのリポジトリと一致しない、などを含む）: `<Web ベース>/<owner>/<name>`

開く前に、組み立てた URL のスキームが `https` で、ホストがアカウントのホストと一致することを確かめ、一致しなければ開いてはならない（MUST NOT）。開かなかったときは、既読にもしてはならない（MUST NOT）。

#### Scenario: Pull request を開く

- **GIVEN** `github.com/alice` のスレッドのリポジトリが `octo/app`、`subject.url` が `https://api.github.com/repos/octo/app/pulls/42`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/pull/42` が開く
- **AND** スレッドは一覧から消え、既読化のリクエストが送られる

#### Scenario: GHES の Issue を開く

- **GIVEN** `ghe.example.com/dave` のスレッドのリポジトリが `team/svc`、`subject.url` が `https://ghe.example.com/api/v3/repos/team/svc/issues/7`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://ghe.example.com/team/svc/issues/7` が開く

#### Scenario: subject.url が別のホストを指している

- **GIVEN** `github.com/alice` のスレッドのリポジトリが `octo/app`、`subject.url` が `https://evil.example.com/repos/octo/app/pulls/42`
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app` が開く
- **AND** `evil.example.com` の URL は開かない

#### Scenario: subject.url が無い

- **GIVEN** スレッドの種類が CheckSuite で、`subject.url` が無い
- **WHEN** ユーザーがそのスレッドをクリックする
- **THEN** リポジトリのページが開く

## ADDED Requirements

### Requirement: 未読バッジ

メニューバーの猫アイコンの横には、全アカウントの未読の一覧（ポップオーバーに表示しているスレッド）の件数の合計を出さなければならない（SHALL）。合計が 0 件のときは数字を出してはならず（MUST NOT）、100 件以上のときは `99+` と出さなければならない（SHALL）。件数は一覧が変わったとき（取得、既読化、アカウントの増減）にすぐ変わらなければならない（SHALL）。取得が失敗して待っているアカウントは、最後に取得できたスレッドを数え、止まっているアカウントとトークンを取れないアカウントは 0 件として数えなければならない（SHALL）。アイコンと数字は、ライトとダークのどちらの外観でもメニューバーのほかのアイコンと同じように判別できなければならない（SHALL）。

#### Scenario: 2 つのアカウントの未読

- **GIVEN** `github.com/alice` に未読が 3 件、`acme.ghe.com/dave` に未読が 2 件ある
- **WHEN** 両方の取得が成功する
- **THEN** メニューバーの猫アイコンの横に `5` と出る

#### Scenario: 未読が無い

- **GIVEN** すべてのアカウントで未読が 0 件
- **WHEN** メニューバーを見る
- **THEN** 猫アイコンだけが出て、数字は出ない

#### Scenario: 既読にすると減る

- **GIVEN** メニューバーに `5` と出ている
- **WHEN** ユーザーが一覧のスレッドを 1 つ開く
- **THEN** 次の取得を待たずに `4` になる

#### Scenario: 100 件以上

- **GIVEN** 未読の合計が 120 件
- **WHEN** メニューバーを見る
- **THEN** 猫アイコンの横に `99+` と出る

### Requirement: 通知が許可されていないときの案内

macOS の通知が許可されていない（拒否された、またはオフにされた）とき、ポップオーバーは一覧の上に、macOS の通知が切られていることと、システム設定の通知の画面を開くボタンを出さなければならない（SHALL）。許可されたら、ポップオーバーを次に開いたときに案内を消さなければならない（SHALL）。まだ許可を求めていないときと、許可を求めている途中は、案内を出してはならない（MUST NOT）。

#### Scenario: 通知を拒否した

- **GIVEN** ユーザーが Mewbell の通知を許可しなかった
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 通知が切られていることと、システム設定を開くボタンが出る
- **AND** 通知の一覧はいつもどおり表示される

#### Scenario: 後から許可する

- **GIVEN** 案内が出ている
- **WHEN** ユーザーがシステム設定で Mewbell の通知を許可し、ポップオーバーを開き直す
- **THEN** 案内は出ない
