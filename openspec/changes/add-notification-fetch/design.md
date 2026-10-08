# Design

## Context

M1 の時点の構成（動機は proposal.md の Why、満たすべき振る舞いは `specs/github-api`、`specs/polling`、`specs/accounts`、`specs/ui`）:

- `AccountStore`（`@MainActor @Observable`）が `DiscoveryState` を持ち、`.accounts([AccountStatus])` のとき各アカウントの `TokenState`（`.fetching` / `.ready` / `.unavailable`）を UI に見せる。トークンは `CredentialStore`（actor）にだけあり、`AccessToken.value` は M2 で `Authorization` を作るために `internal` で読める
- `AccountDiscovery`（actor）が gh の検出からトークン取得までを行う。トークンを持っていないアカウントだけ `gh auth token` を実行する。`AccountStore.reload()` は読み直しの `Task` を 1 つだけ持ち、重なった要求は終わった後にもう 1 回だけ読み直す
- `AppDelegate` が `AccountStore` を持ち、起動時に読み込み、終了時に `.terminateLater` でトークンを捨てる
- `Mewbell/` と `MewbellTests/` は同期フォルダーなので、`GitHubAPI/` と `Polling/` を作ってファイルを置けばターゲットに入る。テストは Swift Testing、偽物は `MewbellTests/Support/` にある（`FakeProcessRunner`、`LockedValue`）
- 既定の actor 分離は `nonisolated`、strict concurrency は `complete`

GitHub の Notifications API の前提:

- `GET /notifications` のスレッドに Web の URL（`html_url`）は無い。`subject.url` は API の URL（`/repos/{owner}/{repo}/pulls/{n}` など）で、Discussion や CheckSuite では `null` のことがある。`repository.full_name` はある
- `Last-Modified` は文字列のまま `If-Modified-Since` に返せばよい（解析しない）。`X-Poll-Interval` は秒数の文字列
- gh のトークン（OAuth アプリのトークン）は classic 系なので `X-OAuth-Scopes` が付く。gh の既定のスコープは `repo`、`read:org`、`gist` を含む
- `gh auth refresh` は `--hostname` を取るが `--user` を取らず、アクティブなアカウントにだけ効く（手元の gh 2.102.0 の `--help` で確認）

## Goals / Non-Goals

**Goals:**

- トークンを送る経路を 1 か所（`GitHubAPIClient` のリクエスト組み立て）に絞り、オリジン検査・リダイレクト拒否・キャッシュなしをその 1 か所で保証する
- ネットワークと時計を差し替えて、ページネーション・条件付きリクエスト・間隔・待ち時間・401 の取り直しをユニットテストで確かめられるようにする
- M3（macOS 通知・既読化）と M4（`participating` の切替・アカウントの ON/OFF）で、ポーラーとクライアントを作り直さずに足せる形にする

**Non-Goals:**

- 取得した通知や `Last-Modified` の永続化（起動直後は毎回条件なしで取得する）
- ネットワークの到達性の監視（`NWPathMonitor`）。失敗したら待ち時間を延ばすだけで足りる
- スレッドの詳細（PR の状態、コメント）の追加取得

## Decisions

### D1. モジュールと型の分担

| 置き場所 | 型 | 役割 |
| --- | --- | --- |
| `GitHubAPI/` | `APIEndpoints` | ホストから API ベース URL と Web ベース URL を導く。URL がその API ベースと同じオリジンで、パスがベースのパスの下にあるかを判定する（`isAllowedRequestURL(_:)`） |
| `GitHubAPI/` | `HTTPTransport`（protocol）と `URLSessionTransport` | `URLRequest` を送って `(Data, HTTPURLResponse)` を返す。ボディの上限、リダイレクトの拒否、キャッシュと Cookie の無効化はここで行う（D3） |
| `GitHubAPI/` | `GitHubAPIClient` | `fetchNotifications(endpoints:token:ifModifiedSince:)`。リクエストの組み立て（トークンを付ける唯一の場所）、オリジン検査、ページネーション、状態コードの分類、スコープの読み取り（D2） |
| `GitHubAPI/` | `NotificationThread`、`RepositoryName`、`SubjectKind` | 検証済みのスレッドの値型。デコード用の DTO は `fileprivate` にし、検証を通ったものだけを外に出す |
| `GitHubAPI/` | `LinkHeader` | `Link` ヘッダーから `rel="next"` の URL を読む |
| `GitHubAPI/` | `ThreadWebURL` | スレッドから開く Web の URL を組み立て、`https` とホストの一致を確かめる（D8） |
| `Polling/` | `PollSchedule` | 結果から次の取得までの待ち時間を決める純粋な関数（D5） |
| `Polling/` | `AccountPoller`（actor） | 1 アカウントのポーリングのループと状態（`Last-Modified`、失敗の回数、スコープ確認済みか）を持つ（D4） |
| `Polling/` | `NotificationStore`（`@MainActor @Observable`） | アカウントごとの `FeedState` を UI に見せ、アカウントの状態に合わせて `AccountPoller` を起動・停止する |
| `Polling/` | `TokenProviding`（protocol） | ポーラーがトークンを受け取る口。`currentToken(for:)` と `refreshToken(for:)`（捨てて取り直す）。実装は `CredentialStore` と `AccountDiscovery` に委ねる |
| `Accounts/` | `AccountDiscovery`、`CredentialStore` | `refreshToken(for:)` と `CredentialStore.remove(_:)` を足す。同じアカウントのトークン取得の `Task` を共有する（D6） |
| `UI/` | `NotificationListView`、`AccountSectionView`、`ThreadRow`、`FeedStatusView` | アカウントの区画、リポジトリの見出し、スレッドの行、取得の状態と案内（D9） |

`AccountListView` は `AccountSectionView` に置き換えて消す。

### D2. API クライアント

- `GitHubAPIClient` は可変の状態を持たない `Sendable` な struct にし、`AccountPoller`（actor）の中からだけ呼ぶ。トークンは引数で受け取り、1 回の `fetchNotifications` の中のすべてのページに同じトークンを使う（取得の途中で `CredentialStore` を引き直さないので、ページの間でトークンが入れ替わらない。Gitify #2176 の原因は共有クライアントのヘッダーをアカウントごとに書き換えていたこと）
- リクエストの組み立ては 1 つの private メソッドにまとめる。ここで `endpoints.isAllowedRequestURL(url)` を確かめてから `Authorization: Bearer <token>`、`Accept: application/vnd.github+json`、`X-GitHub-Api-Version: 2022-11-28`、`User-Agent: Mewbell/<CFBundleShortVersionString>` を付ける。検査に通らなければ送らずに `.rejectedURL` を返す
- 1 ページ目の URL は `<API ベース>/notifications?all=false&participating=false&per_page=50` を `URLComponents` で組み立てる。`participating` は引数で受け取り（既定 `false`）、M4 の切替で使えるようにする
- 2 ページ目以降は `Link` の `rel="next"` をたどる。最大 10 ページ。`If-Modified-Since` は 1 ページ目にだけ付ける
- 結果は次の enum で返す

  ```swift
  enum NotificationsFetchResult {
      case updated(threads: [NotificationThread], lastModified: String?, pollInterval: Int?, scopes: OAuthScopes)
      case notModified(pollInterval: Int?)
      case unauthorized                 // 401
      case rateLimited(retryAt: Date)   // 403 + X-RateLimit-Remaining: 0 / Retry-After
      case forbidden                    // それ以外の 403
      case invalidRequest               // 422
      case failed(FetchFailure)         // 通信・タイムアウト・その他の状態コード・ボディ超過・リダイレクト・URL 拒否・デコード失敗
  }
  ```

  `OAuthScopes` は `X-OAuth-Scopes` を `,` で区切って空白を除いた集合と、ヘッダーが無かったかどうかを持つ。`allowsNotifications` は `repo` か `notifications` を含むときだけ true
- 2 ページ目以降が 304 になることは無いが、来たら `failed` にする。途中のページで失敗したら、それまでのページは捨てて全体を `failed` にする（`Last-Modified` を更新しないため）
- スレッドのデコードは、1 件ずつ `try?` で DTO にし、`id`・`updated_at`・`subject.title`・`subject.type`・`repository.full_name` が揃い、`full_name` が `<owner>/<name>`（GitHub のログイン名とリポジトリ名に使える文字だけ）のものを残す。`updated_at` は ISO 8601（`Date.ISO8601FormatStyle`）で読む
- 代替案: `subject.url` にトークン付きで追加リクエストして `html_url` を取る → スレッドの数だけリクエストが増え、トークンを送る URL の種類も増える。採らない（D8 で組み立てる）
- 代替案: クライアントを actor にする → 状態を持たないので意味が無い。ネットワークを呼ぶのは `AccountPoller` の中だけ、という形で「actor に閉じ込める」約束を守る

### D3. トランスポートと URLSession の設定

- `URLSessionTransport` は `URLSessionConfiguration.ephemeral` をもとに、`urlCache = nil`、`requestCachePolicy = .reloadIgnoringLocalCacheData`、`httpCookieStorage = nil`、`httpShouldSetCookies = false`、`httpCookieAcceptPolicy = .never`、`urlCredentialStorage = nil`、`timeoutIntervalForRequest = 30` にする。`httpAdditionalHeaders` には何も入れない
- セッションの delegate（`URLSessionTaskDelegate`）の `willPerformHTTPRedirection` で常に `nil` を返し、リダイレクトをたどらない。3xx のレスポンスはそのまま返り、クライアントが `failed(.redirect)` にする。同じオリジンのリダイレクトも拒否する（Notifications API はリダイレクトしないので、許す理由が無い。同じオリジンでも `URLSession` がヘッダーをどう引き継ぐかに依存しなくて済む）
- ボディは `bytes(for:)` で読み、上限（5 MiB）を超えたらタスクをキャンセルして `failed(.bodyTooLarge)` にする。`Content-Length` が上限を超えているときは読む前に失敗にする
- delegate の `didReceive challenge` は既定の処理（`.performDefaultHandling`）のままにし、証明書の検証を緩めない
- 代替案: `URLSession.shared` → キャッシュと Cookie が有効で、設定を変えられない。採らない

### D4. ポーリングのループ

`AccountPoller` は 1 アカウントに 1 つの actor で、`start()` で `Task` を 1 つ起動し、`stop()` でキャンセルする。ループは次のとおり。

1. `TokenProviding.currentToken(for:)` でトークンを受け取る。無ければ（アカウントのトークンが捨てられた）「認証エラー」にして止まる
2. `fetchNotifications` を呼ぶ（`If-Modified-Since` は持っている `lastModified`）
3. 結果ごとに状態を更新する
   - `updated`: スコープ未確認なら `scopes.allowsNotifications` を確かめ、足りなければ「スコープ不足」にして止まる（スレッドは出さない）。足りていればスコープ確認済みにし、スレッドと `lastModified` を更新して「取得できた」にする
   - `notModified`: 「取得できた」の時刻だけ更新する
   - `unauthorized`: 直前にトークンを取り直していなければ `refreshToken(for:)` を呼び、取れたら `lastModified` とスコープ確認済みを消してすぐ 2 に戻る。直前に取り直していた、または取れなかったら「認証エラー」にして止まる
   - それ以外: 失敗の回数を増やし、「失敗して待っている」にする（スレッドは前回のまま）
4. `PollSchedule` で待ち時間を決めて、注入した `sleep`（既定は `ContinuousClock` の `Task.sleep(for:)`）で待つ。`ContinuousClock` はスリープ中も進むので、復帰したときに時間が過ぎていればすぐ次の取得になる

- 止まったポーラーは `resume()`（再読み込みボタンから）で、`refreshToken(for:)` → `lastModified` とスコープ確認済みを消す → 1 に戻る
- 状態の変化は `@Sendable (FeedState) async -> Void` のコールバックで `NotificationStore` に渡す。`NotificationStore` はポーラーごとに世代番号を持ち、止めたポーラーから遅れて届いた更新を捨てる
- 1 つのアカウントで取得が重ならないことは、ポーラーが `Task` を 1 つしか持たないことで保証する

### D5. 待ち時間の決め方（`PollSchedule`）

- 成功（`updated` / `notModified`）: `max(60, X-Poll-Interval ?? 60)` 秒。失敗の回数を 0 に戻す
- `rateLimited(retryAt)`: `max(60, retryAt - now)` 秒。上限は設けない（`X-RateLimit-Reset` は最大 1 時間先）。`Retry-After` があればそちらを優先する
- その他の失敗: `min(60 × 2^(n−1), 900)` 秒（n は連続した失敗の回数）
- `now` は注入する（テストで固定する）

### D6. トークンの取り直しと読み直しの共有

- `CredentialStore.remove(_ id:)` を足す
- `AccountDiscovery` に `inFlightTokenFetches: [AccountID: Task<AccessToken?, Never>]` を持たせ、`reload` のトークン取得と `refreshToken(for:)` の両方がこれを通るようにする。同じアカウントの取得が走っていれば、その `Task` の結果を待つ（accounts spec の「重なったら共有」）
- `refreshToken(for:)` は、`CredentialStore` から古いトークンを捨て、検証済みの gh のパス（`verifiedGhPath`）で `gh auth token` を実行し、取れたら保存して返す。gh のパスがまだ確かめられていない（読み直しの途中など）ときは nil を返す
- 取り直しに失敗しても `AccountStore` のトークンの状態（「使える」）はすぐには変えない。ポーラーが「認証エラー」を出す。次の読み直しで、トークンを持っていないアカウントとして gh が呼ばれ、状態が直る
- 代替案: 401 のときに `AccountStore.reload()` を呼ぶ → gh の検出や `hosts.yml` の読み取りまでやり直すうえ、どのアカウントのためかを渡せない。採らない

### D7. 並行性の境界

| 型 | 分離 | 動く場所 |
| --- | --- | --- |
| `AccountStore`、`NotificationStore`、View | `@MainActor` | メインスレッド。状態の反映とポーラーの起動・停止の指示だけ |
| `AccountPoller` | actor（アカウントごと） | ループ、`GitHubAPIClient` の呼び出し、JSON のデコード |
| `GitHubAPIClient`、`APIEndpoints`、`PollSchedule`、`ThreadWebURL` | `nonisolated` の値型 | 呼び出し元の actor の上 |
| `URLSessionTransport` | `Sendable` な final class（`URLSession` を持つだけ） | URLSession の delegate キュー |
| `AccountDiscovery`、`CredentialStore` | actor（M1 のまま） | gh の実行とトークンの保持 |

- `AccountStore` は状態が変わったときに `onStateChange` を呼び、`AppDelegate` がそれを `NotificationStore.sync(with:)` につなぐ。`sync` は `.accounts` のうち `tokenState == .ready` のアカウントにポーラーを起動し、それ以外（消えた、`.unavailable`、全体の状態が `.accounts` 以外）のポーラーを止めて `FeedState` を消す。すでに動いているアカウントはそのままにする
- 再読み込みボタンは `AccountStore.reload(userInitiated: true)` と `NotificationStore.resumeStopped()` を呼ぶ。`resumeStopped()` は「スコープ不足」「認証エラー」のポーラーだけに `resume()` を送る。ポップオーバーを開いたときは `AccountStore.reload()` だけを呼ぶ
- 終了時は `applicationShouldTerminate` で `NotificationStore.stopAll()`（すべてのポーラーを止めて状態を消す）→ `AccountStore.discardCredentials()` の順にする

### D8. スレッドの Web の URL

`ThreadWebURL.make(thread:endpoints:)` は ui spec の規則で URL を組み立てる。

- `subject.url` を `URLComponents` で読み、`endpoints.isAllowedRequestURL` を通ったときだけ、API ベースのパスより後ろを `/` で分けて `["repos", owner, name, kind, id]` と照らし合わせる。`owner/name` はスレッドの `repository.full_name` と大文字小文字を無視して一致すること、`pulls`・`issues` の `id` は数字だけ、`commits` の `id` は 7〜40 桁の 16 進数であることを確かめる
- Web の URL は `endpoints.webBaseURL` に、検証済みの `owner`・`name` と固定の語（`pull`、`issues`、`commit`、`releases`、`discussions`）と検証済みの `id` を `appending(path:)` で足して作る。API の文字列をそのまま連結しない
- 最後に、スキームが `https` でホストがアカウントのホストと一致することを確かめる（組み立て方から外れることは無いが、ui spec の約束として独立に確かめる）。一致しなければ nil を返し、View は何も開かない
- 開くのは `NSWorkspace.shared.open(_:)`

### D9. 画面

- `MenuBarContentView` の本体は、`.accounts` のとき `NotificationListView`（`ScrollView`、最大の高さ 480pt）にし、それ以外は M1 の `GuidanceView` のまま。幅は 320pt から 380pt に広げる。見出しの「Mewbell」と再読み込みボタン、Quit ボタンはスクロールの外に置く
- `AccountSectionView` の見出しは「`user` · `host` — 種別」、アクティブの印、トークンの状態のアイコン、取得の状態（最後に成功した時刻は `Text(date, style: .relative)`）。トークンが「使える」でなければ M1 の案内（`gh auth login --hostname`）を出す
- リポジトリの見出しとスレッドの並びは、`FeedState` のスレッドから View の外の純粋な関数（`NotificationGrouping.groups(from:)`）で作り、テストで確かめる
- スレッドの行はボタンにし、種類のアイコン（SF Symbols: Pull request は `arrow.triangle.pull`、Issue は `smallcircle.filled.circle`、Commit は `point.3.connected.trianglepath.dotted`、Release は `tag`、Discussion は `bubble.left.and.bubble.right`、ほかは `bell`）、件名（2 行まで）、理由の表示名（`review_requested` → 「Review requested」など。知らない値は `_` を空白にしたもの）、相対時刻を出す
- スコープ不足・認証エラーの案内は `CommandRow` を使う。コマンドには検証済みのホスト名とユーザー名だけを埋め込む

### D10. テストでの差し替え

- `HTTPTransport` の偽物（`FakeHTTPTransport`）が、受け取った `URLRequest` を記録し、URL ごとに用意した `(状態コード, ヘッダー, ボディ)` を返す。`GitHubAPIClient` と `AccountPoller` のテストで使う。2 アカウントの取得を同時に走らせ、各リクエストの `Authorization` がそのアカウントのトークンだけであることを確かめる
- `URLSessionTransport` は、セッションの設定（`urlCache`、Cookie、`httpAdditionalHeaders`）を直接確かめ、リダイレクトの delegate メソッドを直接呼んで `nil` が返ることを確かめる。実ネットワークには出ない
- `AccountPoller` には `sleep` と `now` を注入する。`sleep` は要求された待ち時間を記録して、テストが進めるまで止まる偽物にする（`AsyncStream` で 1 回ずつ進める）
- `TokenProviding` の偽物で、取り直しの回数と返すトークンを制御する
- `AccountDiscovery` の取り直しの共有は、M1 の `FakeProcessRunner` と、`gh auth token` を待たせるゲートで確かめる
- フィクスチャの JSON とトークンは `test-token-alice` のようなダミーを使う

## セキュリティ

トークンの流れ:

- 取得: M1 と同じく `gh auth token --hostname <host> --user <user>` の標準出力から。加えて、401 のときと、止まったアカウントの再読み込みのときに取り直す
- 保持: `CredentialStore`（actor）の辞書だけ。`AccountPoller` は 1 回の取得の間だけローカル変数で持ち、プロパティには持たない
- 送信: `GitHubAPIClient` のリクエスト組み立てだけが `Authorization` を付ける。送り先はそのアカウントの `APIEndpoints` のオリジンとパスの下だけ（`Link` の続きのページも同じ検査を通す）。リダイレクトはたどらない
- 破棄: M1 の契機（アカウントが消えた、全体の状態が「アカウントあり」以外、終了時）に加え、401 を受け取ったときと、再読み込みで取り直すとき

`.claude/rules/security.md` への対応:

| 項目 | 対応 |
| --- | --- |
| トークンは `gh auth token` の標準出力からだけ取得。`hosts.yml` はホスト名とユーザー名以外を型に載せない | M1 のまま。取り直しも同じ経路（D6） |
| トークンはメモリ上の actor にだけ持つ | 対応。`CredentialStore` だけ。ポーラーはプロパティに持たない |
| トークン専用の型で伏せ字 | M1 の `AccessToken` を使う。`URLRequest` は `description` にヘッダーを出さないが、リクエストやヘッダーをログに渡さない |
| `Logger` を使い可変値は `.private` / ヘッダーとボディを出さない | 対応。ログに出すのはアカウントの識別子、パス、状態コード、失敗の種類だけ（github-api spec）。テストで、401 の結果やエラーの `description` にトークンとボディが含まれないことを確かめる |
| gh の標準エラー出力・API のエラーボディをそのまま出さない | 対応。エラーボディは読まずに捨てる。UI は固定の文言だけ |
| テスト・フィクスチャに本物の形式のトークンを書かない | 対応（`test-token-alice` など） |
| 削除・無効化・終了時にトークンを破棄 | 対応（D7。無効化は M4） |
| `Process` に絶対パスと引数配列 / ログインシェルの例外 | M1 のまま。取り直しは検証済みの gh のパスだけを使う（D6） |
| gh のパスの検証 / 子プロセスの環境変数の除去 / ホスト名・ユーザー名の検証 / タイムアウトと出力上限 | M1 のまま。取り直しも `GhClient.token` を使うので同じ扱いになる |
| トークンを送る先はアカウントの API ベースだけ。送信前にスキーム・ホスト・ポートを確かめる | 対応（D2 の `isAllowedRequestURL`）。別ホスト・http・別ポート・ベースの外のパス・別アカウントのホストへの送信を拒否するテストを書く |
| HTTPS だけ。ATS の例外を入れない | 対応。ベース URL は常に `https`。Info.plist は変更しない |
| リダイレクトは delegate で扱い、オリジンが変わるものを拒否 | 対応（D3）。同じオリジンも含めてすべて拒否する |
| API レスポンスに含まれる URL にトークン付きでアクセスするときもオリジン検査 | 対応（`Link` の `rel="next"`）。`subject.url` などにはトークン付きでアクセスしない |
| ブラウザで開く URL は `https` でホストがアカウントの Web ホストと一致するものだけ。一致しなければ安全な URL で代用 | 対応（D8）。API の URL は開かず、Web の URL を組み立て、合わなければリポジトリのページにする |
| 共有 `URLSession` の `httpAdditionalHeaders` にトークンを入れない / キャッシュを使わない | 対応（D3） |
| Hardened Runtime、緩める entitlement を付けない | 変更しない。外向きの通信に entitlement は要らない（Sandbox 無効） |
| 通知の本文 | 該当しない（M3） |
| 依存の固定 | 外部依存を追加しない |
| GitHub Actions | 変更しない |

## Risks / Trade-offs

- [`gh` の OAuth トークンが GHES で `X-OAuth-Scopes` を返さない構成がある] → スコープ不足として止まり、案内が出る。誤判定だった場合でもトークンは送り先の API にしか送っていない。報告があれば、200 で通知が読めたときはスコープを問わない形に緩めることを検討する（spec の変更になる）
- [未読が 500 件を超えると古い分が出ない] → 10 ページで打ち切る。M2 ではそのまま表示し、打ち切ったことは区画に出さない。M4 で件数の表示を考える
- [`Last-Modified` を持たずに起動するたびに全ページを取る] → 起動時の 1 回だけで、`X-Poll-Interval` 以上の間隔も守るので、レート制限への影響は小さい
- [`refreshToken` を、読み直しが gh のパスを確かめ直している最中に呼ぶ] → `verifiedGhPath` が nil なら取り直さずに「認証エラー」にする。再読み込みで回復できる
- [スリープからの復帰直後はネットワークがまだ無く、通信の失敗が続く] → 待ち時間が 60 秒から延びるだけで、成功すれば戻る
- [ポップオーバーの `onAppear` で `AccountStore.reload()` が走るたびに `sync` が呼ばれる] → 状態が変わらなければ `AccountStore.apply` が代入しないので `onStateChange` も呼ばれない。呼ばれても `sync` は差分だけを扱う
- [`ThreadWebURL` の規則に合わない種類が多い（Release はタグの URL を作れないなど）] → リポジトリのページなどの近い URL を開く。正確な URL のために追加のリクエストはしない（D2 の代替案）

## Migration Plan

M1 からの移行は無い。永続化するものを増やさないので、ロールバックは PR を戻すだけでよい。
