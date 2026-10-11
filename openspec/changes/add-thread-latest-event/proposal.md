# Proposal

## Why

一覧の行と macOS の通知に出している「Comment」「Watching」などは API の `reason`（なぜ自分に届いたか）で、スレッドで何が起きたかは分からない。Watch しているリポジトリのスレッドは、コメントでもクローズでもマージでも `subscribed` のままなので、開いてみるまで中身の見当が付かない。GitHub の Web の通知一覧と同じ程度に「誰が何をしたか」を一覧と通知で見られるようにしたい。

M4（設定と操作）の後の、一覧と通知の情報を増やす改善として扱う。

## What Changes

- Issue と Pull request のスレッドについて、`GET /repos/{owner}/{repo}/issues/{number}` と `GET /repos/{owner}/{repo}/issues/{number}/timeline` から、スレッドの `updated_at` を更新した出来事（以下「イベント」）とその実行者を求める。`updated_at` にいちばん近い候補を選び、近いものが無ければ出さない
  - 扱うイベント: Opened / Commented / Approved / Requested changes / Reviewed / Closed / Reopened / Merged / Marked ready for review / Converted to draft / Requested review / Assigned / Pushed commits / Force-pushed
  - それ以外のタイムラインのイベント（`labeled`、`cross-referenced`、`subscribed` など）は使わない。知らないイベント名を画面に出さない
- Issue のレスポンスから件名の今の状態（Pull request は Open / Draft / Merged / Closed、Issue は Open / Closed as completed / Closed as not planned）も求め、一覧の行の種類のアイコンを状態の分かる記号と色にする（追加のリクエストは無い）
- イベントはアカウントのポーラーが取り、スレッドの ID と `updated_at` の組でメモリにだけ覚える。`updated_at` が変わったスレッドだけ取り直す。1 回の取得で取るスレッドの数に上限を設ける
- 新着のスレッド（前回の一覧から増えたか `updated_at` が進んだもの）は、一覧と macOS の通知に出す前にイベントを取る（上限あり）。取れなかったスレッドは、今までどおり理由だけで出す
- 一覧の行の 2 行目を `#42 · Closed by alice · Watching · 3m` のように、番号と理由の間にイベントを入れる
- macOS の通知の本文を `Closed by alice · Watching · alice (github.com)` のように、理由の前にイベントを入れる
- イベントの取得の失敗・レート制限は、通知の取得の状態（「取得できた」「失敗して待っている」など）を変えない。レート制限のときは、制限が解けるまでイベントの取得だけを止める

やらないこと:

- Commit・Release・Discussion・CheckSuite のスレッドのイベント（Discussion は GraphQL が要る。Commit などは Timeline が無い）
- コメントの本文の表示（v1 でやらないことのまま）
- イベントの取得をオフにする設定（追加のリクエストは、更新されたスレッド 1 件につき通常 2 回で、レート制限の 5,000 回/時に比べて小さい）
- GraphQL の利用

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- `github-api`: Issue の取得と Timeline の取得のリクエスト（送り先の検証、ページの選び方、状態コードの扱い）と、そこからイベントと件名の状態を決める規則を ADDED で加える
- `polling`: イベントの取得のタイミング・上限・キャッシュ・失敗とレート制限の扱い（通知の取得の状態を変えないこと）を ADDED で加える
- `notifications`: 「通知の中身」の本文にイベントを入れるので MODIFIED にする
- `ui`: スレッドの行にイベントを出す要件と、行のアイコンに件名の状態を出す要件を ADDED で加える（アイコンは「アカウント一覧の表示」の「種類を表すアイコン」をそのまま満たし、状態を足すだけ）。「アカウント一覧の表示」は行に番号・理由・更新日時を出すことと「番号を理由の前に出す」ことを定めている。イベントは番号と理由の間に入れるので、この要件の内容はそのまま成り立つ（番号は理由の前のまま）。そのため「アカウント一覧の表示」は書き換えずに、別の要件として加える

## Impact

- コード: `GitHubAPI/`（Issue と Timeline の取得、イベントの決定、`Link` の `rel="last"` の読み取り、実行者のログイン名の検証）、`Polling/AccountPoller`（イベントの取得とキャッシュ）、`NotificationThread`（イベントを持つ）、`UI/ThreadRow`、`Notifications/ThreadNotificationContent`
- API: 新しく `GET /repos/{owner}/{repo}/issues/{number}` と `GET /repos/{owner}/{repo}/issues/{number}/timeline` を呼ぶ。必要なスコープは今の `repo` と同じ。GHES 3.13+ にもある
- トークン: 触れる。新しいリクエストにも、既存のリクエストと同じくリクエストごとにトークンを付ける。トークンは永続化しない方針のまま（イベントのキャッシュにもトークンは入らない。キャッシュはメモリだけ）
- gh サブプロセス: 触れない
- ネットワーク: 触れる。新しいリクエストの URL は API の `subject.url` をそのまま使わず、検証済みのリポジトリ名と番号から組み立てる。続きのページ（`Link`）にも既存のオリジン検査を通す。`.claude/rules/security.md` が適用される
- URL を開く処理: 触れない
- 依存: 追加しない
