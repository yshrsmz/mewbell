## MODIFIED Requirements

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
