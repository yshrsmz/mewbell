# Spec Delta

## MODIFIED Requirements

### Requirement: 通知の取り下げ

Mewbell は、次のときに macOS の通知を取り下げ（通知センターから消し）なければならない（MUST）。

- アカウントの取得が成功し、通知したスレッドがその未読の一覧に無いとき（Mewbell・Web・別のクライアントで既読や Done にしたとき）は、そのスレッドの通知
- Mewbell でスレッドを既読か Done にしたとき（polling「スレッドの既読化」「スレッドの Done」）は、取得を待たずにそのスレッドの通知
- Mewbell でアカウントの通知をすべて既読にしたとき（polling「アカウントのすべて既読」）は、取得を待たずに、そのとき一覧から外したスレッドの通知
- アカウントが一覧から消えたとき、全体の状態が「アカウントあり」以外になったとき、アカウントの取得が「スコープ不足」か「認証エラー」で止まったときは、そのアカウントの通知すべて
- 起動後、アカウントの最初の取得が成功したときは、前回までの実行で出したそのアカウントの通知のうち、今の未読の一覧に無いもの

取得が失敗して待っている間は、通知を取り下げてはならない（MUST NOT）。

#### Scenario: Web で既読にする

- **GIVEN** `github.com/alice/123` の通知が通知センターにある
- **WHEN** ユーザーが Web でスレッド `123` を既読にし、その後の取得で `123` が未読の一覧に無い
- **THEN** `github.com/alice/123` の通知が通知センターから消える

#### Scenario: ログアウトしたアカウント

- **GIVEN** `github.com/bob` の通知が 2 つ通知センターにある
- **WHEN** ユーザーが `gh auth logout --user bob` を実行し、Mewbell がアカウントを読み直す
- **THEN** `bob` の通知はすべて通知センターから消える

#### Scenario: 前回の実行の通知

- **GIVEN** 前回の実行で出した `github.com/alice/123` と `github.com/alice/456` の通知が通知センターに残っていて、終了している間に Web で `123` を既読にした
- **WHEN** Mewbell を起動し、`alice` の最初の取得が成功する
- **THEN** `github.com/alice/123` の通知は消え、`github.com/alice/456` の通知は残る

#### Scenario: 通信の失敗では消さない

- **GIVEN** `github.com/alice/123` の通知が通知センターにある
- **WHEN** `alice` の取得が通信の失敗になる
- **THEN** `github.com/alice/123` の通知は残る

#### Scenario: Done にする

- **GIVEN** `github.com/alice/123` の通知が通知センターにある
- **WHEN** ユーザーがポップオーバーの一覧でスレッド `123` を Done にする
- **THEN** 次の取得を待たずに、`github.com/alice/123` の通知が通知センターから消える

#### Scenario: すべて既読にする

- **GIVEN** `github.com/alice/123` と `github.com/alice/456`、`github.com/bob/789` の通知が通知センターにある
- **WHEN** ユーザーが `alice` の通知をすべて既読にする
- **THEN** 次の取得を待たずに、`github.com/alice/123` と `github.com/alice/456` の通知が消える
- **AND** `github.com/bob/789` の通知は残る
