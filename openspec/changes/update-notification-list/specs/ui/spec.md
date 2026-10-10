# Spec Delta

## MODIFIED Requirements

### Requirement: アカウント一覧の表示

全体の状態が「アカウントあり」のとき、ポップオーバーは「無効」以外のアカウントごとの区画を、accounts の並び順で表示しなければならない（SHALL）。「無効」のアカウントの区画は出してはならない（MUST NOT）。すべてのアカウントが「無効」のときは、区画の代わりに、すべてのアカウントが無効であることと、設定ウィンドウを開くボタンを表示しなければならない（SHALL）。区画の見出しにはユーザー名、ホスト名、ホスト種別（GitHub.com / GHE Cloud / Enterprise Server）、トークンの状態（取得中 / 使える / トークンを取れない）を出し、gh のアクティブなアカウントにはそうと分かる印を付けなければならない（SHALL）。「参加しているスレッドだけにする」がオンのアカウントの見出しには、そうと分かる印を付けなければならない（SHALL）。トークンが「使える」アカウントの区画には、見出しに通知の取得の状態を出し、その下に未読の通知をリポジトリ（`owner/name`）ごとにまとめて表示しなければならない（SHALL）。リポジトリは含まれるスレッドの最新の更新日時が新しい順に、スレッドは更新日時が新しい順に並べなければならない（SHALL）。スレッドの行には、種類（Pull request / Issue / Commit / Release / Discussion など）を表すアイコン、件名、理由（`reason`）、更新日時を出さなければならない（SHALL）。Issue と Pull request のスレッドの行には、理由の前にその番号を `#<番号>` の形で出さなければならない（SHALL）。番号は、ui「通知のスレッドを開く」で開く URL を `pulls/<番号>` または `issues/<番号>` から組み立てるときと同じ条件（`subject.url` が API ベース URL と同じオリジンでその下にあり、`<owner>/<name>` がスレッドのリポジトリと一致する）を満たしたときだけ出さなければならない（MUST）。条件を満たさないとき（Commit、Release、Discussion、`subject.url` が無い・形が合わない・別のホストを指すなど）は、番号を出してはならない（MUST NOT）。未読の通知が 0 件のときは、そうと分かる表示を出さなければならない（SHALL）。一覧がポップオーバーに収まらないときは、見出しの「Mewbell」と Quit ボタンを残したまま一覧だけをスクロールできなければならない（SHALL）。トークンの値やその一部、API の URL を表示してはならない（MUST NOT）。

#### Scenario: 2 つのホストのアカウントを表示する

- **GIVEN** `github.com/alice`（使える、アクティブ）と `acme.ghe.com/dave`（使える）がある
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `alice` の区画の見出しに「github.com — GitHub.com」とアクティブの印が、`dave` の区画の見出しに「acme.ghe.com — GHE Cloud」が表示される
- **AND** どちらも「使える」状態として表示される

#### Scenario: 2 つのアカウントの通知を表示する

- **GIVEN** `github.com/alice`（使える、アクティブ）に `octo/app` の通知が 2 件と `octo/lib` の通知が 1 件あり、`acme.ghe.com/dave`（使える）に `acme/web` の通知が 1 件ある
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `alice` の区画（github.com — GitHub.com、アクティブの印付き）の下に `octo/app` と `octo/lib` の見出しと、それぞれのスレッドが表示される
- **AND** `dave` の区画（acme.ghe.com — GHE Cloud）の下に `acme/web` の見出しとスレッドが表示される

#### Scenario: 未読が無い

- **GIVEN** `github.com/alice` の取得ができていて、未読の通知が 0 件
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `alice` の区画に、未読の通知が無いことを示す表示が出る

#### Scenario: トークンを取れないアカウント

- **GIVEN** `ghe.example.com/dave` が「トークンを取れない」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `dave` の区画に警告と、実行すべきコマンド `gh auth login --hostname ghe.example.com` が表示される
- **AND** コマンドをクリップボードにコピーするボタンがある

#### Scenario: 無効のアカウントは出さない

- **GIVEN** `github.com/alice`（使える）と `github.com/bob`（無効）がある
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `alice` の区画だけが表示され、`bob` の区画は無い

#### Scenario: すべてのアカウントが無効

- **GIVEN** `github.com/alice` と `github.com/bob` のどちらも「無効」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** すべてのアカウントが無効であることと、設定ウィンドウを開くボタンが表示される

#### Scenario: 参加しているスレッドだけにしたアカウント

- **GIVEN** `acme.ghe.com/dave` の「参加しているスレッドだけにする」がオン
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `dave` の区画の見出しに、参加しているスレッドだけを表示していることを示す印が出る

#### Scenario: Pull request の番号を出す

- **GIVEN** `github.com/alice` のスレッドのリポジトリが `octo/app`、`subject.url` が `https://api.github.com/repos/octo/app/pulls/42`、理由が `review_requested`
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** そのスレッドの行の件名の下に `#42`、理由、更新日時がこの順に出る

#### Scenario: GHES の Issue の番号を出す

- **GIVEN** `ghe.example.com/dave` のスレッドのリポジトリが `team/svc`、`subject.url` が `https://ghe.example.com/api/v3/repos/team/svc/issues/7`
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** そのスレッドの行に `#7` が出る

#### Scenario: 番号を読めないスレッド

- **GIVEN** `github.com/alice` に、`subject.url` が `https://evil.example.com/repos/octo/app/pulls/42` のスレッドと、種類が Release のスレッドがある
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** どちらの行にも番号は出ず、理由と更新日時だけが出る

## ADDED Requirements

### Requirement: 一覧の折りたたみ

ポップオーバーの一覧では、アカウントの区画とリポジトリのグループを、それぞれの見出しから折りたたんだり開いたりできなければならない（SHALL）。折りたたみの操作にはツールチップとアクセシビリティのラベルを付け、開いているか折りたたんでいるかが分かるようにしなければならない（SHALL）。アカウントの区画を折りたたんだときは、その区画のリポジトリのグループと、未読が無いことの表示を隠さなければならない（SHALL）。見出し、通知の取得の状態、操作の失敗の表示、トークンを取れないときの案内は、折りたたんでいても出し続けなければならない（SHALL）。リポジトリのグループを折りたたんだときは、そのグループのスレッドの行を隠さなければならない（SHALL）。折りたたんだアカウントの見出しにはそのアカウントの未読の一覧の件数を、折りたたんだリポジトリの見出しにはそのグループのスレッドの件数を出さなければならない（SHALL）。

折りたたんだ状態は、アカウント（ホストとユーザー名）と、アカウントとリポジトリ（`owner/name`）の組ごとに、Mewbell が起動している間だけ覚えなければならない（SHALL）。ポップオーバーを閉じて開き直しても、折りたたんだ状態は残らなければならない（SHALL）。折りたたんだ状態をディスク（UserDefaults を含む）に保存してはならず（MUST NOT）、起動した直後はすべての区画とグループを開いた状態にしなければならない（SHALL）。アカウントが一覧から消えたとき（無効にしたときを含む）は、そのアカウントの折りたたんだ状態を捨てなければならない（SHALL）。

折りたたんだアカウントやリポジトリに新着が届いたときは、そのアカウントの区画と、新着を含むリポジトリのグループを開かなければならない（SHALL）。新着は、notifications「新着の通知」で通知の対象になるスレッドと同じもの（基準の取得の後に、初めて現れたスレッドか、前に見たときより `updated_at` が新しくなったスレッド）とし、アカウントの「macOS の通知を出す」の設定にかかわらず決めなければならない（MUST）。新着を含まない、ほかの折りたたんだリポジトリのグループを開いてはならない（MUST NOT）。基準の取得（起動した直後、アカウントを有効に戻した後、「参加しているスレッドだけにする」を切り替えた後の最初の取得）と、既読化や Done が失敗して同じ `updated_at` のまま一覧に戻ったスレッドでは、開いてはならない（MUST NOT）。折りたたみは表示だけを変え、未読バッジの件数、macOS の通知、ポーリングを変えてはならない（MUST NOT）。

#### Scenario: リポジトリを折りたたむ

- **GIVEN** `github.com/alice` に `octo/app` の通知が 2 件と `octo/lib` の通知が 1 件ある
- **WHEN** ユーザーが `octo/app` の見出しで折りたたむ
- **THEN** `octo/app` の 2 件の行が隠れ、見出しに `2` と出る
- **AND** `octo/lib` の行は出たまま
- **AND** メニューバーの件数は `3` のまま

#### Scenario: アカウントを折りたたむ

- **GIVEN** `github.com/alice` に未読が 3 件あり、最後に取得できた時刻が表示されている
- **WHEN** ユーザーが `alice` の見出しで折りたたむ
- **THEN** `alice` のリポジトリのグループがすべて隠れ、見出しに `3` と出る
- **AND** 最後に取得できた時刻の表示は出たまま

#### Scenario: ポップオーバーを閉じても残る

- **GIVEN** ユーザーが `octo/app` を折りたたんだ
- **WHEN** ポップオーバーを閉じて開き直す
- **THEN** `octo/app` は折りたたまれたまま

#### Scenario: 再起動するとすべて開く

- **GIVEN** ユーザーが `alice` の区画と `octo/app` を折りたたんだ
- **WHEN** Mewbell を終了して起動し直す
- **THEN** すべての区画とグループが開いた状態で表示される

#### Scenario: 新着で開く

- **GIVEN** `alice` の区画と、`alice` の `octo/app` と `octo/lib` を折りたたんでいる
- **WHEN** 次の取得で `octo/app` に新しいスレッドが届く
- **THEN** `alice` の区画と `octo/app` のグループが開く
- **AND** `octo/lib` は折りたたまれたまま

#### Scenario: 通知をオフにしたアカウントでも開く

- **GIVEN** `alice` の「macOS の通知を出す」がオフで、`octo/app` を折りたたんでいる
- **WHEN** 次の取得で `octo/app` のスレッドの `updated_at` が新しくなる
- **THEN** macOS の通知は出ず、`octo/app` のグループが開く

#### Scenario: 失敗して戻ったスレッドでは開かない

- **GIVEN** `octo/app` を折りたたんでいて、その中のスレッド `123` を既読にしたが既読化が失敗した
- **WHEN** 次の取得で `123` が同じ `updated_at` のまま一覧に戻る
- **THEN** `octo/app` は折りたたまれたまま
