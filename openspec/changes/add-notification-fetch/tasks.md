# Tasks

## 1. URL の導出とスレッドのモデル（GitHubAPI）

- [x] 1.1 `APIEndpoints` を実装する（API ベース URL・Web ベース URL の導出と `isAllowedRequestURL(_:)`。design.md D1）。確認: `github.com`・`acme.ghe.com`・`github.example.com` の API / Web ベース URL のテストと、同じオリジンでパスがベースの下にある URL だけが通り、別ホスト・`http`・別ポート・GHES でベースの外のパス（`https://ghe.example.com/other`）・ユーザー情報付きの URL が拒否されるテストが通る
- [x] 1.2 `RepositoryName`、`SubjectKind`、`NotificationThread` と、DTO からの 1 件ずつのデコードを実装する（design.md D2）。確認: 正常なスレッド、`subject.url` が `null`、`repository.full_name` が無い・`owner/name` の形でない、`updated_at` が読めない、のフィクスチャで、壊れたものだけが読み飛ばされるテストが通る
- [x] 1.3 `LinkHeader` を実装する（`rel="next"` の URL だけを読む）。確認: `next` と `last` が並ぶヘッダー、`next` が無いヘッダー、引用符や空白の揺れ、壊れたヘッダーのテストが通る

## 2. トランスポートとクライアント（GitHubAPI）

- [x] 2.1 `HTTPTransport` と `URLSessionTransport` を実装する（ephemeral、キャッシュ・Cookie・資格情報の保存なし、`httpAdditionalHeaders` なし、30 秒のタイムアウト、リダイレクトの拒否、5 MiB のボディ上限。design.md D3）。確認: セッションの設定値を確かめるテストと、リダイレクトの delegate メソッドを直接呼んで `nil` が返るテストが通る
- [x] 2.2 `MewbellTests/Support/FakeHTTPTransport` を作る（URL ごとの応答、受け取った `URLRequest` の記録）。確認: 2.3 以降のテストで使える
- [x] 2.3 `GitHubAPIClient.fetchNotifications` のリクエスト組み立てを実装する（トークンを付ける唯一の場所、オリジン検査、`Authorization: Bearer`・`Accept`・`X-GitHub-Api-Version`・`User-Agent`、クエリ `all=false&participating=false&per_page=50`、1 ページ目だけ `If-Modified-Since`）。確認: ヘッダーとクエリのテスト、`If-Modified-Since` の有無のテスト、許されない URL には送らずに `failed(.rejectedURL)` になるテストが通る
- [x] 2.4 ページネーションを実装する（`rel="next"` を 10 ページまで、続きのページにも同じオリジン検査、途中で失敗したら全体を `failed`）。確認: 2 ページで 53 件になるテスト、`next` が別ホスト・`http` を指すと送らずに失敗するテスト、11 ページ目を取りに行かないテスト、2 ページ目の失敗で全体が失敗になるテストが通る
- [x] 2.5 状態コードの分類とスコープの読み取りを実装する（200 / 304 / 401 / 403 のレート制限と拒否 / 422 / 3xx / その他 / 通信の失敗 / ボディ超過、`X-OAuth-Scopes` と `X-Poll-Interval` と `Last-Modified` の読み取り）。確認: 各状態コードのテスト、`Retry-After` と `X-RateLimit-Reset` から時刻を出すテスト、スコープ `repo` / `notifications` / どちらも無い / ヘッダーが無い のテストが通る
- [x] 2.6 トークンとボディを漏らさないことを確かめる。確認: 2 アカウント（`test-token-alice` と `test-token-bob`）の 2 ページの取得を同時に走らせ、各リクエストの `Authorization` がそのアカウントのトークンだけであるテストと、401 のときの結果や `failed` の `String(describing:)`・`String(reflecting:)` にトークンとエラーボディの文字列が含まれないテストが通る。ログ（`Logger`）にはパス・状態コード・失敗の種類だけを `.private` で出していることをコードで確かめる

## 3. トークンの取り直し（Accounts）

- [x] 3.1 `CredentialStore.remove(_:)` を足す。確認: 指定したアカウントのトークンだけが消え、`close()` の後も動くテストが通る
- [x] 3.2 `AccountDiscovery` に同じアカウントのトークン取得を共有する仕組みと `refreshToken(for:)` を足し、`AccountDiscovering` に公開する（design.md D6）。確認: 古いトークンが捨てられて新しいトークンが保存されるテスト、`gh auth token` を待たせている間に読み直しと `refreshToken` が重なっても実行が 1 回だけのテスト、gh のパスを確かめていないときは nil を返すテスト、取り直せなかったときに古いトークンが残らないテストが通る

## 4. ポーリング（Polling）

- [x] 4.1 `PollSchedule` を実装する（design.md D5）。確認: `X-Poll-Interval` が 120 / 10 / 無し / 数値でない、レート制限の `Retry-After` と `X-RateLimit-Reset`（過去の時刻を含む）、失敗の回数 1〜6 回（60・120・240・480・900・900 秒）のテストが通る
- [x] 4.2 `TokenProviding` と、`CredentialStore`・`AccountDiscovery` を使う実装を作る。確認: 偽物を使う 4.3 のテストと、実装が `CredentialStore` から読むことをテストで確かめる
- [x] 4.3 `AccountPoller` のループを実装する（design.md D4。`sleep` と `now` を注入、状態の変化をコールバックで渡す）。確認: 偽のトランスポートと偽の `sleep` で、最初の取得が条件なし・2 回目に `If-Modified-Since` が付く・304 でスレッドが変わらない・途中のページの失敗で `Last-Modified` が変わらない・失敗が続くと待ち時間が延び、成功で戻る・失敗の間も前回のスレッドが残る、のテストが通る
- [x] 4.4 401 とスコープ不足の扱いを実装する。確認: 401 → 取り直し → 条件なしでやり直して成功するテスト、取り直しても 401 で「認証エラー」になり以後リクエストも取り直しもしないテスト、取り直せないと「認証エラー」になるテスト、スコープ不足で止まりスレッドを出さないテスト、`resume()` で取り直してから条件なしで再開するテストが通る
- [x] 4.5 `NotificationStore`（`@MainActor @Observable`）を実装する（`sync(with:)`、`resumeStopped()`、`stopAll()`、世代番号で遅れた更新を捨てる。design.md D7）。確認: 「使える」になったアカウントだけポーラーが起動する、消えた・`.unavailable` になった・全体の状態が `.accounts` 以外になったアカウントのポーラーが止まり状態が消える、動いているアカウントと止まっているアカウントは `sync` で作り直されず再開もしない、`resumeStopped()` は止まったポーラーにだけ届く、止めたポーラーからの更新が反映されない、のテストが通る

## 5. 画面とつなぎ込み（UI / App）

- [x] 5.1 `NotificationGrouping.groups(from:)` を実装する（リポジトリは最新のスレッドの更新日時順、スレッドは更新日時順）と、理由の表示名の対応を作る。確認: 並び順と、知らない `reason` の表示名のテストが通る
- [x] 5.2 `ThreadWebURL` を実装する（design.md D8）。確認: PR・Issue・Commit（github.com、`*.ghe.com`、GHES の `/api/v3`）、Release・Discussion、`subject.url` が `null`・別ホスト・`http`・リポジトリ名が一致しない・番号が数字でない・SHA が 16 進でない、の各ケースで ui spec どおりの URL（または代用のリポジトリのページ）になり、結果がすべて `https` でアカウントのホストを指すテストが通る
- [x] 5.3 `AccountSectionView`、`ThreadRow`、`FeedStatusView` を実装する（取得中・取得できた・失敗して待っている（レート制限を含む）・スコープ不足（アクティブ / アクティブでない）・認証エラー・未読 0 件・トークンを取れない）。`AccountListView` を消す。確認: 各状態と 2 アカウント・複数リポジトリを含む SwiftUI プレビューを表示して ui spec と照らし、スコープ不足の案内のコマンドを `pbpaste` で確かめる
- [x] 5.4 `MenuBarContentView` を `NotificationListView`（スクロール、最大 480pt、幅 380pt）にし、スレッドのクリックで `ThreadWebURL` の URL を `NSWorkspace` で開く。確認: プレビューで見出しと Quit がスクロールの外に残ることを確かめる
- [x] 5.5 `AppDelegate` で `NotificationStore` を持ち、`AccountStore.onStateChange` を `sync(with:)` に、再読み込みボタンを `resumeStopped()` に、終了処理を `stopAll()` → `discardCredentials()` の順につなぐ。テストのホストとプレビューではポーリングを始めない。確認: `AccountStore` の状態を変えると `sync` が呼ばれるテストが通り、`bash scripts/run.sh` で起動して自分のアカウントの通知が一覧に出る
- [x] 5.6 README の注記を M2 の状態に更新し、取得する通知の範囲（未読・`participating=false`）とポーリングの間隔（`X-Poll-Interval`、下限 60 秒）を書く。確認: README の差分を読む

## 6. 最終確認

- [x] 6.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する。Release の `.app` の Info.plist に ATS の例外が無く、`codesign -d --entitlements -` に緩める entitlement が無いことも確かめる
- [x] 6.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 6.3 手元で起動して確認した: (a) 自分のアカウントの未読がアカウント → リポジトリの順に出る、(b) PR・Issue のスレッドをクリックすると正しい Web ページが開き、一覧では未読のまま残る、(c) `log show --predicate 'subsystem == "com.codingfeline.mewbell"' --info --debug` で、2 回目以降の取得が 304 になり、間隔が 60 秒以上空いていることを確かめる、(d) 再読み込みを押しても間隔より早く取得しない、(e) ネットワークを切ると「失敗して待っている」になり一覧が残り、戻すと回復する、(f) スコープ不足・認証エラー・401 の取り直しは 4.4 のテストで確かめたものとし、PR 本文にそう書く
- [x] 6.4 トークンが残っていない・漏れていないことを確かめた: 一覧が出た後、`defaults read com.codingfeline.mewbell`、`~/Library/Application Support/com.codingfeline.mewbell/`、`~/Library/Caches/com.codingfeline.mewbell/`、`~/Library/HTTPStorages/com.codingfeline.mewbell/`、`log show`（6.3 と同じ条件）に `gh auth token` の出力が含まれないことを、`grep -c -F "$(gh auth token)"` のように件数だけで確かめる

## 7. 別コンテキストでのレビュー

- [x] 7.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 7.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 7.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認（security.md のどの項目を満たしたか）を PR 本文に書いた
