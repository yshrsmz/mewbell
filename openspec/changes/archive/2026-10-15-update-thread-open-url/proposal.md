# Proposal

## Why

種類が Discussion と Release のスレッドをクリックすると、個別のディスカッション・リリースではなく、リポジトリのディスカッション一覧・リリース一覧のページが開く。最初の change（add-notification-fetch）では「Discussion の `subject.url` は `null` のことがある」「Release はタグの URL を作れない」ので、正確な URL のために追加のリクエストはしないと決めていた。今の API を確かめると、Discussion の `subject.url` は `https://api.github.com/repos/<owner>/<name>/discussions/<番号>` の形で番号を含んでいる。Release の `subject.url` は `.../releases/<数値の ID>` で、Web の `/releases/<ID>` は 404 になる。個別のページはタグで開く（`/releases/tag/<タグ>`）が、タグは件名と違うことがある（件名 `0.163.0-alpha.10.1` に対してタグ `rust-v0.163.0-alpha.10.1`）。開いた先でもう一度探す手間をなくすため、どちらも個別のページを開くようにする。

M4（設定と操作）の改善として扱う。

## What Changes

- Discussion のスレッドは、`subject.url` が API ベース URL の下の `repos/<owner>/<name>/discussions/<番号>` で、Pull request・Issue と同じ検証を通るとき、`<Web ベース>/<owner>/<name>/discussions/<番号>` を開く。通らなければ今までどおり `<Web ベース>/<owner>/<name>/discussions` を開く
- Release のスレッドは、一覧を取るときに、Issue と Pull request のイベントと同じ仕組み（スレッドの ID と `updated_at` ごとにメモリに覚え、同時に取る数とレート制限を守る）で `GET <API ベース>/repos/<owner>/<name>/releases/<ID>` を送り、`tag_name` を覚える。タグを覚えていれば `<Web ベース>/<owner>/<name>/releases/tag/<タグ>` を開き、覚えていなければ（取る前、取れなかった、タグが検証を通らない）今までどおり `<Web ベース>/<owner>/<name>/releases` を開く
- 新着の Release のタグは、イベントと同じく一覧を知らせる前に取るので、macOS の通知のクリックでも個別のページが開く
- API が返す `html_url` は使わない。タグは検証してから、Web ベース URL に足して組み立てる
- 一覧の行の表示は変えない（Discussion と Release には今までどおり番号を出さない）

## Capabilities

### New Capabilities

（なし）

### Modified Capabilities

- `ui`: 「通知のスレッドを開く」の Discussion と Release の URL の決め方を変える
- `polling`: 「スレッドのイベントの取得」の対象に、リリースの ID を持つ Release のスレッドを加え、タグを覚える
- `github-api`: Release のタグを取るリクエスト（`GET /repos/{owner}/{name}/releases/{id}`）とレスポンスの扱いを足す

## Impact

- コード: `Mewbell/GitHubAPI/ThreadWebURL.swift`（Discussion の番号と Release のタグからの組み立て、リリースの ID の検証）、`Mewbell/GitHubAPI/NotificationThread.swift`（リリースの ID）、`Mewbell/GitHubAPI/ThreadEvent.swift`（`ThreadDetails` にタグ）、`Mewbell/GitHubAPI/GitHubAPIClient.swift`（リリースの取得）、`Mewbell/Polling/ThreadDetailsCache.swift`（取る対象）とそれぞれのテスト
- ネットワーク: 新しく `GET /repos/{owner}/{name}/releases/{id}` を送る。トークンを付けて送るので `.claude/rules/security.md` のネットワークの項目が適用される（送り先の検査、リダイレクトの拒否、キャッシュしない、ボディをログに出さない）。リクエストは Release のスレッドごとに `updated_at` が変わるたびに 1 回で、イベントの取得と同じレート制限の扱いに従う
- URL を開く処理: 開く URL の組み立てを変えるので、`ThreadWebURL` の検査（`https`・アカウントのホスト）をそのまま通す。API の文字列（タグ）を URL に入れるので、タグの検証を足す
- トークン: 扱いは変えない。今までどおりポーラーの actor の中にだけ持ち、永続化しない。覚えたタグもメモリにだけ持ち、アプリの終了で捨てる
- gh サブプロセス: 触れない
