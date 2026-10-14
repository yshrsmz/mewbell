# Mewbell の設計方針

この文書は、Mewbell のコードの構造の約束（層・依存の向き・状態の持ち方・境界・部品の足し方など）を「今の形」として定める。振る舞い（ユーザーや API から見えること）は `openspec/specs/` が、セキュリティの約束は `.claude/rules/security.md` が受け持ち、この文書には書かない。

設計・実装・レビューで判断が要るときに読む。この文書を変えるときは、プロジェクトのスキル `update-architecture-doc` の手順に従い、`bash scripts/check-architecture.sh` を通す。

## 方針が割れたときの優先順位

1. `openspec/specs/` の要件
2. `.claude/rules/security.md`
3. この文書の原則
4. Swift と Apple のプラットフォームの慣用

原則と慣用が食い違うときは、原則の「理由」がその場面に当てはまるかで決める。当てはまらないなら、それは原則への異議として扱う（下の表）。

## 指摘の仕分けとの関係

レビューの指摘は、この文書に照らして次のように扱う。

| 指摘 | 扱い |
| --- | --- |
| 原則に反している | 直す。原則の ID を添える |
| 原則が「採らなかった案」に挙げた形を求めている | 直さない。理由は原則の ID |
| 原則そのものへの異議（理由がその場面に当てはまらない、など） | AskUserQuestion で確かめる。採るなら原則を改める |
| 方針が何も決めていない論点 | AskUserQuestion で確かめる。決めたことは change の design.md に書き、change をまたいで効くものは同じ change でこの文書にも足す |

## 方針を足す・改める

- 足す: 方針に無い論点を change の中で決めたら、その change の design.md に Decision として書く。別の機能を足すときにも同じ問いが出るなら、change をまたいで効くものとして、同じ change でこの文書に原則を足すか、既存の原則に書き足す。
- 改める: 原則を変えるときは、そのための change を起こす（振る舞いが変わらなければ `skip_specs: true`）。design.md に改める理由と採らなかった案を書く。今のコードが新しい原則に合わなくなるなら「既知の逸脱」に書く。
- ID は `A1` からの通し番号で、再利用しない。廃止した原則は見出しを残す。ほかの文書からは `A3` のように ID だけで引く。

## 原則

### A1. 依存は下の層へ向け、型は使う層のうち最も下に置く

- **原則**: 層は 3 段に分ける。下の層は `GhCLI/` と `GitHubAPI/`、中間の層は `Accounts/`・`Polling/`・`Notifications/`・`Settings/`、上の層は `UI/` と `App/` である。下の層は中間と上の層の型を使わない。中間の層は同じ高さとして互いの型を使ってよいが、上の層の型は使わない。store と actor を持つのは中間の層で、`UI/` は表示と、表示だけに使う状態（折りたたみの `ListExpansion`、アニメーションの `DisclosureAnimations`）を受け持つ。SwiftUI と AppKit を import するのは `UI/` と `App/` だけにする。本物の部品は `AppDelegate` で組み立て、長いものは `.live(...)` にまとめて `AppDelegate` から呼ぶ。型や値は、それを使う層のうち最も下の層に置く。1 つの層だけが使うならその層に、複数の層が使うなら共通の依存先に置く（`RepositoryGroup` は `Polling/`、`hostLabel` は `UI/`、ポップオーバーと通知の両方が使う `AccountID.displayName` は `Accounts/`）。
- **理由**: 下の層を UI 抜きで単体テストでき、トークンを扱う層が表示の都合で変わらない。置き場所を決める軸を 1 つにすると、移す・移さないの判断がレビューの周ごとに揺れない。
- **採らなかった案**:
  - 値を作る層に置く: 表示のためだけに作る値（`hostLabel` など）の置き場所を別に決める必要がある
  - 中間の層にも順序を決めて上への参照を禁じる: 設定・アカウント・ポーリング・通知は互いの変化に応じて動き、順序を決めても参照を間接にする部品が増えるだけになる
  - SwiftPM のモジュールに分けて依存の向きをコンパイラで守る: プロジェクトの構成を変える大きさに見合わない。import だけを lint で守る
- **適用外**: なし
- **根拠**: add-gh-account-discovery D1、add-notification-fetch D1、add-system-notifications D1、add-settings D1、add-diagnostics D1、update-notification-list D1・D6、update-list-readability D8、add-architecture-principles D6・D7。import は lint の `ui_frameworks_outside_ui` で守る

### A2. View と store は @MainActor、外部とのやり取りは actor に閉じ込める

- **原則**: Swift 6 の strict concurrency を有効にし、`@MainActor` を明示する。View と、View が読む `@Observable` の型は `@MainActor` に置く。gh の実行・ファイルの読み取り・HTTP は、関心ごと（アカウントごと）の actor の中で行う。状態を持たない部品は actor にせず、`nonisolated` の `Sendable` な値型にして呼び出し元の actor の上で動かす（`GitHubAPIClient`、`APIEndpoints`、`PollSchedule`）。actor は `@MainActor` の状態を読まず、要る値は呼び出した時点の `Sendable` な値として引数で受け取る（`DiscoveryOptions`）。actor の外から同期的に触る状態は `Synchronization` の型（`Mutex` など）で持ち、actor の中だけで触る状態は actor の `var` で持つ。
- **理由**: どのスレッドで何が動くかを型で決めれば、コンパイラが境界を守る。スナップショットで渡すと、どの値で動いたかがはっきりする。
- **採らなかった案**:
  - 状態の無いクライアントを actor にする: 守る状態が無く、意味が無い
  - actor の中から `MainActor.assumeIsolated` などで設定を読む: 読み直しの開始時点の値を引数で渡す方が、どの値で読んだかがはっきりする
  - `SWIFT_DEFAULT_ACTOR_ISOLATION` で既定を `MainActor` にする: 境界が宣言から読み取れなくなる
- **適用外**: なし
- **根拠**: add-project-skeleton D1・D3、add-gh-account-discovery D2、add-notification-fetch D2・D7、fix-stale-notification-list D2、add-settings D3、add-diagnostics D6、remove-poller-flag-atomic D1

### A3. 状態は残す期間で置き場所を決め、正本は 1 か所に持つ

- **原則**: ポップオーバーや設定ウィンドウを閉じれば消えてよい状態は View の `@State` に置く。起動している間だけ残す状態は `AppDelegate` が持つ `@MainActor` の型（`ListExpansion`）に置く。起動をまたいで残す状態は `AppSettings` と `SettingsStorage` を通して UserDefaults に置く。トークンは actor の中だけに置く。アカウントの一覧の状態の正本はポーラー（`AccountPoller`）が持ち、`NotificationStore` はポーラーが知らせた写しを持つ。一覧からすぐ外すのはよいが、外すかどうかの判断と状態からの除去はポーラーで行う。消えたアカウントの状態を捨てる規則は `DiscoveryState.retainedAccountIDs` の 1 か所にまとめ、捨てる判断は `NotificationStore.sync` の 1 か所で行う。`@Observable` にするのは View が読む型だけにし、観測の粒度は読む View の粒度に合わせる（`ListExpansion` は観測させず、アカウントごとの `AccountExpansion` を観測させる）。派生データは元のデータが変わる場所で 1 回だけ作り、描画の中では作らない。
- **理由**: 残す期間から置き場所が 1 つに決まる。正本と捨てる規則を 1 か所に置けば、経路ごとの食い違いが起きない。観測の粒度を View に合わせると、ある区画の操作でほかの区画が描き直されない。
- **採らなかった案**:
  - `@AppStorage` を View で直接使う: store や actor へ変更を伝える経路が View に散らばり、テストもしにくい
  - `@SceneStorage` / `@AppStorage` で折りたたみを持つ: ディスクに残り、「起動中だけ」に反する
  - `NotificationStore` の側でだけ一覧から外す: ポーラーの状態に残っていると、次の `304` の後の知らせでスレッドが戻る
- **適用外**: なし
- **根拠**: add-system-notifications D4、add-thread-actions D5・D8、add-settings D1・D2、add-diagnostics D3、update-notification-list D1・D3・D4・D6

### A4. View に ViewModel の層を置かず、文言は View の外で決める

- **原則**: データの store（`AccountStore`、`NotificationStore`、`AppSettings` など）を直接受け取るのは、シーンのルートの View（`MenuBarContentView`、`SettingsView`、`MenuBarLabel`）だけにする。それ以外の View は、値と、操作のクロージャ（`ThreadListActions` など）と、表示の状態の型（`ListExpansion`、`AccountExpansion`）だけを受け取る。表示する文言・記号・コマンドは、View の外の純粋な enum や値型で決め、単体テストする（`ThreadReason`、`ThreadEventText`、`ThreadIcon`、`ActionFailureMessage`、`GhCommand`、`UnreadBadge`）。書体の大きさはテキストスタイルで指定し、ポイント数を書かない。
- **理由**: `@Observable` の store をルートが読めば、変換のための層を挟まずに済む。下位の View が値とクロージャだけを受け取れば、プレビューとテストで store を組まずに済み、どの操作が起きるかが引数で読める。文言を View の外に置けば、描画抜きでテストできる。
- **採らなかった案**:
  - View ごとに ViewModel を置く: store と同じ状態を二重に持ち、同期の経路が増える
  - View で `@Environment(\.openURL)` を使って開く: テストで開いた URL を確かめられず、開く前の検査の場所が分かれる
  - 書体を共有の型（`ListTypography` など）にまとめる: ほとんどが 1 行の modifier で、型を挟むと読む場所が増えるだけになる
- **適用外**: なし
- **根拠**: add-notification-fetch D9、add-system-notifications D8、add-thread-actions D7、add-web-notifications-link D2、update-list-readability D1・D7、add-thread-latest-event §2。書体のポイント数は lint の `fixed_font_size` で守る

### A5. 外部はプロトコルかクロージャの裏に置き、テストでは本物に触れない

- **原則**: gh の実行（`ProcessRunning`）、HTTP（`HTTPTransport`）、通知センター（`UserNotificationCenter`）、macOS の通知の出し分け（`ThreadNotifying`）、設定の保存（`SettingsStorage`）、ログイン項目（`LoginItemService`）、アカウントの検出（`AccountDiscovering`）、トークン（`TokenProviding`）はプロトコルの裏に置く。URL を開く処理・ポーラーの生成と、テストで制御する必要のある時刻と待ちは、クロージャで注入する。テストのホストやプレビューとして起動されたときは、本物を作らない（依存を nil や `InertLoginItem` にする）。URL を開くクロージャには既定値を持たせない。
- **理由**: テストが gh・ネットワーク・通知センター・`UserDefaults.standard`・ブラウザに触れずに通る。URL を開く処理に既定値が無ければ、テストで渡し忘れるとコンパイルが通らず、本物のブラウザが開くことはない。
- **採らなかった案**:
  - URL を開く処理の既定値を `NSWorkspace.shared.open` にする: テストで渡し忘れると、本物のブラウザが開く
- **適用外**: 本物を確かめること自体が目的のテスト（`SubprocessRunner` のテストが OS 付属のコマンドを起動する、`hosts.yml` の読み取りのテストが一時ディレクトリの実ファイルを読む、設定の保存のテストが `UserDefaults(suiteName:)` を使う、`GitHubAPIClientTests` が本物の `URLSessionTransport` の設定を確かめる）
- **根拠**: add-project-skeleton D4、add-gh-account-discovery D7・D9、add-notification-fetch D10、add-system-notifications D6、add-settings D11、add-thread-latest-event §4、add-architecture-principles D10

### A6. 危ない処理の関所は 1 か所にし、内側は private で守る

- **原則**: `Authorization` を付けて送るのは `GitHubAPIClient.send` だけにする。ブラウザで開く URL の検査は `ThreadWebURL` だけで行い、API 由来の URL を開くのは `NotificationStore` の `openURL` だけにする。子プロセスの環境変数は `GhEnvironment` だけが作る。案内に出す gh のコマンドの文字列は `GhCommand` だけが作る。新しい処理は新しい経路を作らずに既存の関所を通す。関所の内側（`Authorization` を付ける `send` など、検査を経ずに危ない操作をする関数）は `private` を保つ。行数の上限でファイルを分けるときも、関所の内側は分けずに、そのファイルだけ上限を緩める（`swiftlint:disable file_length`）。
- **理由**: 検査を 1 か所に集めると、security.md の約束を確かめる場所とテストが 1 つで済む。内側を `private` にしておけば、関所を迂回する呼び出しをコンパイラが止める。
- **採らなかった案**:
  - ブラウザで開く URL の組み立てを `APIEndpoints` に置く: `APIEndpoints` はトークンを送ってよい相手を決める型で、開く前の検査を持っていない
  - 行数の上限に合わせて `send` の `private` を外す（add-thread-latest-event §2 の判断を改めた）: 「関所は 1 か所」が規約だけで守られる状態になる
- **適用外**: 案内画面と通知の許可のバナーが開く固定の URL（gh のサイト、システム設定）は API 由来でないので、`NSWorkspace` で直接開く
- **根拠**: add-gh-account-discovery D5、add-notification-fetch D2・D8、add-system-notifications D3・D5・D7、add-thread-actions D2、add-web-notifications-link D1・D2、update-list-readability D7、add-architecture-principles D7、fix-api-client-send-privacy D1・D2・D3。`Authorization` は lint の `authorization_header_outside_client` で守る

### A7. actor や store の中の判断は、値型か純粋な関数に切り出す

- **原則**: actor や store の中の判断（隠すスレッド、取り直しの回数、待ちの合流、新着の判定、取得の記録など）は、状態を持つ struct（`ThreadDetailsCache`、`RefreshWaiters`、`ReadThrough`、`FeedRecorder`、`NotificationTracker`）か、`inout` で状態を受け取る純粋な関数（`HiddenThreads`）に切り出す。actor や store はそれを持って使う。切り出した型は、actor や store を組まずに単体テストできるようにする。
- **理由**: 判断を同期の値型にすると、actor の再入や待ちを組まずに境界の場合をテストできる。
- **採らなかった案**:
  - 判断を actor や store のメソッドに直接書く: テストに actor と偽物の外部を組む必要があり、境界の場合を突きにくい
- **適用外**: なし
- **根拠**: add-notification-fetch D5、add-system-notifications D2、add-thread-actions D4、update-reload-fetch-now D2、add-thread-latest-event §3

### A8. 失敗は enum で表し、UI は enum から決めた固定の文言だけを出す

- **原則**: 下の層は型付き throws の `Error` enum を使う（`TransportError`、`HostsFile.LoadError`）。API クライアントは throw せず、結果の enum を返す（`NotificationsFetchResult`、`ThreadActionResult`）。状態は enum（`FeedPhase`、`TokenState`、`FailureKind`）で UI に渡し、UI は enum から決めた固定の文言だけを出す。エラーの本文や gh の標準エラー出力をそのまま出さない。診断の値は状態の enum の連想値に足さず、横に並べて持つ。
- **理由**: 呼び出し側が場合を網羅でき、表示する文言にトークンや本文が混ざる経路が無くなる。
- **採らなかった案**:
  - スレッドへの操作（既読・Done）ごとに結果の enum を分ける: 呼び出し側は成否しか見ないので、分ける価値が無い
  - 診断の値を状態の enum の連想値に足す: 状態の比較と表示の分岐が、診断の値が変わるたびに変わる
- **適用外**: なし
- **根拠**: add-gh-account-discovery D6・D8、add-notification-fetch D2・D9、add-thread-actions D2、add-diagnostics D1、add-settings D8

### A9. 型・抽象・部品は、要件かテストに要るときだけ足す

- **原則**: 新しい型・抽象・ファイルは、どの要件かどのテストのために要るかを言えるときだけ足す。1 行の modifier を型で包まない。独自のデザインシステムのようなコンテナを作らない。まとめるときは、使う回数ではなく役割でまとめる（一覧の寸法を `ListLayout` にまとめる）。組にして行う操作の取り違えを防ぐ型（`ThreadChangeDispatcher`）は、テストで守る要件があるので足してよい。
- **理由**: 指摘を満たすためだけに足した部品は、次のレビューの指摘の種になる。
- **採らなかった案**:
  - 中身を受け取るコンテナ（`SectionNote` など）に色や間隔を持たせる: SwiftUI では見た目は modifier で重ね、コンテナは並べ方や意味のまとまりに使う
  - 記号の網羅のテストのために `CaseIterable` を足す: 本体の型の形をテストのために変える。`SubjectKind` は `other(String)` を持つので合成もできない
- **適用外**: なし
- **根拠**: update-list-readability D1・D6・D8、add-thread-actions D6、fix-thread-icon-column D3、update-notification-list D2。手順は `.claude/rules/review-process.md` の「指摘の直し方」

### A10. 可視性は private を既定にし、テストのために広げない

- **原則**: 宣言は `private` を既定にし、ファイル直下では `fileprivate` でなく `private` と書く（swift-format の `FileScopedDeclarationPrivacy`）。API のデコード用の型は `GitHubAPI/` の外で使わず、1 ファイルで閉じるものは `private` にする。本体から呼ばれないものは、テストのためでも公開せず、テストは公開されている経路を通す。行数の上限で型を extension に分けるときは、その型の中に閉じるメンバーに限って `private` を外してよい。関所の内側は A6 に従い、外さない。
- **理由**: 公開されている経路だけをテストすれば、実装を変えてもテストが壊れにくい。
- **採らなかった案**:
  - テストから呼ぶために内部の関数を公開する: 実装の形にテストが縛られる
- **適用外**: 非同期の処理の終わりを待つテスト用のフック（`AccountStore.waitForReload`、`SystemNotifier.waitForPendingWork`）。テストが時間で待たずに済むため
- **根拠**: add-notification-fetch D1、add-thread-latest-event §3、remove-redundant-tests

### A11. ログは Logger だけで、カテゴリはモジュール名にする

- **原則**: ログは `Logger(category:)` で出し、型ごとに `static let logger` を持つ。カテゴリは、ログを出す型のモジュールのディレクトリ名にする。`print` を使わないことと、何を伏せるかは security.md に従う。
- **理由**: Console でサブシステムとカテゴリで絞れば、どのモジュールのログかが分かる。
- **採らなかった案**:
  - 型ごとのカテゴリにする: カテゴリが増え、モジュール単位で絞りにくい
- **適用外**: なし
- **根拠**: 今のコード（`Mewbell/App/Logging.swift`）の形を add-architecture-principles で原則にした。`print` を使わないことは add-gh-account-discovery と add-thread-latest-event のセキュリティの節。lint の `no_print` で守る

### A12. テストは、削ったら見逃す不具合で残すかを決める

- **原則**: テストは Swift Testing で書く。残すかどうかは「削ったら見逃す現実的な不具合」で決め、型や言語が保証することはテストしない。security.md の性質ごとに、確かめるテストの最後の 1 本は必ず残す。書体・ホバー・読み上げは単体テストせず、手元で確かめる項目として tasks に置く。SwiftUI の実際の寸法は `NSHostingView` で測る。偽物の中で同期的に待たず、待たせるときは async で中断させる。種類の一覧の漏れは、`default` の無い `switch` でコンパイラに気づかせる。
- **理由**: 保証を足さないテストは、実行時間と実装を変えるたびの修正の手間だけを増やす。同期的な待ちは actor を塞ぎ、テストを止める。
- **採らなかった案**:
  - カバレッジや件数を目標にする: 同じ分岐を確かめ直すテストが増える
- **適用外**: なし
- **根拠**: add-project-skeleton D4、remove-redundant-tests、fix-thread-icon-column D3、update-list-readability（テストでの差し替えの節）、CLAUDE.md の「ビルドとテスト」。同期的な待ちは lint の `no_thread_sleep` で守る

### A13. 外部依存は最小限にする

- **原則**: 外部のライブラリは、標準ライブラリと Apple のフレームワークで足りないときだけ足す（YAML の解析の Yams 程度）。UI フレームワークやネットワークのライブラリは足さない。
- **理由**: 依存はサプライチェーンの攻撃面になり、gh の認証情報を扱うアプリでは影響が大きい。
- **採らなかった案**:
  - プロジェクトを XcodeGen や Tuist で生成する: 外部依存が増え、`project.xcproj` を正本としてコミットする方針と合わない
  - ネットワークのライブラリを使う: リダイレクトやキャッシュの扱いを security.md の約束どおりに確かめる場所が増える
- **適用外**: なし
- **根拠**: add-project-skeleton D1、add-gh-account-discovery D4、add-notification-fetch と add-settings のセキュリティの節。固定の方法は security.md の「依存とサプライチェーン」

### A14. 部品の間の変更は、AppDelegate がつなぐコールバックで伝える

- **原則**: 部品の間で変化を伝えるとき（設定の変更、アカウントの状態の変化、新着のスレッド）は、送る側の型が持つコールバック（`onStateChange` など）で知らせ、`AppDelegate` がそれを受ける側の操作につなぐ。部品が `withObservationTracking` でほかの部品の変化を追わない。
- **理由**: 変化の種類ごとに受ける側の行動が違い（無効化と `participating` の切り替えなど）、Observation の追跡では何が変わったかが分からない。つなぐ場所が 1 か所なら、どこからどこへ伝わるかが読める。
- **採らなかった案**:
  - `withObservationTracking` で設定や store の変化を追う: 変化の種類が分からず、受ける側が全体を見比べて判断することになる
- **適用外**: View が store を読んで描き直すのは Observation に任せる。テストで観測の粒度を確かめるときに `withObservationTracking` を使うのはよい
- **根拠**: add-notification-fetch D7、add-settings D3、update-notification-list D2

### A15. 遅れて届く結果は世代で捨て、設定を変えるときは作り直す

- **原則**: 止めたり作り直したりする非同期の処理（ポーラー、アカウントの読み直し、gh の検出）から遅れて届く結果は、世代番号で見分けて捨てる。actor が使う設定（`participating` など）は作るときに受け取り、変えるときは作り直す。
- **理由**: 走っている処理の結果が、古い設定と新しい設定のどちらのものかを区別して捨てる処理が要らなくなる。
- **採らなかった案**:
  - ポーラーに設定を切り替えるメソッドを足し、ループの中で切り替える: `Last-Modified`・隠しているスレッド・走っている取得の結果を、どちらの設定のものか区別して捨てる処理が要る
- **適用外**: なし
- **根拠**: add-notification-fetch D4、update-reload-fetch-now D2、fix-stale-notification-list D2、add-settings D5・D6、add-thread-latest-event §3

## 既知の逸脱

原則に合わない今のコード。直したら行を消す。

| 原則 | 場所 | 直す change |
| --- | --- | --- |
| A1 | `GitHubAPI/APIEndpoints.swift` が `Accounts/` の `HostKind` を使っている | fix-lower-layer-dependencies（仮） |
| A1 | `GitHubAPI/GitHubAPIClient.swift` が `Polling/` の `ThreadAction` を使っている | fix-lower-layer-dependencies（仮） |
| A1 | `GhCLI/` と `GitHubAPI/` が、`App/Logging.swift` の `Logger(category:)` を使っている | fix-lower-layer-dependencies（仮） |
| A1 | `Polling/NotificationStore.swift` が、`NSWorkspace` で URL を開く `.live` の組み立てのために AppKit を import している（lint の `ui_frameworks_outside_ui` はこのファイルを除外している。直したら除外も消す） | fix-lower-layer-dependencies（仮） |
| A1 | `ThreadReason`・`ThreadEventText` が `UI/` にあり、`Notifications/ThreadNotificationContent.swift` から使われている | fix-shared-thread-text-placement（仮） |
| A4 | 設定ウィンドウの下位の View（`DiagnosticsSettingsView`、`AccountSettingsSection` など）が store を直接受け取っている | fix-settings-view-inputs（仮） |
| A10 | `AccountPoller.pendingRefreshCount` が、テストのためだけに公開されている | fix-minor-principle-deviations（仮） |
| A11 | `App/SingleInstance.swift` のログのカテゴリが `SingleInstance` で、ディレクトリ名（`App`）でない | fix-minor-principle-deviations（仮） |
