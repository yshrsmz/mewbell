# Design

## Context

- 開く URL は `ThreadWebURL.make(for:endpoints:)` が組み立てる。種類が Release と Discussion のときは `subject.url` を見ずに `.releases` / `.discussions` を返している。ポップオーバーのクリック（`NotificationStore.open`）と macOS の通知（`ThreadNotificationContent` が通知を出すときに URL を作って `userInfo` に入れる）の 2 つの経路が同じ関数を使う
- Issue と Pull request の件名の状態とイベントは、`AccountPoller+ThreadDetails` が `ThreadDetailsFetcher`（同時に 4 件、20 秒の打ち切り、レート制限で残りをやめる）で取り、`ThreadDetailsCache`（スレッドの ID と `updated_at` ごとの記録、失敗の回数、レート制限の待ち）に覚え、`NotificationThread.details` に付ける。新着は一覧を知らせる前に取るので、新着の macOS の通知は `details` を付けたスレッドから作られる。取る対象は `ThreadDetailsCache.pending` が `subjectNumber != nil` で選ぶ
- `GitHubAPIClient.fetchDetails` は `subjectNumber` から Issue と Timeline の URL を組み立て、`get`（ステータスコードを `ThreadDetailsFetchResult` に振り分ける）で送る
- 手元の github.com で確かめた API の値: Discussion の `subject.url` は `.../repos/<owner>/<name>/discussions/<番号>`、`latest_comment_url` は `null`。Release の `subject.url` と `latest_comment_url` は `.../repos/<owner>/<name>/releases/<数値の ID>`。`GET .../releases/<ID>` は `tag_name` と `html_url`（`.../releases/tag/<タグ>`）を返す。Web の `/releases/<ID>` は 404

## Goals / Non-Goals

**Goals:**

- Discussion と Release のスレッドで、ポップオーバーからも macOS の通知からも個別のページを開く
- Release のタグの取得を、イベントの取得と同じ仕組み（覚え方・同時に取る数・打ち切り・レート制限・失敗の回数）に載せる
- 取れないとき・検証を通らないときは、今の一覧のページに戻る

**Non-Goals:**

- 一覧の行に Discussion の番号や Release のタグを出すこと（ui「アカウント一覧の表示」は変えない）
- Discussion の状態（回答済みなど）やイベントを取ること
- 開くときに待ってタグを取ること（クリックしてから通信を待たない）
- GraphQL を使うこと

## Decisions

### D1. Discussion の番号は `subject.url` から、Pull request・Issue と同じ検証で読む（A6、A9）

`ThreadWebURL.target` の種類ごとの早期 return をやめ、`subject.url` を API ベースの下・`repos/<owner>/<name>/<種類>/<id>`・リポジトリの一致の順に検証してから、種類と組み合わせて `Target` を決める。種類が Discussion で `discussions/<1〜20 桁の数字>` なら `.discussion(番号)`（パスは `discussions/<番号>`）、それ以外なら今の `.discussions`。`subjectNumber` は今までどおり Pull request と Issue の番号だけを返す（Discussion の番号を返すと `#<番号>` が出て、イベントの取得の対象にもなるため）。

- 代替案: `latest_comment_url` から読む → Discussion では `null` で使えない
- 代替案: 種類を見ずに `discussions/<番号>` の形だけで決める → spec は種類で分けているので、Issue の種類で `discussions` の URL が来たときの扱いを増やさない

### D2. Release のタグは、イベントの取得の仕組みで一覧を取るときに取る（A3、A7）

`NotificationThread` に、デコードするときに `ThreadWebURL.releaseID(kind:subjectURL:repository:endpoints:)` で求めた `releaseID: String?` を足す（`subjectNumber` と同じ求め方。D1 と同じ検証を通った `releases/<1〜20 桁の数字>` で、種類が Release のときだけ）。`ThreadDetailsCache.pending` の対象を `subjectNumber != nil || releaseID != nil` にする。`GitHubAPIClient.fetchDetails` は `releaseID` があれば `GET repos/<owner>/<name>/releases/<ID>` を `get` で 1 回送り、タグを付けた `ThreadDetails` を返す。覚え方・失敗の回数・レート制限・再読み込みでの中断は今のものをそのまま使う。

`ThreadDetails` に `releaseTag: String?` を足す。Release のスレッドでは `state` と `event` は nil、Issue と Pull request では `releaseTag` は nil になる。

- 代替案: クリックしたときに取る → ブラウザが開くまで通信を待つ。macOS の通知の経路は起動の直後でトークンが無いことがあり、2 つの経路で別々に取る処理が要る（ユーザーと確認して採らなかった）
- 代替案: `ThreadDetails` を Issue 用と Release 用の enum にする → 状態のアイコンやイベントの表示（`details?.state`、`details?.event`）の読み出しをすべて変えることになる。足す値が 1 つなので、任意の値を 1 つ足す（A9）
- 代替案: タグを `ThreadDetailsCache` とは別の記録に持つ → 覚え方・失敗の回数・レート制限・止まったときに捨てる処理を二重に持つことになる（A3 の正本は 1 か所）

### D3. タグの検証と URL への足し方は `ThreadWebURL` に置く（A6）

ブラウザで開く URL の関所は `ThreadWebURL` なので、タグの検証も `ThreadWebURL.releaseTagComponents(_:) -> [String]?` に置く（空でない、255 文字以下、空白・制御文字を含まない、`/` で区切った要素に空・`.`・`..` が無い。満たせば要素の配列を返す）。`GitHubAPIClient` はレスポンスを読むときにこれで確かめ、通らなければ `.unavailable`（タグが「無い」）を返す。`ThreadWebURL.make` は覚えたタグをもう一度これで要素に分け、`releases`・`tag` に続けて要素ごとに `appending(path:)` で足す。`/` を含むタグ（`cli/v1.2.0`）は GitHub の Web と同じく `/` のまま、要素の中の `?`・`#`・`%` などはパスの要素としてエスケープされることを、テストで確かめる。

- 代替案: レスポンスの `html_url` をオリジンとパスの前置きで確かめて使う → API の URL をそのまま開かない約束（security.md・ui spec）に外れる。`tag_name` だけを読み、`html_url` はデコードの型に載せない

### D4. リリースのレスポンスの読み方（A7、A8）

`ReleaseSummary`（`tagName: String` だけを持つ `Decodable`）を `ThreadEventResolver.swift` の `IssueSummary` の隣に置く。`200` でボディが読めない・`tag_name` が文字列でなければ `.failed(.malformedBody)`、タグが D3 の検証を通らなければ `.unavailable`。ほかのステータスコードは `get` の今の振り分けをそのまま使う（spec のレスポンスの扱いはイベントの取得と同じ）。`body` などほかのキーは型に載せない。

### actor と `@MainActor` の境界（A2）

変えない。リリースの取得は `AccountPoller`（actor）の中から `ThreadDetailsFetcher` 経由で、今のイベントの取得と同じタスクで動く。`ThreadWebURL` は純粋な関数で、`NotificationStore`（`@MainActor`）と `ThreadNotificationContent` から今までどおり呼ぶ。

### テストでの差し替え（A5、A12）

ネットワークは今までどおり `HTTPTransport` を `FakeHTTPTransport` に差し替える。`ThreadDetailsRequestTests` にリリースの取得（URL・トークン・`200`/`404`/`403`/`429`/形の崩れ・検証を通らないタグ・`html_url` を使わないこと）を、`ThreadDetailsCacheTests` に Release を対象に選ぶこと・ID を持たない Release を選ばないことを、`ThreadDetailsPollingTests` に新着の Release のタグを知らせる前に付けることを、`ThreadPresentationTests`（`ThreadWebURL` のテストがある所）に Discussion と Release の URL の組み立てを足す。

### docs/architecture.md

原則に無い新しい判断は無い（D3 は A6 の関所に検証を足すだけ）。型・メンバーの削除や改名も無いので、文書は変えない。

## セキュリティ

- トークンの流れ: 変えない。`TokenProviding` から得たトークンを `AccountPoller` の中だけで持ち、リリースの取得でも `GitHubAPIClient.send` だけがリクエストごとに `Authorization` を付ける。永続化しない
- 送り先: リリースの URL は検証済みの `owner/name` と数字の ID から `endpoints.apiURL(path:)` で組み立て、`send` のオリジン検査（「トークンを送る相手の制限」）を通す。`subject.url` をそのまま叩かない
- リダイレクトとキャッシュ: 今の `URLSession` の設定（リダイレクトを拒否、キャッシュなし）をそのまま使う
- ログ: レスポンスのボディ・タグ・URL をログに出さない。今のイベントの取得と同じく、打ち切りとレート制限の事実だけをホスト名付きで出す
- 開く URL: `html_url` は使わない。タグは D3 で検証し、Web ベース URL に要素として足した後、`ThreadWebURL.isOpenable`（`https`・アカウントのホスト・ポートとユーザー情報なし）を通す。検証を通らなければ `/releases` に戻る
- 覚えたタグはメモリにだけ持ち、今の記録と同じく一覧から消えたら・止まったら・終了で捨てる。通知の `userInfo` に入るのは組み立てた Web の URL だけで、トークンや API の URL は入れない
- gh サブプロセス・環境変数・ホスト名とユーザー名の検証: 触れない

## Risks / Trade-offs

- [Release のスレッドごとにリクエストが 1 回増える] → `updated_at` が変わったときだけ取り、イベントの取得と同じ件数の上限・同時に取る数・レート制限の待ちに従う。Release のスレッドは `updated_at` がほとんど変わらない
- [最初の一覧や、11 件目以降の新着の Release は、通知を出した後にタグを取る] → その macOS の通知のクリックは今の `/releases` を開く。ポップオーバーからは、タグを取った後なら個別のページを開く
- [`appending(path:)` のエスケープの仕方が想定と違う（`%` をそのまま残すなど）] → テストで `?`・`#`・`%`・空白以外の記号を含むタグの URL を確かめ、合わなければ `URLComponents` の `percentEncodedPath` で組み立てる
- [GHES で Discussion の `subject.url` が `null` のまま] → 今の `/discussions` に戻るので、悪くはならない
- [ドラフトのリリースなどで `GET /releases/<ID>` が `404`] → タグは「無い」になり、その `updated_at` の間は取り直さない
