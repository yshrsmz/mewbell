# Tasks

## 1. 関所を `APIGateway` に切り出し、行数の上限に収める

- [x] 1.1 `Mewbell/GitHubAPI/APIGateway.swift` に `APIGateway` を置き、今の `GitHubAPIClient.send` の中身・`bodyLimit`・`userAgent`・ロガーを形を変えずに移す（design.md D1）。`transport` と `bodyLimit` は `private`、外に見せるのは `init(transport:)` と `send` だけにする。`swiftlint:disable:next authorization_header_outside_client` は `Authorization` の行と一緒に移す。`GitHubAPIClient` は `private let transport` を `let gateway: APIGateway` に置き換え、`init(transport:now:)` の中で作り、`send(...)` の呼び出しを `gateway.send(...)` に変える。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell build` が通ることと、`git grep -n "transport\.send\|\.transport\b" Mewbell` で `HTTPTransport.send` を呼んでいるのが `APIGateway.swift` だけであることを確かめる。
- [x] 1.2 状態とイベントの取得の extension（`ThreadDetailsFetchResult`、`DetailsStop` を含む）を、形を変えずに `Mewbell/GitHubAPI/GitHubAPIClient+ThreadDetails.swift` に移す（design.md D2）。別のファイルから使う `gateway`・`now`・`rateLimit(_:)`・`RateLimit`・`apiDateFormat` だけ `private` を外し、ほかは `private` のままにする。`GitHubAPIClient.swift` の先頭の `// swiftlint:disable file_length` を消す。`wc -l Mewbell/GitHubAPI/APIGateway.swift Mewbell/GitHubAPI/GitHubAPIClient.swift Mewbell/GitHubAPI/GitHubAPIClient+ThreadDetails.swift` でどれも 400 行未満であることと、`xcodebuild ... build` が通ることを確かめる。
- [x] 1.3 `.swiftlint.yml` の `authorization_header_outside_client` の `message` を「Authorization を付けて送るのは APIGateway.send だけ（A6、security.md）」に直し、`GitHubAPIClient` の doc コメントの「`Authorization` に付けるのはこの型だけ」などを `APIGateway` を通して送る形に直す（design.md D3）。`bash scripts/lint.sh` が通ることを確かめる（`file_length` の警告も出ないこと）。
- [x] 1.4 lint の例外が `APIGateway.swift` の 1 行だけに効くことを手で確かめる。`APIGateway.swift` のほかの行と `GitHubAPIClient.swift` に一時的に `"Authorization"` を含む行を書き、それぞれ `bash scripts/lint.sh` が `authorization_header_outside_client` で止まることを確かめてから戻す。
- [x] 1.5 テストを変えずに、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/GitHubAPIClientTests -only-testing:MewbellTests/NotificationPagingTests -only-testing:MewbellTests/URLSessionTransportTests -only-testing:MewbellTests/ThreadDetailsRequestTests -only-testing:MewbellTests/MarkThreadDoneTests -only-testing:MewbellTests/MarkAllReadTests -only-testing:MewbellTests/MarkThreadReadTests -only-testing:MewbellTests/APIEndpointsTests` が通ることを確かめる（オリジン検査・リダイレクトの拒否・送り先の検査が今までどおりであること）。結果のスイート数が指定した 8 と合うことも確かめる。

## 2. 設計方針の文書

- [x] 2.1 スキル `update-architecture-doc` の手順で `docs/architecture.md` を更新する（design.md D3）。A6 の「原則」の `` `GitHubAPIClient.send` `` を `` `APIGateway.send` `` に直し、関所の内側の例と行数の上限の扱いを今の形に合わせる。「既知の逸脱」から A6 の行を消し、A6 の「根拠」に `fix-api-client-gateway D1・D2・D3` を足す。A10 の「関所の内側は A6 に従い、外さない」が直した A6 と合っていることを読み直す。`bash scripts/check-architecture.sh` と `bash scripts/tests/check-architecture-test.sh` が通ることを確かめる。

## 3. 確認

- [x] 3.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [ ] 3.2 `bash scripts/run.sh` で起動し、手元で確かめる。通知の一覧が取れること、件名の状態とイベントが表示されること、既読にできることが今までどおりであること。

## 4. レビュー

- [ ] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する。
