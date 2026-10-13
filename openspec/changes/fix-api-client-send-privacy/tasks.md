# Tasks

## 1. `send` を private にし、lint の例外を絞る

- [ ] 1.1 `GitHubAPIClient+ThreadDetails.swift` の中身（`ThreadDetailsFetchResult`、`DetailsStop`、状態とイベントの取得の extension）を、形を変えずに `GitHubAPIClient.swift` の末尾に移し、元のファイルを消す。`send` を `private` にし、`send` の doc コメントから「ほかのファイルの extension もこれを通して送る」を外す。ファイルの先頭に `// swiftlint:disable file_length` を置く。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell build` が通ることと、`git grep -n "\.send(" Mewbell` で `send` を呼んでいるのが `GitHubAPIClient.swift` の中だけであることを確かめる。
- [ ] 1.2 `.swiftlint.yml` の `authorization_header_outside_client` から `excluded` を消し、`send` の `Authorization` を付ける行の直前に `// swiftlint:disable:next authorization_header_outside_client` を置く。`bash scripts/lint.sh` が通ることを確かめる。
- [ ] 1.3 lint の例外が 1 行だけに効くことを手で確かめる。`GitHubAPIClient.swift` のほかの行に一時的に `"Authorization"` を含む行を書き、`bash scripts/lint.sh` が `authorization_header_outside_client` で止まることを確かめてから戻す。
- [ ] 1.4 テストを変えずに、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/GitHubAPIClientTests -only-testing:MewbellTests/ThreadDetailsRequestTests -only-testing:MewbellTests/ThreadActionRequestTests -only-testing:MewbellTests/APIEndpointsTests` が通ることを確かめる（オリジン検査・リダイレクトの拒否・送り先の検査が今までどおりであること）。

## 2. 設計方針の文書

- [ ] 2.1 スキル `update-architecture-doc` の手順で `docs/architecture.md` を更新する。「既知の逸脱」から A6 の行を消し、A6 の「根拠」に `fix-api-client-send-privacy D1・D2` を足す。`bash scripts/check-architecture.sh` と `bash scripts/tests/check-architecture-test.sh` が通ることを確かめる。

## 3. 確認

- [ ] 3.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [ ] 3.2 `bash scripts/run.sh` で起動し、手元で確かめる。通知の一覧が取れること、件名の状態とイベントが表示されること、既読にできることが今までどおりであること。

## 4. レビュー

- [ ] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する。
