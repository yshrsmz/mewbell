# Design

## Context

- `GitHubAPIClient`（`Mewbell/GitHubAPI/GitHubAPIClient.swift`、299 行）は、状態を持たない `nonisolated` の `Sendable` な struct で、呼び出し元（`AccountPoller` などの actor）の上で動く（A2）。`send(_:method:endpoints:token:ifModifiedSince:body:)` は、送り先が `APIEndpoints.isAllowedRequestURL` を通ることを確かめ、`Authorization` と共通のヘッダーを付けて `HTTPTransport` に渡し、リダイレクトを失敗にする。
- 状態とイベントの取得（`fetchDetails(for:endpoints:token:)` と、その下の `fetchTimeline`・`getPage`・`get`、URL の組み立てと二次レート制限の判定、結果の型 `ThreadDetailsFetchResult`・`DetailsStop`）は、`GitHubAPIClient+ThreadDetails.swift`（159 行）の extension にある。この extension の `get` が `send` を呼ぶので、`send` は `private` になっていない。
- swiftlint の `file_length` は既定のまま（400 行で警告）で、`scripts/lint.sh` は `--strict` で警告もエラーにする。2 つのファイルを合わせると 400 行を超える。
- `.swiftlint.yml` の `authorization_header_outside_client`（正規表現 `(?i)"authorization"`）は、`GitHubAPIClient.swift` をファイルごと `excluded` にしている。今このファイルで正規表現に当たるのは、`send` の `request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")` の 1 行だけ。
- テストは `HTTPTransport` を `FakeHTTPTransport` に差し替えて `fetchDetails` などの公開の関数を呼んでいて（A5）、`send` を直接は呼んでいない。

## Goals / Non-Goals

**Goals:**

- `send` を `private` にして、`Authorization` を付ける経路が `GitHubAPIClient.swift` の外から増えないことを、コンパイラで守る。
- lint の例外を、`Authorization` を付ける 1 行に絞る。

**Non-Goals:**

- `GitHubAPIClient` の公開の関数の形・結果の型・振る舞いを変えること。
- テストを足す・変えること。振る舞いを変えないので、既存の `GitHubAPIClientTests`・`ThreadDetailsRequestTests`・`ThreadActionRequestTests` などがそのまま通ることで確かめる。
- ほかの「既知の逸脱」（A1 の `GitHubAPIClient` から `ThreadAction` への依存など）を直すこと。別の change で扱う。

## Decisions

### D1. 状態とイベントの取得の extension を `GitHubAPIClient.swift` に移し、`send` を `private` にする（A6）

`GitHubAPIClient+ThreadDetails.swift` の中身を、extension の形のまま `GitHubAPIClient.swift` の末尾に移し、元のファイルを消す。Swift では、同じファイルの extension から型の `private` のメンバーを呼べるので、`send` を `private` にしても `get` から呼べる。ファイルの先頭に `// swiftlint:disable file_length` を置き、このファイルだけ行数の上限を緩める。これは A6 の「行数の上限でファイルを分けるときも、関所の内側は分けずに、そのファイルだけ上限を緩める」に従う形である。

結果の型（`ThreadDetailsFetchResult`、`DetailsStop`）も一緒に移す。取得の関数と結果の型を別のファイルに分ける理由が無く、移した先を読むだけで取得の全体が分かるようにする。

採らなかった案:

- 純粋な部分（URL の組み立て、`page(of:)`、`isSecondaryRateLimit`、結果の型）を別のファイルに残し、行数を 400 行に収める: 合わせても 400 行前後で、次に少し足せばまた上限に当たる。行数のためだけにファイルを分けると、置き場所を決める軸が増える（A1 の「置き場所を決める軸を 1 つにする」の考え方に反する）。
- 状態とイベントの取得を別の型（`ThreadDetailsFetcher` など）にし、送る処理をクロージャで渡す: 渡したクロージャが `send` と同じことをできるので、関所が 1 か所であることをコンパイラで守れない。型も 1 つ増える。
- `get` だけを `GitHubAPIClient.swift` に置いて `private` でない形にする: `get` がトークン付きの `GET` を送る新しい入口になり、逸脱の形が変わるだけになる。

### D2. lint の例外を `Authorization` を付ける 1 行に絞る（A6、security.md）

`.swiftlint.yml` の `authorization_header_outside_client` から `excluded` を消す。`send` の `Authorization` を付ける行の直前に `// swiftlint:disable:next authorization_header_outside_client` を置く。こうすると、`GitHubAPIClient.swift` の中でも、ほかの行に `Authorization` を書けば lint が止める。

採らなかった案:

- ファイルの除外を残す: `send` が `private` になっても、同じファイルの中に 2 か所目の `Authorization` を書けることは変わらず、lint では見つからない。

### D3. `docs/architecture.md` を、スキル `update-architecture-doc` の手順で更新する

「既知の逸脱」から A6 の行を消し、A6 の「根拠」に `fix-api-client-send-privacy D1・D2` を足す。A6 の本文は今の形と合っているので変えない。

## Risks / Trade-offs

- [`GitHubAPIClient.swift` が 450 行ほどになり、読む範囲が広がる] → 状態とイベントの取得は、今の見出しのコメント（`// スレッドの件名の状態とイベントの取得（…）`）を付けた extension のまま移し、ファイルの中で区切りが分かるようにする（リポジトリでは `// MARK:` を使っていないので、足さない）。
- [`swiftlint:disable file_length` を一度置くと、このファイルがいくらでも大きくなれる] → A6 で例外として認めた形で、関所を持つこのファイルだけに限る。大きくなりすぎたら、関所の外（URL の組み立てやボディの解釈など、`send` を呼ばない純粋な部分）を別の型に切り出す（A7）。
- [`swiftlint:disable:next` の書き方を誤ると、lint の例外が効かないか、別の行に効く] → 実装の後に、`GitHubAPIClient.swift` のほかの行に一時的に `"Authorization"` を書いて lint が止めることを確かめる（tasks の 1.3）。

## セキュリティ

トークンの流れは変えない。`AccountPoller` がポーラーの actor の中で `TokenProviding` から受け取った `AccessToken` を、呼び出しごとに引数で `GitHubAPIClient` の公開の関数に渡す。`send` がリクエストの `Authorization` に付けて `HTTPTransport` に渡し、`GitHubAPIClient` はトークンを保持しない。破棄は今までどおりポーラーの側で行う。

`.claude/rules/security.md` の項目への対応:

- トークンの扱い（取得元、メモリにだけ持つ、`AccessToken` の伏せ字、ログに出さない）: 触れない。`send` のログの内容は変えない。
- gh サブプロセス: 触れない。
- ネットワーク（送り先のオリジン検査、HTTPS だけ、リダイレクトの拒否、共有のヘッダーにトークンを入れない、キャッシュを使わない）: `send` の中身は変えない。`private` にすることで、オリジン検査を経ない送り方を同じファイルの外から作れなくなる。lint の例外を 1 行に絞ることで、同じファイルの中でも `Authorization` を付ける 2 か所目を lint で止める。
- これらの性質を確かめる既存のテスト（`APIEndpointsTests` のオリジン検査、`GitHubAPIClientTests` のリダイレクトと送り先の検査、`ThreadDetailsRequestTests.sendsNothingToTheLinkedHost`）は変えずに通す。
- アプリとビルドの設定、依存: 触れない。
