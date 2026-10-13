# Proposal

## Why

`docs/architecture.md` の A6 では、`Authorization` を付けて送る関所の内側（`GitHubAPIClient.send`）を `private` に保つと決めている。ところが今の `send` は `private` ではなく、「既知の逸脱」に載っている。add-thread-latest-event で `GitHubAPIClient.swift` が行数の上限を超えたため、状態とイベントの取得を `GitHubAPIClient+ThreadDetails.swift` の extension に分け、その extension から呼べるように `private` を外した。そのため今は、モジュールのどこからでも `send` を呼んでトークン付きのリクエストを組み立てられる。関所が 1 か所であることを、コンパイラではなく規約だけで守っている状態になっている。

lint の `authorization_header_outside_client` も、`GitHubAPIClient.swift` をファイルごと除外している。そのため、このファイルの中に `Authorization` を付ける 2 か所目ができても、lint では見つからない。

## What Changes

- `GitHubAPIClient+ThreadDetails.swift` の中身を、extension のまま `GitHubAPIClient.swift` に移し、`GitHubAPIClient+ThreadDetails.swift` を消す。`send` を `private` に戻す。ファイルの行数の上限は、このファイルだけ `swiftlint:disable file_length` で緩める（A6 に書いてあるやり方）。
- `.swiftlint.yml` の `authorization_header_outside_client` から `excluded` を消す。`Authorization` を付ける 1 行の直前に `swiftlint:disable:next authorization_header_outside_client` を置き、例外をその 1 行に絞る。
- `docs/architecture.md` の「既知の逸脱」から A6 の行を消す。A6 の「根拠」にこの change を足す。

アプリの振る舞いは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。コードの置き場所とアクセス修飾子、lint の設定を変えるだけで、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。M2（通知の取得）と add-thread-latest-event で入れた `GitHubAPIClient` の構造を、A6 に合わせる。
- 変更するもの: `Mewbell/GitHubAPI/GitHubAPIClient.swift`、`Mewbell/GitHubAPI/GitHubAPIClient+ThreadDetails.swift`（削除）、`.swiftlint.yml`、`docs/architecture.md`。プロジェクトはフォルダ単位でファイルを取り込んでいるので、`project.xcproj` は変えない。
- トークン・ネットワーク: トークンを付けて送る処理（`send`）に触れるので、`.claude/rules/security.md` が適用される。送り先のオリジン検査、リダイレクトの扱い、ヘッダー、ログの内容は変えない。トークンは今までどおりメモリにだけ持ち、永続化しない。gh サブプロセスと URL を開く処理には触れない。
