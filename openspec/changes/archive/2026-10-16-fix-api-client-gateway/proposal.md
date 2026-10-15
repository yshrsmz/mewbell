# Proposal

## Why

`docs/architecture.md` の A6 は、関所のファイルが行数の上限に当たったら上限を緩めずに、関所（送り先を検査して `Authorization` を付けて送る処理と、それが使う `HTTPTransport`）を小さな型に切り出すと決めている（update-architecture-principles D6 で改めた）。ところが今の `GitHubAPIClient.swift` は 646 行あり、先頭の `// swiftlint:disable file_length` で上限を緩めている。この形は A6 の「既知の逸脱」に載っていて、直す change として `fix-api-client-gateway` を指している。関所の範囲がファイル 1 つで読めず、取得の処理を足すたびに関所のファイルが大きくなる。

## What Changes

- 関所を `APIGateway`（`Mewbell/GitHubAPI/APIGateway.swift`）に切り出す。今の `GitHubAPIClient.send` の中身（送り先の検査、`Authorization` と共通のヘッダー、ボディの上限、リダイレクトと通信の失敗の分類、ログ）をこの型に移し、`HTTPTransport` はこの型だけが `private` で持つ。外に見せるのは、検査を通る入口の `send` だけにする。
- `GitHubAPIClient` は `APIGateway` を持ち、すべてのリクエストをその `send` で送る。`init(transport:now:)` の形は変えず、中で `APIGateway` を作る。
- 状態とイベントの取得の extension（`ThreadDetailsFetchResult` と `DetailsStop` を含む）を `GitHubAPIClient+ThreadDetails.swift` に移す。関所が別の型になったので、別のファイルの extension からでも検査を通らずに送ることはできない。extension から使うメンバー（関所、`now`、レート制限の判定、日時の書き方）だけ `private` を外す（A10）。
- `GitHubAPIClient.swift` の `// swiftlint:disable file_length` を消す。3 つのファイルとも行数の上限（400 行）に収める。
- `.swiftlint.yml` の `authorization_header_outside_client` の規則を、ID・`name`・`message` とも新しい関所の名前（`authorization_header_outside_gateway`）に直す。`swiftlint:disable:next` の例外は、`Authorization` を付ける 1 行と一緒に `APIGateway.swift` に移す。
- `docs/architecture.md` の A6 の本文の関所の名前を `APIGateway.send` に直し、「既知の逸脱」から A6 の行を消し（表には「なし」の行を置く）、A6 の「根拠」にこの change を足す。

アプリの振る舞いは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。コードの置き場所と型の分け方、lint の設定と設計方針の文書を変えるだけで、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。M2（通知の取得）以降に足してきた `GitHubAPIClient` の構造を、改めた A6 に合わせる。
- 変更するもの: `Mewbell/GitHubAPI/GitHubAPIClient.swift`、`Mewbell/GitHubAPI/APIGateway.swift`（新規）、`Mewbell/GitHubAPI/GitHubAPIClient+ThreadDetails.swift`（新規）、`.swiftlint.yml`、`docs/architecture.md`。プロジェクトはフォルダ単位でファイルを取り込んでいるので、`project.xcproj` は変えない。テストは変えない。
- トークン・ネットワーク: トークンを `Authorization` に付けて送る処理に触れるので、`.claude/rules/security.md` が適用される。送り先のオリジン検査、リダイレクトの扱い、ヘッダー、ボディの上限、ログの内容は変えない。トークンは今までどおり呼び出しごとに引数で受け取ってリクエストに付けるだけで、`APIGateway` も `GitHubAPIClient` も保持せず、永続化しない。gh サブプロセスと URL を開く処理には触れない。
