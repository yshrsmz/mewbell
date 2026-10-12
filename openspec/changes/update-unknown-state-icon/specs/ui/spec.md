## MODIFIED Requirements

### Requirement: スレッドの行の状態のアイコン

スレッドに件名の状態（github-api「スレッドの状態の決定」、polling「スレッドのイベントの取得」）が付いているとき、スレッドの行の種類のアイコンは、種類に加えて状態が分かるものにしなければならない（SHALL）。状態どうしは、記号の形と色の両方で区別しなければならず（MUST）、色だけで区別してはならない（MUST NOT）。VoiceOver では、アイコンを種類と状態（例: 「Pull request, merged」）として読ませなければならない（SHALL）。

状態が「分からない」か付いていないとき、またはスレッドの種類に合わない状態が付いているときは、状態として扱わず、種類だけを表すアイコンを薄い色で出さなければならない（SHALL）。このアイコンは、種類が分かるものであればよく、その種類の状態のアイコン（例: 開いている Pull request の緑のアイコン）と記号の形が同じで色だけが違ってもよい。形と色の両方で区別する決まりは、状態どうしにだけ適用する。状態が分からないことを示すために、種類が見分けられなくなる記号（例: 種類によらない疑問符）を使ってはならない（MUST NOT）。VoiceOver では、種類だけ（例: 「Pull request」）として読ませなければならない（SHALL）。

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
- **THEN** 行のアイコンは、Pull request を表す記号を薄い色で出したものになる
- **AND** VoiceOver では「Pull request」と読まれる

#### Scenario: 状態が分からない Issue

- **GIVEN** Issue のスレッドのイベントを取れなかった
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行のアイコンは、Issue を表す記号を薄い色で出したものになる
- **AND** VoiceOver では「Issue」と読まれる

#### Scenario: 種類に合わない状態

- **GIVEN** Issue のスレッドに、Pull request にしか無い状態（Merged）が付いている
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行のアイコンは、状態が分からない Issue と同じになる
