## MODIFIED Requirements

### Requirement: スレッドの行の状態のアイコン

スレッドに件名の状態（github-api「スレッドの状態の決定」、polling「スレッドのイベントの取得」）が付いているとき、スレッドの行の種類のアイコンは、種類に加えて状態が分かるものにしなければならない（SHALL）。状態は、記号の形と色の両方で区別しなければならず（MUST）、色だけで区別してはならない（MUST NOT）。VoiceOver では、アイコンを種類と状態（例: 「Pull request, merged」）として読ませなければならない（SHALL）。

状態が「分からない」か付いていない Pull request と Issue のアイコンは、種類が分かり、その種類のどの状態のアイコンとも記号の形が違うものにしなければならず（SHALL）、薄い色で出さなければならない（SHALL）。開いている状態と形が同じで色だけが違う記号を使ってはならない（MUST NOT）。VoiceOver では、種類だけ（例: 「Pull request」）として読ませなければならない（SHALL）。状態を持たない種類（Commit、Release、Discussion、Check suite、その他）は、今までどおり種類だけを表すアイコンを出さなければならない（SHALL）。

#### Scenario: マージした Pull request

- **GIVEN** `github.com/alice` の Pull request のスレッドの状態が Merged
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行のアイコンは、マージした Pull request と分かる記号と色になる

#### Scenario: 開いている Issue と閉じた Issue

- **GIVEN** Issue のスレッドが 2 つあり、状態が Open と Closed as completed
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 2 つの行のアイコンは、記号の形と色の両方が違う

#### Scenario: 状態が分からない

- **GIVEN** Pull request のスレッドが 2 つあり、1 つは状態が Open、もう 1 つはイベントをまだ取っていない
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** イベントを取っていない行のアイコンは、Pull request と分かる薄い色の記号で、Open の行のアイコンとは記号の形が違う
- **AND** VoiceOver では「Pull request」と読まれる

#### Scenario: 状態が分からない Issue

- **GIVEN** Issue のスレッドのイベントを取れなかった
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行のアイコンは、Issue と分かる薄い色の記号で、Open・Closed as completed・Closed as not planned のどのアイコンとも記号の形が違う

#### Scenario: 状態を持たない種類

- **GIVEN** 種類が Release のスレッドがある
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行のアイコンは今までどおり Release を表すものになる
