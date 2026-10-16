## MODIFIED Requirements

### Requirement: スレッドの行の状態のアイコン

スレッドに件名の状態（github-api「スレッドの状態の決定」、polling「スレッドのイベントの取得」）が付いているとき、スレッドの行の種類のアイコンは、種類に加えて状態が分かるものにしなければならない（SHALL）。状態どうしは、記号の形と色の両方で区別しなければならず（MUST）、色だけで区別してはならない（MUST NOT）。VoiceOver では、アイコンを種類と状態（例: 「Pull request, merged」）として読ませなければならない（SHALL）。

状態のアイコンの色は、GitHub の Web が同じ状態に使う色（GitHub のデザインシステム Primer の状態の色）にしなければならない（SHALL）。開いている Pull request と Issue は open の緑、マージせずに閉じた Pull request は closed の赤、マージした Pull request と完了として閉じた Issue は done の紫にする。下書きの Pull request と、対応しないで閉じた Issue は、薄い色（システムの副次的な色）で出す。色は、外観（ライト・ダーク）と「コントラストを上げる」の設定に合わせて、Primer の対応するテーマの値に変えなければならない（SHALL）。値は次のとおりにする（Primer 11.10.0 の `fgColor-open`・`fgColor-closed`・`fgColor-done`）。

| 色 | ライト | ダーク | ライト・コントラストを上げる | ダーク・コントラストを上げる |
|---|---|---|---|---|
| open の緑 | `#1A7F37` | `#3FB950` | `#04591F` | `#2BD853` |
| closed の赤 | `#D1242F` | `#F85149` | `#960D1E` | `#FF9492` |
| done の紫 | `#8250DF` | `#AB7DF8` | `#5E2BB4` | `#D3ABFF` |

システムの紫・赤・緑など、GitHub の Web と違う色を状態のアイコンに使ってはならない（MUST NOT）。設定や外観が変わったときは、ポップオーバーを開き直さなくても、次に描くときから新しい色で出さなければならない（SHALL）。

状態が「分からない」か付いていないとき、またはスレッドの種類に合わない状態が付いているときは、状態として扱わず、種類だけを表すアイコンを薄い色で出さなければならない（SHALL）。このアイコンは、その種類の状態のアイコン（例: 開いている Pull request の緑のアイコン）と記号の形が同じで色だけが違ってもよい。形と色の両方で区別する決まりは、状態どうしにだけ適用する。状態が分からないことを示すために、種類を表す記号の代わりに種類によらない記号（例: 疑問符）を使ってはならず（MUST NOT）、状態が分からない Pull request と Issue は記号で見分けられなければならない（SHALL）。VoiceOver では、種類だけ（例: 「Pull request」）として読ませなければならない（SHALL）。

#### Scenario: マージした Pull request

- **GIVEN** `github.com/alice` の Pull request のスレッドの状態が Merged
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行のアイコンは、マージした Pull request と分かる記号と色になる

#### Scenario: マージした Pull request は GitHub の紫で出る

- **GIVEN** 外観がライトで、「コントラストを上げる」がオフ
- **AND** Pull request のスレッドの状態が Merged
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行のアイコンは `#8250DF` の紫で出る
- **AND** システムの紫（`#AF52DE`）では出ない

#### Scenario: 閉じた Pull request とマージした Pull request

- **GIVEN** Pull request のスレッドが 2 つあり、状態が Closed と Merged
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** Closed の行は GitHub の closed の赤、Merged の行は GitHub の done の紫で出る
- **AND** 2 つの行のアイコンは記号の形も違う

#### Scenario: ダークの外観

- **GIVEN** 外観がダークで、「コントラストを上げる」がオフ
- **AND** Issue のスレッドが 2 つあり、状態が Open と Closed as completed
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** Open の行のアイコンは `#3FB950`、Closed as completed の行のアイコンは `#AB7DF8` で出る

#### Scenario: コントラストを上げる

- **GIVEN** 外観がライトで、「コントラストを上げる」がオン
- **AND** Pull request のスレッドの状態が Closed
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 行のアイコンは `#960D1E` の赤で出る

#### Scenario: 薄い色のままの状態

- **GIVEN** 下書きの Pull request のスレッドと、状態が Closed as not planned の Issue のスレッドがある
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 2 つの行のアイコンは、GitHub の色ではなく薄い色で出る

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
