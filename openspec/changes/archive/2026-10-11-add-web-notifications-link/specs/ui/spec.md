# Spec Delta

## ADDED Requirements

### Requirement: Web の通知一覧を開く

一覧に出ているアカウントの区画（無効のアカウントの区画は出さない）の見出しには、そのアカウントのホストの Web の通知一覧を既定のブラウザで開くボタンがなければならない（SHALL）。ボタンは、トークンの状態（取得中・使える・取得できない）と取得の状態（取得中・取得できた・失敗して待っている・スコープ不足・認証エラー）にかかわらず出して、押せるようにしなければならない（SHALL）。開く URL は、アカウントの Web ベース URL（`https://<host>`）に `notifications` を足した `https://<host>/notifications` でなければならず（MUST）、クエリ（`query=` などの絞り込み）を付けてはならない（MUST NOT）。アカウントの「参加しているスレッドだけにする」の設定は URL に反映してはならない（MUST NOT）。開く前に、URL のスキームが `https` で、ホストがアカウントのホストと一致し、ポートとユーザー情報を含まないことを確かめ、満たさなければ開いてはならない（MUST NOT）。ボタンを押しても、スレッドの既読・Done・すべて既読のリクエストを送ってはならず（MUST NOT）、一覧のスレッドを外してはならない（MUST NOT）。ボタンには、開く先のホストを含むツールチップとアクセシビリティのラベル（`Open notifications on <host>` など）を付けなければならない（SHALL）。

#### Scenario: github.com のアカウントの通知一覧を開く

- **GIVEN** `github.com/alice` の一覧に 3 件ある
- **WHEN** ユーザーが `alice` の見出しの Web の通知一覧のボタンを押す
- **THEN** 既定のブラウザで `https://github.com/notifications` が開く
- **AND** `alice` の一覧の 3 件は残り、既読化のリクエストは送られない

#### Scenario: GHE Cloud と GHES のアカウント

- **GIVEN** `acme.ghe.com/dave` と `ghe.example.com/erin` がある
- **WHEN** ユーザーが `dave` の見出しのボタンを押し、続けて `erin` の見出しのボタンを押す
- **THEN** `https://acme.ghe.com/notifications` と `https://ghe.example.com/notifications` がそれぞれ開く
- **AND** API ベース URL（`https://api.acme.ghe.com`、`https://ghe.example.com/api/v3`）は開かない

#### Scenario: 参加しているスレッドだけにしたアカウント

- **GIVEN** `github.com/alice` の「参加しているスレッドだけにする」がオン
- **WHEN** ユーザーが `alice` の見出しのボタンを押す
- **THEN** 開く URL は `https://github.com/notifications` で、クエリを含まない

#### Scenario: 取得が止まっているアカウント

- **GIVEN** `github.com/bob` がスコープ不足で止まっていて、`ghe.example.com/frank` はトークンを取得できない
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `bob` と `frank` の見出しにも Web の通知一覧のボタンが出て、押すとそれぞれ `https://github.com/notifications` と `https://ghe.example.com/notifications` が開く

#### Scenario: 無効のアカウント

- **GIVEN** `github.com/carol` が無効
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `carol` の区画は出ず、`carol` の Web の通知一覧のボタンも出ない
