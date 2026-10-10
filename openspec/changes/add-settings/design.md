# Design

## Context

今の構成のうち、この change に関係するところ（動機は proposal.md の Why、満たすべき振る舞いは `specs/` の各 delta）:

- `AppDelegate` が `AccountStore`、`NotificationStore`、`NotificationPermission`、`NotificationClickHandler` を作り、`AccountStore.onStateChange` から `NotificationStore.sync(with:)` を呼ぶ。`MewbellApp` は `MenuBarExtra`（`.window`）だけで、`Settings` シーンは無い
- `AccountDiscovery`（actor）は `GhLocator`、子プロセスの `environment`、`configDirectory` を `init` で固定している。`overridePath` は `@Sendable () -> String?` の口だけあり、常に `nil`
- `AccountDiscovery.knownAccountIDs` に無いアカウントのトークンは `CredentialStore` に保存しない（取得の途中でアカウントが消えたとき、捨てたトークンを書き戻さないため）。`refreshToken(for:)` も `knownAccountIDs` に無ければ `nil` を返す
- `DiscoveryState.accounts([AccountStatus])` の `TokenState` は `.fetching` / `.ready` / `.unavailable`
- `NotificationStore.sync(with:)` は、一覧に無いアカウントのポーラーを止めて `feeds` を消し、`notifier.accountRemoved` と `notifier.retainOnly` で通知を取り下げる。ポーラーには世代（`generation`）を振り、止めたポーラーから遅れて届いた更新は捨てる
- `AccountPoller` は `participating` を持たない（`GitHubAPIClient.fetchNotifications` の引数の既定値 `false` のまま）。`Last-Modified`、隠しているスレッド（`hidden`、`readThroughs`）はポーラーの中にだけある
- `SystemNotifier` は `NotificationTracker` で「見たスレッド」を覚え、基準（`baseline`）が無いアカウントの最初の `.loaded` では通知せず、今の一覧に無い通知だけを取り下げる。`LiveUserNotificationCenter.add` は常に `sound = .default`
- `GuidanceView(state:)` は `DiscoveryState` だけを見て案内を出す
- アプリは `LSUIElement`（Dock に出ない）。新しい Swift ファイルはフォルダーに置けばターゲットに入る

## Goals / Non-Goals

**Goals:**

- 設定の読み書きを `@MainActor` の 1 つの型に閉じ込め、actor（`AccountDiscovery`、`AccountPoller`）には値のスナップショットだけを渡す
- アカウントの無効化・`participating` の切り替え・設定ディレクトリの変更を、既存の「ポーラーを止める・作り直す」「基準を取り直す」の経路に乗せ、新しい停止の経路を作らない
- 設定ウィンドウ・ログイン項目・UserDefaults をプロトコルで差し替え、ユニットテストで振る舞いを確かめられるようにする

**Non-Goals:**

- Diagnostics の表示、操作の失敗の表示、500 件で打ち切ったことの表示（`add-diagnostics`）
- ポーリング間隔の設定。API の `X-Poll-Interval` に従う方針を変えない
- 設定の書き出し・読み込み、iCloud での同期
- 通知の音の種類の選択（オン・オフだけ）
- アカウントの並び順の変更

## Decisions

### D1. モジュールと型の分担

| 置き場所 | 型 | 役割 |
| --- | --- | --- |
| `Settings/` | `AppSettings`（`@MainActor @Observable`） | 設定の唯一の持ち主。読み書きは `SettingsStorage` を通す。変更を `AccountStore`・`NotificationStore`・`SystemNotifier` に伝える（D3） |
| `Settings/` | `SettingsStorage`（プロトコル）、`UserDefaultsStorage`、`AccountPreferences` | UserDefaults の読み書き。テストはメモリ上の実装に替える（D2） |
| `Settings/` | `LoginItemService`（プロトコル）、`MainAppLoginItem`、`LaunchAtLogin`（`@MainActor @Observable`） | `SMAppService.mainApp` の登録・解除・状態の読み直し（D8） |
| `GhCLI/` | `GhOverrides`、`ConfigDirectoryValidator`、`GhEnvironment.make(from:configDirectory:)` | 上書きの値の受け渡しと検証、子プロセスの環境（D4） |
| `Accounts/` | `TokenState.disabled`、`AccountDiscovering.reload(userInitiated:options:update:)`、`disable(_:)`、`discardAllTokens()` | 無効なアカウントを飛ばす、すぐに捨てる（D5） |
| `Polling/` | `NotificationStore.sync(with:preferences:)`、`PollerFactory` に `participating` を足す | 無効なアカウントのポーラーを止める、`participating` の切り替えで作り直す（D6） |
| `Notifications/` | `ThreadNotifying.resetBaseline(_:)`、`notificationsDisabled(_:)`、`ThreadNotificationContent.playsSound` | 通知のオフ・音・基準の取り直し（D7） |
| `UI/` | `SettingsView`（General / Accounts / gh）、`OpenSettingsButton`、`GuidanceView` の引数、`MarkAllReadButton` の引数 | 設定ウィンドウ、歯車のボタン、案内、すべて既読の表示（D9、D10） |
| `App/` | `MewbellApp` に `Settings` シーン、`AppDelegate` の配線 | — |

### D2. 保存の形

UserDefaults（`UserDefaults.standard`、ドメインは Bundle ID）に次のキーだけを書く。

| キー | 型 | 中身 |
| --- | --- | --- |
| `notificationSound` | Bool | 通知の音 |
| `ghExecutableOverride` | String | gh のパスの上書き（無ければキーを消す） |
| `ghConfigDirectoryOverride` | String | gh の設定ディレクトリの上書き（無ければキーを消す） |
| `accounts` | `[String: [String: Bool]]` | `<host>/<user>` → `enabled` / `participatingOnly` / `notifications` |

- 読むときは型を確かめ、違えば既定値にする（`object(forKey:) as? Bool` など。`bool(forKey:)` は文字列の `"YES"` も真にするので使わない）。アカウントの辞書は、キーが `AccountID` として読めて（ホスト名とユーザー名の検証を通る）値が Bool のものだけを使う
- 既定値と同じ値になったアカウントの項目は辞書から消す（UserDefaults に既定値を書き溜めない）。gh からログアウトしたアカウントの項目は消さない（spec「設定項目と既定値」）
- 上書きのパスは、前後の空白を除いて空なら「上書きなし」としてキーを消す。`~` は展開しない（gh の検証が絶対パスを求めるので、入力欄の控えの文で絶対パスを促す）
- 代替案: `@AppStorage` を View で直接使う → `AccountStore` や actor へ変更を伝える経路が View に散らばり、テストもしにくい。`Codable` の 1 つの JSON を書く → 型が壊れたときに全項目が既定値に戻る。項目ごとに分ける方が壊れたときの影響が小さい

### D3. 変更の伝え方とスレッド

`AppSettings` は `@MainActor` で、変更のメソッド（`setEnabled(_:for:)`、`setParticipatingOnly(_:for:)`、`setNotifies(_:for:)`、`setNotificationSound(_:)`、`setGhExecutableOverride(_:)`、`setGhConfigDirectoryOverride(_:)`）で保存してから、`AppDelegate` が設定したコールバックを呼ぶ。Observation の追跡（`withObservationTracking`）では変更の種類が分からず、無効化と `participating` で取る行動が違うので、明示的なコールバックにする。

| 変更 | 呼ぶ先（すべてメインスレッド） |
| --- | --- |
| 無効にする | `AccountStore.disable(id)`: 状態の `TokenState` をすぐ `.disabled` にして `onStateChange` を呼ぶ（→ `NotificationStore` がポーラーを止める）。続けて `discovery.disable(id)` でトークンを捨てる |
| 有効にする | `AccountStore.reload()`: 読み直しで `gh auth token` を実行する（D5） |
| `participating` | `NotificationStore.restart(id)`（D6） |
| 通知のオン・オフ | オフなら `SystemNotifier.notificationsDisabled(id)`（D7）。オンは何もしない（次の取得から出る） |
| 音 | 何もしない（`SystemNotifier` が通知を出すたびに読む） |
| gh のパス | `AccountStore.reload(userInitiated: true)` |
| 設定ディレクトリ | `AccountStore.resetForNewConfigDirectory()`: 状態を `.checking` にして `onStateChange`（→ すべてのポーラーを止める）、`discovery.discardAllTokens()` の後に `reload(userInitiated: true)` |

`AccountStore` が `discovery.reload` を呼ぶときは、その時点の `AppSettings` から `DiscoveryOptions`（`GhOverrides` と無効なアカウントの集合、どちらも `Sendable` な値）を作って渡す。actor の中から UserDefaults や `AppSettings` を読まない。`NotificationStore` と `SystemNotifier` は同じ `@MainActor` なので、`AppSettings` の参照を持って直接読む（ポーラーを作るときの `participating`、通知を出すときのオン・オフと音）。

- 代替案: `AccountDiscovery` に `@Sendable () -> DiscoveryOptions` のクロージャーを渡し、actor の中で読む → `AppSettings` が `@MainActor` なので、クロージャーの中で `MainActor.assumeIsolated` などが要る。読み直しの開始時点の値を引数で渡す方が、どの値で読んだかがはっきりする

### D4. gh の上書き

- `GhOverrides { executablePath: String?, configDirectory: String? }` を読み直しごとに受け取る。`GhLocator.locate(overridePath:retryLoginShell:)` は今のまま使う（上書きがあればそれだけを `ExecutableValidator` で確かめ、ログインシェルは使わない。spec「gh 実行ファイルの検出」）
- 上書きした設定ディレクトリは `ConfigDirectoryValidator.validate(_:)` で、絶対パス・`realpath` で解決した先がディレクトリ・所有者が現在のユーザー・world-writable でない、を確かめ、解決した実体のパスを返す。`hosts.yml` を読むのも `GH_CONFIG_DIR` に渡すのもこの実体のパスにする（確かめた後にシンボリックリンクを差し替えられても、確かめたディレクトリを使う）。通らなければ `.hostsFileUnreadable(path: <上書き>/hosts.yml)` を返し、ほかの候補に移らない
- 子プロセスの環境は `GhEnvironment.make(from: base, configDirectory: URL?)`。取り除くキーを除いた後に、上書きがあれば `GH_CONFIG_DIR` を設定する（プロセスの環境にあった `GH_CONFIG_DIR` を置き換える）。`AccountDiscovery` は読み直しの中で作った環境を、確かめた gh のパス（`verifiedGhPath`）と一緒に持ち、401 の後の `refreshToken` でも同じ環境を使う。設定ディレクトリが前回と違えば `verifiedGhPath` を消して `gh --version` からやり直す
- `GhLocator` のログインシェルの検索に渡す環境は今のまま（`GH_CONFIG_DIR` は `command -v gh` に関係しない）
- 代替案: 上書きした設定ディレクトリが使えないとき、既定の候補に戻る → 別の gh のログインを黙って使うことになる。gh のパスと同じく、ユーザーが指定したものだけを使う

### D5. 無効なアカウント

- `discover` は `hosts.yml` のアカウントのうち、`DiscoveryOptions.disabled` に入るものを `TokenState.disabled` にし、`gh auth token` の対象から外す。`knownAccountIDs` は有効なアカウントだけにする。`credentials.retainOnly(knownAccountIDs)` で、無効なアカウントのトークンは読み直しのたびにも捨てる
- `disable(id)` は `knownAccountIDs` から外して `credentials.remove(id)` を呼ぶ。走っている `gh auth token` があっても、終わったときに `knownAccountIDs` に無いので保存されない（今の仕組みのまま）。走っている取得そのものは止めない（合流した呼び出し元がいれば結果を奪うため。5 秒のタイムアウトで終わる）
- 有効にし直したときは `reload()` で、そのアカウントは `held` に無いので `.fetching` を経て取得される
- `AccountStore.disable` が状態を先に書き換えるのは、`reload` を待たずにポップオーバーとバッジから外すため。その直後に走っていた読み直しが古い options で終わって `.ready` を返すことがあるので、`AccountStore.apply` で、今の `AppSettings` で無効なアカウントを `.disabled` に置き換えてから反映する
- 通知のクリックで既読を取っておく `pendingReads` は、`.disabled` のアカウントの分も捨てる（spec notifications「通知のクリック」）
- `AccountDiscovery` は無効なアカウントの集合（`disabledIDs`）を自分でも持つ。読み直しの始めに options から受け取り、`disable` でも足す。`knownAccountIDs` は `gh --version` などの await の後に `disabledIDs` から作るので、古い設定で始めた読み直しが、途中で無効にしたアカウントを戻してトークンを取り直すことはない
- `AccountStore` は送った `disable` を `pendingDisable` に積み、後から始める読み直しはそれを待つ。読み直しに渡す options は、待ち終えてから `AppSettings` を読んで作る（待っている間に無効にしたアカウントを含めるため）。無効にしてすぐ有効に戻したとき、遅れて届いた `disable` が、有効に戻した後の読み直しで取ったトークンを消さないようにするため
- `discardAllTokens` は走っている `gh auth token`（`inFlightTokenFetches`）を外し、`tokenEpoch` を進める。それより前に始めた取得の結果は保存せず、後の読み直しも合流しない（前の設定ディレクトリの取得なので）

### D6. ポーラーの停止と作り直し

- `NotificationStore.sync(with:)` は、`.ready` かつ `.disabled` でないアカウントだけにポーラーを作る。`keptIDs`（ポーラーと `feeds` を残すアカウント）から `.disabled` を除く。これで、無効にしたアカウントは「一覧から消えた」と同じ経路で止まり、`notifier.accountRemoved` で通知が取り下がる。読み込みが終わったときの `notifier.retainOnly(keptIDs)` で、前回の実行で出した無効なアカウントの通知も消える
- `PollerFactory` に `participating: Bool` を足し、ポーラーを作るときに `AppSettings` から読む。`AccountPoller` は `participating` を `let` で持ち、すべての取得で `fetchNotifications(..., participating:)` に渡す
- `restart(id)` は、ポーラーを止めて取り除き、`feeds[id] = .loading`、`notifier.resetBaseline(id)` の後に、同じアカウントに新しい世代のポーラーを作って `start()` する。新しいポーラーは `Last-Modified` も `hidden` も持たないので、最初の取得は条件なしになる。トークンは `CredentialStore` にあるので gh は呼ばない
- 作り直しで `hidden` と `readThroughs` が消えるので、直前に既読にしたスレッドが、GitHub の反映が遅れたときに一度だけ一覧に戻ることがある（Risks）
- 「スコープ不足」「認証エラー」で止まっているアカウントは、`AccountPoller(initialPhase:)` で止まった状態のまま作り直し、始めない。再読み込みの `refreshNow` が、止まっているポーラーと同じく `resume()` で再開する
- レート制限で待っているアカウントは、`initialPhase` に `.retrying(rateLimited: true)` を渡して作り直す。新しいポーラーは最初の取得の前に、その再試行の時刻まで待つ（CLAUDE.md の「レート制限で待っている間は早めない」）
- 代替案: `AccountPoller` に `setParticipating(_:)` を足してループの中で切り替える → `Last-Modified`・隠しているスレッド・走っている取得の結果を、どちらの一覧のものか区別して捨てる処理が要る。作り直しなら、既存の世代の仕組みで遅れて届いた結果も捨てられる

### D7. 通知のオフと音

- `ThreadNotifying` に 2 つ足す。`resetBaseline(_ account:)` は `tracker.reset` だけを行い、出ている通知は取り下げない（次の `.loaded` の基準の取り直しで、今の一覧に無いものだけが取り下がる。spec「通知の取り下げ」）。`notificationsDisabled(_ account:)` はそのアカウントの出ている通知をすべて取り下げ、`tracker` は消さない
- `SystemNotifier.feedChanged` の `.loaded` では、今までどおり `tracker.update` で見たスレッドを覚え、取り下げも行う。`AppSettings` でそのアカウントの通知がオフなら、`post` だけを捨てる。オンに戻したときに、オフの間に届いたスレッドは `tracker` が覚えているので通知されない
- `ThreadNotificationContent` に `playsSound: Bool` を足し、`SystemNotifier` が作るときに `AppSettings` から読む。`LiveUserNotificationCenter.add` は `playsSound` のときだけ `sound = .default` にする。前面にいるときの表示（`NotificationClickHandler` の `[.banner, .list, .sound]`）は今のまま（`sound` が無い通知は鳴らない）

### D8. ログイン時起動

- `LoginItemService` は `status`（`enabled` / `requiresApproval` / `notRegistered` / `notFound`）、`register()`、`unregister()`、`openSystemSettings()` を持つ。本物は `SMAppService.mainApp` と `SMAppService.openSystemSettingsLoginItems()` を呼ぶ
- `LaunchAtLogin` は表示用の状態を持ち、設定ウィンドウの表示時（`onAppear`）と切り替えた後に `status` を読み直す。`register` / `unregister` が投げたら状態を読み直して戻し、「Could not change the login item.」のような固定の文を出す（エラーの文は出さずにログに `.private` で残す）
- 状態は UserDefaults に持たない（spec「設定項目と既定値」）。システム設定で外されたときにずれないように、常にシステムから読む
- 代替案: `LSSharedFileList` やログイン項目用のヘルパーアプリ → 前者は廃止済み、後者は macOS 13 以降の `SMAppService.mainApp` で不要

### D9. 設定ウィンドウ

- `MewbellApp` に `Settings { SettingsView(...) }` を足す。`SettingsView` は `TabView` で General / Accounts / gh の 3 タブ。UI の文言は既存に合わせて英語にする
- ポップオーバーの `OpenSettingsButton`（歯車、`.keyboardShortcut(",")`、`.help("Settings")`）は `@Environment(\.openSettings)` を呼ぶ前に `NSApp.activate()` で Mewbell を前面にする。`LSUIElement` のアプリは前面にしないと設定ウィンドウがほかのアプリの後ろに開く。ポップオーバーは `MenuBarExtra` の `.window` がキーでなくなると閉じるので、閉じる処理は足さない（手動確認で確かめる。閉じなければ `dismiss` を呼ぶ）
- Accounts タブは `AccountStore.state` の `.accounts` を並べ、行ごとに 3 つの `Toggle` を出す。無効の行では 2 つを `.disabled(true)` にする。トグルの値は `AppSettings` から読み、変更はメソッドで書く
- gh タブは、入力欄（`TextField` の `onSubmit` で確定）、`NSOpenPanel` を開く「Choose…」、上書きを消す「Reset」。使えない表示は、確定した値を `ExecutableValidator` / `ConfigDirectoryValidator` に通した結果で出す（gh は実行しない）
- すべてのアカウントが無効のときのポップオーバーの表示と、上書きが使えないときの `GuidanceView` の案内にも `OpenSettingsButton` を置く。`GuidanceView` には `ghExecutableOverridden` と `ghConfigDirectoryOverridden` の Bool を渡す（パスの値は渡さない。`hostsFileUnreadable` は状態がパスを持っている）

### D10. すべて既読の表示と見出しの印

- `MarkAllReadButton` に `participatingOnly: Bool` を足す。真なら確認の表示を `Mark all as read?` にし、`.help` とアクセシビリティのラベルを「Also marks notifications you are not participating in as read.」にする。確認を元に戻す条件（件数・最新のスレッド・5 秒・閉じる）は変えない
- アカウントの見出しには、`participatingOnly` のとき「Participating」の小さな印を出す

### D11. テストでの差し替え

- 設定: `SettingsStorage` のメモリ上の実装（`InMemorySettingsStorage`）。`UserDefaultsStorage` は、テストごとに `UserDefaults(suiteName:)` を作って壊れた値の読み取りと書いたキーの一覧を確かめる
- gh: 既存の `FakeProcessRunner` で、無効なアカウントに `gh auth token` を実行しないこと、上書きした設定ディレクトリのときに `GH_CONFIG_DIR` が子プロセスの環境に入り、`GH_TOKEN` などが無いことを確かめる。`ConfigDirectoryValidator` は一時ディレクトリにパーミッションを変えたディレクトリを作って確かめる
- ポーリング: 既存の `FakeHTTPTransport` で、`participating=true` のクエリ、作り直した後の最初の取得に `If-Modified-Since` が無いこと、無効にした後に `GET` が送られないことを確かめる
- 通知: 既存の `FakeUserNotificationCenter` で、通知のオフ・オンに戻したとき・音・基準の取り直しを確かめる
- ログイン項目: `LoginItemService` の fake で、失敗したときに表示が戻ることを確かめる。本物の登録は手動確認にする

## セキュリティ

### トークンの流れ

- 取得: 今までどおり `gh auth token --hostname <host> --user <user>` の標準出力からだけ。無効なアカウントには実行しない。設定ディレクトリを上書きしたときは、子プロセスに `GH_CONFIG_DIR` を渡す（Mewbell が読んだ `hosts.yml` と gh のトークンの出所をそろえる）
- 保持: `CredentialStore`（actor）のメモリにだけ。設定（UserDefaults）にはトークンを書かない
- 送り先: 変えない。そのアカウントの API ベース URL だけ。`participating` はクエリの値が変わるだけ
- 破棄: 今の場面（一覧から消えた、「アカウントあり」以外、401、終了）に、無効にしたとき（`disable` ですぐ）と、設定ディレクトリの上書きを変えたとき（`discardAllTokens` ですべて）を足す。読み直しの `retainOnly` でも無効なアカウントのトークンを捨てる

### `.claude/rules/security.md` への対応

| 項目 | 対応 |
| --- | --- |
| トークンは `gh auth token` の標準出力からだけ。`hosts.yml` の `oauth_token` を読まない | 変えない。上書きした設定ディレクトリの `hosts.yml` も、同じ `HostsFile` で読む |
| メモリ上の actor にだけ持つ。ディスク・UserDefaults・Keychain に書かない | 対応。UserDefaults に書くキーは D2 の 4 つだけで、テストで書いたキーの一覧と値の型を確かめる |
| トークン専用の型、伏せ字 | 変えない |
| ログは `Logger`、可変値は `.private` | 対応。設定の変更（どのアカウントを無効にしたか、上書きのパス）もログに出すときは `.private` |
| gh の標準エラー出力・API のエラーボディをそのまま出さない | 対応。ログイン項目の失敗も固定の文を出す |
| テストに本物の形式のトークンを書かない | 対応。`test-token` を使う |
| 削除・無効化・終了でトークンを破棄 | 対応（D5。M1 から持ち越していた無効化をここで満たす） |
| `Process` に絶対パスと引数配列、シェルを経由しない | 変えない |
| gh のパスの検証（通常ファイル、実行可能、他人が書けない） | 対応。上書きしたパスも `ExecutableValidator` を通す。通らなければ既定の候補に戻らない |
| 子プロセスから `GH_TOKEN` などを除く | 対応。`GH_CONFIG_DIR` を足すのは除いた後で、除くキーの一覧は変えない。テストで確かめる |
| `hosts.yml` のホスト名・ユーザー名の検証 | 変えない。設定の辞書のキー（`<host>/<user>`）も同じ検証を通ったものだけを使う |
| サブプロセスのタイムアウトと出力の上限 | 変えない |
| トークンを送る先の検査、HTTPS、リダイレクトの拒否、キャッシュなし | 変えない（`GitHubAPIClient.send` の 1 か所のまま） |
| ブラウザで開く URL の検査 | GitHub の URL を開く処理は変えない。新しく開くのはシステム設定のログイン項目だけで、URL ではなく `SMAppService` の API で開く |
| Hardened Runtime、緩める entitlement を付けない | 変えない。`SMAppService.mainApp` に entitlement は要らない |
| 通知の本文にトークンや API URL を入れない | 変えない。音の有無を足すだけ |
| 外部依存は最小限 | `ServiceManagement`（OS のフレームワーク）だけ。パッケージは足さない |

### 設定の値の信頼

UserDefaults は同じユーザーのほかのプロセスから書き換えられる（`defaults write`）。gh のパスの上書きを書き換えられると、Mewbell がそのファイルを gh として実行する。ただし、同じユーザーの権限があれば `~/.config/gh` や `PATH` の gh も書き換えられるので、新しく攻撃できることは増えない。それでも、上書きしたパスにも既存の検証（所有者が自分か root、group と world が書けない、置いたディレクトリが world-writable でない）を掛け、ほかのユーザーが置いたファイルは実行しない。設定ディレクトリの上書きにも、所有者が自分で world-writable でないことを求める。

## Risks / Trade-offs

- [`participating` を切り替えるとポーラーを作り直すので、直前に既読・Done にしたスレッドが GitHub の反映の遅れで一度だけ一覧に戻ることがある] → 切り替えはまれな操作なので受け入れる。次の条件なしの取得（最大 5 分）で消える
- [ローカルビルド（`build/Debug/Mewbell.app`）をログイン項目に登録すると、ビルドし直しや場所の移動で登録が外れたり、古い場所を指したりする] → README に、ログイン時起動は `/Applications` に置いたビルドで使うよう書く。状態は常にシステムから読むので、外れたら設定ウィンドウでオフと表示される
- [ad-hoc 署名のビルドでは、ログイン項目の承認（`requiresApproval`）が求められることがある] → 承認が要る表示と、システム設定を開くボタンを出す
- [`LSUIElement` のアプリで、設定ウィンドウがほかのアプリの後ろに開く、またはポップオーバーが閉じない] → `NSApp.activate()` を先に呼ぶ。手動確認の項目に入れる
- [無効にした直後に、走っていた読み直しが古い options で `.ready` を返す] → `AccountStore.apply` で今の設定に合わせて `.disabled` に置き換える（D5）
- [設定ディレクトリを変えると、すべてのアカウントの一覧と通知の基準がいったん消える] → 変更はまれで、ユーザーが明示的に行うので受け入れる。最初の取得では通知しない（基準の取り直し）ので、通知が一斉に出ることはない
- [`participating=true` の「すべて既読」は、一覧に出ていない未読も既読にする] → 確認の表示を `Mark all as read?` にし、ツールチップで伝える（D10。ユーザーと決めた方針）

## Migration Plan

- 既存のユーザーは UserDefaults に何も無いので、すべて既定値（今までと同じ振る舞い）で始まる。移行の処理は要らない
- 戻すときは、この change の前のビルドに戻せばよい。残った UserDefaults のキーは前のビルドでは読まれない。ログイン項目に登録したままなら、システム設定で外す
