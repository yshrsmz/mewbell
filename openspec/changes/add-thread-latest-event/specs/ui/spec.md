## ADDED Requirements

### Requirement: スレッドの行のイベント

スレッドにイベント（polling「スレッドのイベントの取得」）が付いているとき、スレッドの行は、件名の下の行の番号（出すとき）と理由の間に、イベントの表示を出さなければならない（SHALL）。イベントが付いていないときは、今までどおり番号・理由・更新日時だけを出さなければならない（SHALL）。イベントを取っている間やイベントの取得に失敗したときに、そうと分かる表示（読み込み中の印やエラー）を行に出してはならない（MUST NOT）。

イベントの表示は、github-api「スレッドのイベントの決定」のイベント名に、実行者があれば ` by <ログイン名>` を付けたものにしなければならない（SHALL）（例: `Closed by alice`、`Approved by bob`、`Pushed commits`）。表示してよいのは、決まったイベント名と検証済みのログイン名だけで、Timeline の `event` の値やコメントの本文をそのまま出してはならない（MUST NOT）。

#### Scenario: イベントが付いた行

- **GIVEN** `github.com/alice` のスレッドが `octo/app#42`、理由が `subscribed`、イベントが Closed by `alice`、3 分前に更新された
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** そのスレッドの行の件名の下に `#42`、`Closed by alice`、`Watching`、更新日時がこの順に出る

#### Scenario: 実行者の無いイベント

- **GIVEN** スレッドのイベントが Pushed commits で、番号が `#41`、理由が `review_requested`
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行の件名の下に `#41`、`Pushed commits`、`Review requested`、更新日時がこの順に出る

#### Scenario: イベントの無い行

- **GIVEN** 種類が Release のスレッドがある
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行には理由と更新日時だけが出る
