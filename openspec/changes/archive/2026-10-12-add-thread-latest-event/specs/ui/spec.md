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

### Requirement: スレッドの行の状態のアイコン

スレッドに件名の状態（github-api「スレッドの状態の決定」、polling「スレッドのイベントの取得」）が付いているとき、スレッドの行の種類のアイコンは、種類に加えて状態が分かるものにしなければならない（SHALL）。状態は、記号の形と色の両方で区別しなければならず（MUST）、色だけで区別してはならない（MUST NOT）。VoiceOver では、アイコンを種類と状態（例: 「Pull request, merged」）として読ませなければならない（SHALL）。状態が「分からない」か付いていないときは、今までどおり種類だけを表すアイコンを出さなければならない（SHALL）。

#### Scenario: マージした Pull request

- **GIVEN** `github.com/alice` の Pull request のスレッドの状態が Merged
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行のアイコンは、マージした Pull request と分かる記号と色になる

#### Scenario: 開いている Issue と閉じた Issue

- **GIVEN** Issue のスレッドが 2 つあり、状態が Open と Closed as completed
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 2 つの行のアイコンは、記号の形と色の両方が違う

#### Scenario: 状態が分からない

- **GIVEN** Pull request のスレッドのイベントをまだ取っていない
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行のアイコンは今までどおり Pull request を表すものになる
