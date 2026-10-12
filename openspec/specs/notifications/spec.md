# notifications Specification

## Purpose
新しく届いた GitHub の通知スレッドを macOS の通知で知らせ、既読や Done で不要になった通知を取り下げ、通知のクリックからスレッドを開いて既読にするまでの振る舞いを定める。

## Requirements

### Requirement: 通知の許可

Mewbell は起動したとき、macOS の通知（バナーと音）を出す許可を求めなければならない（SHALL）。許可されていないときは macOS の通知を出さず、それ以外の振る舞い（通知の取得、一覧、未読バッジ）は変えてはならない（MUST NOT）。テストのホストや SwiftUI プレビューとして起動されたときは、許可を求めてはならない（MUST NOT）。

#### Scenario: 初めて起動する

- **GIVEN** Mewbell に通知の許可を一度も求めたことがない
- **WHEN** ユーザーが Mewbell を起動する
- **THEN** macOS の通知の許可を求めるダイアログが出る

#### Scenario: 通知を許可していない

- **GIVEN** ユーザーが Mewbell の通知を許可していない
- **WHEN** `github.com/alice` に新しいスレッドが届く
- **THEN** macOS の通知は出ない
- **AND** ポップオーバーの一覧と未読バッジにはそのスレッドが入る

### Requirement: 新着の通知

Mewbell は、アカウントの取得が成功した（polling「取得の状態」が「取得できた」になった）たびに、そのアカウントの未読のスレッドのうち次のものについて、macOS の通知を 1 スレッドにつき 1 つ出さなければならない（SHALL）。

- このアプリの実行中に、そのアカウントで初めて見たスレッド
- 前に見たときより `updated_at` が新しくなったスレッド

ただし、アカウントの最初の成功した取得（起動直後、アカウントが増えたとき、止まったアカウントの再開の後、設定でアカウントを有効にし直した後、設定で「参加しているスレッドだけにする」を切り替えた後。その前に取得が失敗して待っていた場合も含む）で得たスレッドは通知せず、見たものとして覚えるだけにしなければならない（MUST）。設定で「macOS の通知を出す」をオフにしたアカウントは、macOS の通知を出してはならない（MUST NOT）。その間も見たスレッドは覚え続け、オンに戻したときに、オフの間に届いたスレッドをまとめて通知してはならない（MUST NOT）。通知の識別子は `<host>/<user>/<threadId>` にしなければならず（MUST）、同じスレッドを出し直すときは同じ識別子で置き換えなければならない（MUST）。同じスレッドの通知を 2 つ以上並べてはならない（MUST NOT）。Mewbell の画面が前面にあるときも、通知をバナーとして出さなければならない（SHALL）。

#### Scenario: 起動直後の未読は通知しない

- **GIVEN** `github.com/alice` に未読のスレッドが 12 件ある
- **WHEN** Mewbell を起動し、`alice` の最初の取得が成功する
- **THEN** macOS の通知は出ない
- **AND** 一覧には 12 件が表示される

#### Scenario: 新しいスレッドが届く

- **GIVEN** `github.com/alice` の最初の取得が済んでいる
- **WHEN** 次の取得で、ID `123` の新しいスレッドが返る
- **THEN** 識別子 `github.com/alice/123` の macOS の通知が 1 つ出る

#### Scenario: 同じスレッドに動きがある

- **GIVEN** 識別子 `github.com/alice/123` の通知を出した後、スレッド `123` の `updated_at` が進んだ
- **WHEN** 次の取得でスレッド `123` が返る
- **THEN** 識別子 `github.com/alice/123` の通知が新しい内容で置き換わり、通知センターに `123` の通知は 1 つだけある

#### Scenario: 変わっていないスレッド

- **GIVEN** スレッド `123` の通知を出した後、`updated_at` は変わっていない
- **WHEN** 次の取得（`304` を含む）が成功する
- **THEN** `123` の通知は出し直さない

#### Scenario: 遅れて届いたスレッド

- **GIVEN** `github.com/alice` の最初の取得が済んでいて、Watch 経由のスレッド `456` が、一覧の最新のスレッドより古い `updated_at` で後から受信箱に入った
- **WHEN** 条件なしの取得で `456` が返る
- **THEN** `github.com/alice/456` の通知が出る

#### Scenario: 再開の後は通知しない

- **GIVEN** `github.com/alice` が「認証エラー」で止まっている間に、未読が 3 件増えた
- **WHEN** ユーザーが再読み込みを押し、`alice` の取得が再開して成功する
- **THEN** その 3 件の通知は出ない

#### Scenario: 参加しているスレッドだけにするのをやめる

- **GIVEN** `github.com/alice` が「参加しているスレッドだけにする」で、参加していないスレッドが 20 件未読になっている
- **WHEN** ユーザーが設定で `alice` の「参加しているスレッドだけにする」をオフにし、`alice` の取得が成功する
- **THEN** 一覧に 20 件が加わるが、その 20 件の macOS の通知は出ない

#### Scenario: 通知をオフにしたアカウント

- **GIVEN** `github.com/alice` は「macOS の通知を出す」がオフで、`acme.ghe.com/dave` はオン
- **WHEN** 両方の次の取得で、それぞれ新しいスレッドが 1 件ずつ返る
- **THEN** `dave` のスレッドの通知だけが出る
- **AND** `alice` のスレッドは一覧と未読バッジには入る

#### Scenario: 通知をオンに戻す

- **GIVEN** `github.com/alice` の「macOS の通知を出す」がオフの間に、新しいスレッドが 5 件届いて一覧に入った
- **WHEN** ユーザーが `alice` の「macOS の通知を出す」をオンに戻し、次の取得で新しいスレッド `789` が返る
- **THEN** `github.com/alice/789` の通知だけが出て、オフの間に届いた 5 件の通知は出ない

### Requirement: 通知の中身

macOS の通知のタイトルはスレッドの件名（`subject.title`）、サブタイトルはリポジトリの `owner/name` にしなければならない（SHALL）。本文は、スレッドにイベント（polling「スレッドのイベントの取得」）が付いているときは、イベントの表示（ui「スレッドの行のイベント」と同じ文言）、理由（`reason`）の表示、アカウント（`<user> (<host>)`）をこの順に ` · ` でつないだものにし、付いていないときは理由の表示とアカウントにしなければならない（SHALL）。設定で「macOS の通知に音を付ける」がオンのときは既定の通知音を付け、オフのときは音を付けてはならない（MUST NOT）。同じアカウントの通知は、通知センターでまとまるようにしなければならない（SHALL）。通知の本文・タイトル・サブタイトル・添付の情報（`userInfo`）に、トークンやその一部、API の URL、コメントの本文を入れてはならない（MUST NOT）。`userInfo` に入れてよいのは、ホスト名、ユーザー名、スレッド ID、リポジトリの `owner/name`、ui「通知のスレッドを開く」の規則で組み立てた Web の URL だけとする（MUST）。

#### Scenario: Pull request のレビュー依頼

- **GIVEN** `github.com/alice` に、`octo/app` の Pull request「Fix login」のスレッドが `reason: review_requested` で届き、イベントが付いていない
- **WHEN** Mewbell が通知を出す
- **THEN** タイトルは「Fix login」、サブタイトルは「octo/app」で、本文にレビュー依頼であることと `alice (github.com)` が入る
- **AND** 通知のどこにもトークンと `https://api.github.com/...` の URL は入っていない

#### Scenario: イベントが付いたスレッド

- **GIVEN** `github.com/alice` に、`octo/app` の Issue「Crash on start」のスレッドが `reason: subscribed` で届き、イベント Closed by `bob` が付いている
- **WHEN** Mewbell が通知を出す
- **THEN** 本文は `Closed by bob · Watching · alice (github.com)` になる

#### Scenario: 音をオフにする

- **GIVEN** ユーザーが設定で「macOS の通知に音を付ける」をオフにした
- **WHEN** `github.com/alice` に新しいスレッドが届き、Mewbell が通知を出す
- **THEN** 通知は音なしで出る

### Requirement: 通知の取り下げ

Mewbell は、次のときに macOS の通知を取り下げ（通知センターから消し）なければならない（MUST）。

- アカウントの取得が成功し、通知したスレッドがその未読の一覧に無いとき（Mewbell・Web・別のクライアントで既読や Done にしたとき）は、そのスレッドの通知
- Mewbell でスレッドを既読か Done にしたとき（polling「スレッドの既読化」「スレッドの Done」）は、取得を待たずにそのスレッドの通知
- Mewbell でアカウントの通知をすべて既読にしたとき（polling「アカウントのすべて既読」）は、取得を待たずに、そのとき一覧から外したスレッドの通知
- アカウントが一覧から消えたとき、全体の状態が「アカウントあり」以外になったとき、アカウントの取得が「スコープ不足」か「認証エラー」で止まったとき、ユーザーが設定でアカウントを無効にしたとき、ユーザーが設定でアカウントの「macOS の通知を出す」をオフにしたときは、そのアカウントの通知すべて
- アカウントの読み込みが終わったとき、無効のアカウントの通知すべて（前回までの実行で出したものを含む）
- 起動後、アカウントの最初の取得が成功したとき（設定で「参加しているスレッドだけにする」を切り替えた後の最初の取得を含む）は、前回までの実行や切り替える前に出したそのアカウントの通知のうち、今の未読の一覧に無いもの

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

#### Scenario: 無効にしたアカウント

- **GIVEN** `github.com/bob/789` と `github.com/alice/123` の通知が通知センターにある
- **WHEN** ユーザーが設定で `bob` を無効にする
- **THEN** `github.com/bob/789` の通知はすぐに消え、`github.com/alice/123` の通知は残る

#### Scenario: 通知をオフにしたアカウント

- **GIVEN** `github.com/alice/123` の通知が通知センターにある
- **WHEN** ユーザーが設定で `alice` の「macOS の通知を出す」をオフにする
- **THEN** `github.com/alice/123` の通知はすぐに消え、`alice` の一覧にはスレッド `123` が残る

#### Scenario: 無効のアカウントの前回の通知

- **GIVEN** 前回の実行で出した `github.com/bob/789` の通知が残っていて、`bob` は無効にしてある
- **WHEN** Mewbell を起動し、アカウントの読み込みが終わる
- **THEN** `github.com/bob/789` の通知は消える

### Requirement: 通知のクリック

ユーザーが macOS の通知をクリックしたとき、Mewbell はそのスレッドの Web ページを既定のブラウザで開き、続けてそのスレッドを既読にしなければならない（SHALL。polling「スレッドの既読化」）。通知から戻ってきた値（`userInfo`）は使う前に検証し直さなければならない（MUST）: ホスト名とユーザー名が gh-cli「ホスト名とユーザー名の検証」を通ること、スレッド ID が 1〜20 桁の数字であること、開く URL のスキームが `https` でホストが通知のアカウントのホストと一致すること。URL が検証を通らなければ、URL は開かずにリポジトリのページ（`https://<host>/<owner>/<name>`、`owner/name` も検証を通ったときだけ）を開かなければならない（MUST）。ホスト名・ユーザー名・スレッド ID のどれかが検証を通らなければ、何も開かず既読にもしてはならない（MUST NOT）。

通知のアカウントが一覧にあって、まだトークンを持っていない（起動の直後など）ときは、トークンを得て取得を始めるときに既読にしなければならない（SHALL）。そのアカウントが、アカウントの読み込みが終わった後も一覧に無いか、「トークンを取れない」のときは、既読にしなくてよい（MAY）。そのアカウントが「無効」のときは、ページは開くが、既読にしてはならない（MUST NOT。無効のアカウントのトークンは取得しないため）。Mewbell が起動していないときに通知がクリックされた場合も、起動してから同じように扱わなければならない（SHALL）。

#### Scenario: 通知をクリックする

- **GIVEN** `github.com/alice` の `octo/app` の Pull request #42 のスレッド `123` の通知が出ている
- **WHEN** ユーザーがその通知をクリックする
- **THEN** 既定のブラウザで `https://github.com/octo/app/pull/42` が開く
- **AND** `PATCH https://api.github.com/notifications/threads/123` が `alice` のトークンで送られる
- **AND** スレッド `123` は一覧から消える

#### Scenario: 終了している間にクリックする

- **GIVEN** Mewbell が終了していて、前回の実行で出した `github.com/alice/123` の通知が残っている
- **WHEN** ユーザーがその通知をクリックする
- **THEN** Mewbell が起動して、スレッドの Web ページが開く
- **AND** `alice` のトークンを得た後に、スレッド `123` を既読にする

#### Scenario: userInfo の URL が別のホストを指している

- **GIVEN** `github.com/alice` の通知の `userInfo` の URL が `https://evil.example.com/octo/app/pull/42` で、`owner/name` が `octo/app`
- **WHEN** ユーザーがその通知をクリックする
- **THEN** `https://github.com/octo/app` が開き、`evil.example.com` は開かない

#### Scenario: スレッド ID が数字でない

- **GIVEN** 通知の `userInfo` のスレッド ID が `../user`
- **WHEN** ユーザーがその通知をクリックする
- **THEN** 何も開かず、API へのリクエストも送らない

#### Scenario: 無効のアカウントの通知をクリックする

- **GIVEN** Mewbell が終了していて、前回の実行で出した `github.com/bob/789` の通知が残っていて、`bob` は無効にしてある
- **WHEN** ユーザーがその通知をクリックする
- **THEN** Mewbell が起動して、スレッドの Web ページが開く
- **AND** `bob` のための `gh auth token` と `PATCH /notifications/threads/789` は送られない
