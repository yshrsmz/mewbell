# Design

## Context

- `GitHubAPIClient`（`Mewbell/GitHubAPI/GitHubAPIClient.swift`、646 行）は、状態を持たない `nonisolated` の `Sendable` な struct で、呼び出し元（`AccountPoller` などの actor）の上で動く（A2）。ファイルの先頭の `// swiftlint:disable file_length` で行数の上限を緩めている。`scripts/lint.sh` は swiftlint を `--strict` で動かし、`file_length` は既定のまま（400 行で警告）なので、この行を消すとファイルを 400 行未満にする必要がある。
- ファイルの中身は、結果の型（`OAuthScopes`、`FetchFailure`、`NotificationsFetchResult`、`ThreadActionResult`）、型の本体（一覧の取得、既読・Done・すべて既読、`send`、レスポンスの分類、レート制限の判定、約 240 行）、状態とイベントの取得の extension（`ThreadDetailsFetchResult`、`DetailsStop` を含めて約 330 行）、`MarkAllReadBody` である。
- `private func send(_:method:endpoints:token:ifModifiedSince:body:)` は、送り先が `APIEndpoints.isAllowedRequestURL` を通ることを確かめ、`Authorization`・`Accept`・`X-GitHub-Api-Version`・`User-Agent`（と、あれば `If-Modified-Since` と JSON のボディ）を付け、`private let transport: any HTTPTransport` に `bodyLimit` を付けて渡す。`304` 以外の 3xx を `.redirect` に、`TransportError` を `FetchFailure` に分類し、メソッド・パス・ホスト・状態コードをログに出す。`Authorization` を付ける 1 行の直前に `// swiftlint:disable:next authorization_header_outside_client` がある。
- fix-api-client-send-privacy は、状態とイベントの取得の extension が別のファイルにあると `send` を `private` にできないので、extension をこのファイルに移して上限を緩めた。update-architecture-principles D6 で A6 を改め、関所を小さな型に切り出す形にした。この形にすれば、extension を別のファイルに置いても、関所の外から検査を通らずに送る道はできない。
- テストは `HTTPTransport` を `FakeHTTPTransport` に差し替え、`GitHubAPIClient(transport:now:)` で作ったクライアントの公開の関数を呼ぶ（A5）。作っている箇所は `NotificationStore.live` とテストの約 25 か所。
- `docs/architecture.md` の A6 の本文は `` `GitHubAPIClient.send` `` と書いている。`scripts/check-architecture.sh` の「コードの名前」の検査は、バッククォートの名前がコードに無いと lint を止める。`.swiftlint.yml` の `authorization_header_outside_client` の `message` も「`GitHubAPIClient.send` だけ」と書いている。

## Goals / Non-Goals

**Goals:**

- 関所（送り先の検査をして `Authorization` を付けて送る処理と、それが使う `HTTPTransport`）を 1 つの型・1 つのファイルにし、その型が外に見せるのを検査を通る入口だけにする（A6）。
- `swiftlint:disable file_length` を消し、どのファイルも行数の上限に収める。A6 の既知の逸脱を消す。

**Non-Goals:**

- `GitHubAPIClient` の公開の関数・`init(transport:now:)`・結果の型・振る舞いを変えること。リクエストのヘッダー・ログ・失敗の分類も変えない。
- テストを足す・変えること。振る舞いを変えないので、既存のテストがそのまま通ることで確かめる。`APIGateway` を直接呼ぶテストも足さない（A10・A12。関所の性質は `GitHubAPIClient` の公開の関数を通した既存のテストが確かめている）。
- `HTTPTransport.swift`（プロトコル、`URLSessionTransport`、`RedirectRejectingDelegate`）を変えること。
- 状態とイベントの取得の中身（`get` の分類や Timeline のページのたどり方）を整理すること。

## Decisions

### D1. 関所を `APIGateway` に切り出し、入口の `send` だけを見せる（A6、A2、A5）

`Mewbell/GitHubAPI/APIGateway.swift` に、`nonisolated` の `Sendable` な struct `APIGateway` を置く（A2。状態を持たない部品で、呼び出し元の actor の上で動く）。中身は今の `GitHubAPIClient.send` をそのまま移したもの。

- `private let transport: any HTTPTransport` を持ち、`init(transport:)` で受け取る。`transport` は外から読めない（A6 の「関所の内側は `private`」）。
- 外に見せるのは `func send(_ url: URL, method: String, endpoints: APIEndpoints, token: AccessToken, ifModifiedSince: String?, body: Data? = nil) async -> Result<HTTPResponse, FetchFailure>` だけ。送り先の検査、ヘッダー、ボディの上限、リダイレクトと通信の失敗の分類、ログを、この関数の中で行う。検査を通らない送り方は、この型の外に無い。
- `bodyLimit`、`userAgent`、ロガーも `APIGateway` に移す。`bodyLimit` を外から読んでいる箇所は無いので `private` にする。ログのカテゴリは今と同じ `GitHubAPI`（A11。モジュール名）。
- `// swiftlint:disable:next authorization_header_outside_gateway` は、`Authorization` を付ける 1 行と一緒に移す。

`GitHubAPIClient` は `private let transport` の代わりに `let gateway: APIGateway` を持ち、今 `send(...)` を呼んでいる 3 か所（一覧の取得、操作、状態とイベントの `get`）を `gateway.send(...)` に変える。`init(transport:now:)` の形は変えず、中で `APIGateway(transport:)` を作る。呼び出し側（`NotificationStore.live` とテスト）は変えない。

`APIGateway` は internal なので、モジュールのどこからでも作って `send` を呼べる。これは A6 の「その型を作れれば、検査を通る入口から送れる。入口の中で検査をするので、関所が 1 か所であることは変わらない」のとおりで、迂回の道ではない。

`FetchFailure` は `GitHubAPIClient.swift` に残す。`APIGateway` の戻り値にも使うが、`unexpectedStatus`・`malformedBody`・`noToken` は `GitHubAPIClient` とポーラーが作る値で、`NotificationsFetchResult` などの結果の型と並べて読む方が分かりやすい。

型の名前は `APIGateway` にする。A6 の「関所」をそのまま英語にした名前で、`GitHubAPI/` の中の `APIEndpoints`（送ってよい相手を決める型）と並ぶ。この名前を型・ファイル・A6・lint の `message`・コメントで揃える。

採らなかった案:

- `HTTPTransport` に検査とヘッダーを持たせる（`URLSessionTransport` を関所にする）: `HTTPTransport` はテストで差し替える境目（A5）で、偽物に差し替えると検査ごと消える。検査をテストで確かめられなくなる。
- 取得の処理を別の型にし、送る処理をクロージャで渡す: A6 の採らなかった案のとおり。渡したクロージャが関所と同じことをでき、検査を通らない送り方を外へ渡すことになる。
- `GitHubAPIClient` に `init(gateway:now:)` を足し、テストで `APIGateway` を渡す: 呼び出し側の変更が増えるだけで、守る要件もテストも増えない（A9）。

### D2. 状態とイベントの取得の extension を `GitHubAPIClient+ThreadDetails.swift` に移す（A6、A10、A9）

関所を `APIGateway` に切り出しても、`GitHubAPIClient.swift` は約 600 行で上限を超えたままになる。状態とイベントの取得の extension（`ThreadDetailsFetchResult`、`DetailsStop`、`fetchDetails` 以下の関数）を、形を変えずに `Mewbell/GitHubAPI/GitHubAPIClient+ThreadDetails.swift` に移す。ファイル名は add-thread-latest-event で使っていた名前に戻す。見込みの行数は、`GitHubAPIClient.swift` が約 270 行、`GitHubAPIClient+ThreadDetails.swift` が約 335 行、`APIGateway.swift` が約 70 行で、どれも 400 行未満に収まる。

別のファイルの extension から使うメンバーだけ、`private` を外して internal にする（A10 が extension への分割で認めた範囲）。

- `gateway`（D1）: 外に見せるのは検査を通る入口だけなので、関所の内側ではない。
- `now`: レート制限の時刻を出すための現在時刻のクロージャ。
- `rateLimit(_:)` と `RateLimit`: 403 / 429 の分け方。一覧・操作・状態とイベントの取得で判定を揃えるために、1 か所に置いたまま使う。
- `apiDateFormat`: API に送る日時の書き方。`markAllRead` と run の検索の両方で使う。

関所の内側（`APIGateway.transport`）は `private` のまま外さない。`DetailsStop` と `timelinePerPage`・`waitingRunLimit` などの extension の中だけで使うものは、移した先のファイルで `private` のままにする。`MarkAllReadBody` は `GitHubAPIClient.swift` に残して `private` のままにする。

採らなかった案:

- 状態とイベントの取得を別の型（`ThreadDetailsFetcher` など）にする: 型が増え、`GitHubAPIClient` の公開の関数とテストの組み方が変わる。行数の上限に収めるためだけの型になる（A9）。今のテストは `GitHubAPIClient.fetchDetails` を通して確かめていて、そのまま残せる。
- 結果の型だけを別のファイルに移して行数を減らす: 約 600 行から 100 行ほどしか減らず、上限に収まらない。

### D3. `.swiftlint.yml` と `docs/architecture.md` の関所の名前を直す（A6）

- `.swiftlint.yml` の `authorization_header_outside_client` の `message` を「Authorization を付けて送るのは APIGateway.send だけ（A6、security.md）」に直す。規則の ID も `authorization_header_outside_gateway` に改名し、`name` も合わせる（`swiftlint:disable:next` と A6 の根拠の規則名も直す）。正規表現と `included` は変えない。例外は `APIGateway.swift` の 1 行の `swiftlint:disable:next` だけになる。
- `docs/architecture.md` は、スキル `update-architecture-doc` の手順で更新する。A6 の「原則」の `` `GitHubAPIClient.send` `` を `` `APIGateway.send` `` に直し、関所の内側の例（「`Authorization` を付ける `send` など」）を `APIGateway` が持つ `HTTPTransport` に直す。「関所のファイルが行数の上限に当たったら切り出す」という条件の書き方を、関所を `APIGateway` にした今の形と、使う側が上限に当たったら extension に分ける（A10）形に書き直す。採らなかった案の「`send` の `private` を外す」は、`send` が入口になったので「関所の内側の `private` を外す」と書き直す。「既知の逸脱」から A6 の行を消し（表が空になるので「なし」の行を置く）、A6 の「根拠」に `fix-api-client-gateway D1・D2・D3` を足す。A10 の「関所の内側は A6 に従い、外さない」は、直した後の A6 と合っているかを読み直す。
- `GitHubAPIClient` の doc コメント（「トークンを `Authorization` に付けるのはこの型だけ」）を、`APIGateway` を通して送る形に直す。

この change で原則そのものは変えない（A6 が決めた形にコードを合わせ、名前を直すだけ）。

## Risks / Trade-offs

- [`gateway`・`now`・`rateLimit` などが internal になり、`GitHubAPI/` の外からも読める] → `gateway` は検査を通る入口しか持たず、`now` と `rateLimit` は危ない操作をしない。A10 が extension への分割で認めた範囲に収まる。
- [`swiftlint:disable:next` を移し損ねると、lint が `APIGateway.swift` の `Authorization` の行で止まるか、例外が別の行に効く] → 実装の後に、`APIGateway.swift` のほかの行と `GitHubAPIClient.swift` に一時的に `"Authorization"` を書いて lint が止めることを確かめる（tasks 1.4）。
- [見込みより行数が多く、どれかのファイルが 400 行を超える] → `bash scripts/lint.sh` で確かめる。超えたら、上限を緩めずに、そのファイルの中で送らない純粋な部分（URL の組み立てなど）を移す形を、その時点で AskUserQuestion で確かめる。

## テストでの差し替え

ネットワークは今までどおり `HTTPTransport` のプロトコルで差し替える（A5）。テストは `FakeHTTPTransport` を `GitHubAPIClient(transport:now:)` に渡し、`GitHubAPIClient` が中で作る `APIGateway` を通して送る。テストのコードは変えない。security.md の性質を確かめる既存のテスト（`APIEndpointsTests` のオリジン検査、`GitHubAPIClientTests` の `doesNotFollowANextLinkOutsideTheAPIBase`・リダイレクトの分類・`URLSessionTransportTests.rejectsEveryRedirect`、`ThreadDetailsRequestTests.sendsNothingToTheLinkedHost`）がそのまま通ることで、関所の性質が変わっていないことを確かめる（A12）。

## スレッドと actor の境界

変えない。`APIGateway` と `GitHubAPIClient` は状態を持たない `nonisolated` の `Sendable` な struct で、呼び出し元の actor（`AccountPoller`、`ThreadDetailsFetcher` を使う側）の上で動く。`HTTPTransport.send` の `await` の間だけ、その actor から離れる。

## セキュリティ

トークンの流れは変えない。`AccountDiscovery` が `gh auth token` で取得したトークンは `CredentialStore` の中のメモリにだけあり、ポーラーが `TokenProviding` から取得の間だけ `AccessToken` として受け取る。ポーラーは呼び出しごとに引数で `GitHubAPIClient` の公開の関数に渡し、`GitHubAPIClient` はそれを `APIGateway.send` に渡す。`APIGateway.send` がリクエストの `Authorization` に付けて `HTTPTransport` に渡す。`GitHubAPIClient` も `APIGateway` もトークンを保持しない。破棄は今までどおりアカウントの無効化・アプリの終了時に行う。

`.claude/rules/security.md` の項目への対応:

- トークンの扱い（取得元、メモリにだけ持つ、`AccessToken` の伏せ字、ログに出さない）: 変えない。`APIGateway.send` のログは、今の `send` と同じくメソッド・パス・ホスト・状態コードだけで、ヘッダーとボディを出さない。
- gh サブプロセス: 触れない。
- ネットワーク: 送り先のオリジン検査（`APIEndpoints.isAllowedRequestURL`）、HTTPS だけ、リダイレクトの拒否（`RedirectRejectingDelegate` と 3xx の `.redirect`）、共有のヘッダーにトークンを入れない（リクエストごとに付ける）、キャッシュを使わない（`URLSessionTransport` の設定）は、中身を変えずに `APIGateway` に移すか、触れない。`HTTPTransport` を持つのが `APIGateway` だけになり、`private` なので、検査を通らずに送る道は `APIGateway.swift` の外に無い。`Authorization` を付ける行は lint の例外 1 行のまま。
- これらを確かめる既存のテストは、「テストでの差し替え」に書いたものを変えずに通す。
- URL を開く処理、アプリとビルドの設定、依存: 触れない。
