# Tasks

## 1. ドキュメントの準備

- [ ] 1.1 `SETUP.md` の M4 の `add-settings` の行を、`add-settings`（Settings シーン、participating の切替、アカウントの ON/OFF と通知のオン・オフ、ログイン時起動、通知の音、gh のパスと設定ディレクトリの上書き）と `add-diagnostics`（Diagnostics の表示、操作の失敗の表示、500 件で打ち切ったことの表示）の 2 行に分ける。確認: 差分を読み、元の行の要点がどちらかの行に入っている

## 2. 設定の保存（Settings）

- [ ] 2.1 `SettingsStorage` プロトコル、`UserDefaultsStorage`、テスト用の `InMemorySettingsStorage`、`AccountPreferences` を作る（D2）。確認: テストを足して通す: (a) 何も保存されていなければすべて既定値、(b) 書いた値を別のインスタンスで読み直せる、(c) `notificationSound` に文字列が入っていると既定値（オン）になり、落ちない、(d) `accounts` の辞書のうち、`<host>/<user>` として検証を通らないキーと Bool でない値は読み飛ばす、(e) 既定値に戻したアカウントの項目は辞書から消える、(f) 空白だけの上書きのパスはキーを消す。`UserDefaultsStorage` のテストはテストごとの `UserDefaults(suiteName:)` を使い、後で消す
- [ ] 2.2 `AppSettings`（`@MainActor @Observable`）を作り、変更のメソッドで保存してから変更の種類ごとのコールバックを呼ぶ（D3）。確認: テストを足して通す: (a) 各メソッドで値が変わり保存され、対応するコールバックだけが 1 回呼ばれる、(b) 同じ値を設定し直してもコールバックは呼ばれない、(c) すべての項目を変えた後の UserDefaults のキーは D2 の 4 つだけで、値は Bool・String・`[String: [String: Bool]]` だけ（トークンや URL が入る余地が無い）

## 3. gh の上書き（GhCLI）

- [ ] 3.1 `ConfigDirectoryValidator` と `GhConfigDirectory.resolve(override:environment:homeDirectory:)` を作る（D4）。確認: テストを足して通す: (a) 上書きがあれば環境変数より優先する、(b) 相対パス・存在しないパス・ファイル・world-writable のディレクトリは通らない、(c) シンボリックリンクは実体を確かめる、(d) 上書きが無ければ今までの順（`GH_CONFIG_DIR` → `XDG_CONFIG_HOME/gh` → `~/.config/gh`）
- [ ] 3.2 `GhEnvironment.make(from:configDirectory:)` を作る。確認: テストを足して通す: (a) 上書きがあると `GH_CONFIG_DIR` がその値になり、元の `GH_CONFIG_DIR` は置き換わる、(b) 上書きがあっても `GH_TOKEN`・`GITHUB_TOKEN`・`GH_ENTERPRISE_TOKEN`・`GITHUB_ENTERPRISE_TOKEN`・`GH_HOST` は無い、(c) 上書きが無ければ今と同じ環境になる

## 4. アカウントの読み直しと無効化（Accounts）

- [ ] 4.1 `AccountDiscovering.reload` に `DiscoveryOptions`（`GhOverrides` と無効なアカウントの集合）を渡し、`AccountDiscovery` が読み直しごとに gh のパス・設定ディレクトリ・子プロセスの環境を決めるようにする。環境は確かめた gh のパスと一緒に持ち、`refreshToken` でも使う（D4）。確認: `FakeProcessRunner` でテストを足して通す: (a) gh のパスを上書きすると、そのパスで `gh --version` と `gh auth token` が実行され、ログインシェルは起動しない、(b) 上書きしたパスが使えないと `.ghNotFound` になり、`/opt/homebrew/bin/gh` は使わない、(c) 設定ディレクトリを上書きすると、そのディレクトリの `hosts.yml` を読み、`gh auth token` と `gh --version` の環境の `GH_CONFIG_DIR` がその値になる、(d) 上書きした設定ディレクトリが通らないと `.hostsFileUnreadable(path: <上書き>/hosts.yml)` になり、既定の `hosts.yml` は読まない、(e) 401 の後の `refreshToken` も上書きした環境で実行される。既存の `AccountDiscoveryTests` が通る
- [ ] 4.2 `TokenState.disabled` を足し、無効なアカウントを `gh auth token` の対象と `knownAccountIDs` から外す。`disable(_:)` と `discardAllTokens()` を足す（D5）。確認: テストを足して通す: (a) 無効な `bob` は `.disabled` になり、`bob` の `gh auth token` は実行されない、(b) `disable` の後、`CredentialStore` に `bob` のトークンが無く、`currentToken(for: bob)` と `refreshToken(for: bob)` が `nil`、(c) `bob` の `gh auth token` の応答を止めている間に `disable` すると、終わった後もトークンは保存されない、(d) `discardAllTokens` の後はどのアカウントのトークンも無い
- [ ] 4.3 `AccountStore` に `AppSettings` を渡し、`reload` で options を作って渡す。`disable(_:)`（状態をすぐ `.disabled` にしてから `discovery.disable`）、有効にし直したときの `reload()`、`resetForNewConfigDirectory()`、`apply` で今の設定に合わせて `.disabled` に置き換える処理を足す（D3、D5）。確認: `FakeDiscovery` でテストを足して通す: (a) `disable` で `onStateChange` が `bob` を `.disabled` にした状態ですぐ呼ばれ、`discovery.disable(bob)` が呼ばれる、(b) 無効にした直後に、走っていた読み直しが `bob` を `.ready` で返しても `.disabled` のまま、(c) 有効にし直すと読み直しが始まる、(d) 設定ディレクトリを変えると `.checking` を経て `discardAllTokens` の後に読み直す、(e) gh のパスを変えると `userInitiated: true` で読み直す

## 5. ポーリングと participating（Polling / GitHubAPI）

- [ ] 5.1 `AccountPoller` に `participating` を足して `fetchNotifications` に渡し、`PollerFactory` に `participating` を足す（D6）。確認: `FakeHTTPTransport` でテストを足して通す: (a) `participating: true` のポーラーの 1 ページ目の URL が `https://api.acme.ghe.com/notifications?all=false&participating=true&per_page=50`、(b) `false` なら今と同じ URL、(c) `Link` の `rel="next"` の URL はそのままたどる。既存の `PollingTests` が通る
- [ ] 5.2 `NotificationStore.sync` で `.disabled` のアカウントにポーラーを作らず、`keptIDs` と `pendingReads` から外す。`restart(_:)` を足し、`participating` の切り替えで止めて作り直す（D5、D6）。確認: 偽の `PollerFactory` と偽の `ThreadNotifying` でテストを足して通す: (a) `bob` を `.disabled` にした状態で `sync` すると、`bob` のポーラーが止まり、`feeds[bob]` が消え、`accountRemoved(bob)` が呼ばれる、(b) 読み込みが終わったときの `retainOnly` に `bob` が入らない、(c) 起動直後の通知のクリックで取っておいた `bob` の既読は、`bob` が `.disabled` で読み込みが終わると捨てられ、`perform` は呼ばれない、(d) `restart(alice)` で前のポーラーが止まり、新しいポーラーが今の `participating` の値で作られて始まり、`feeds[alice]` は `.loading`、`resetBaseline(alice)` が呼ばれる、(e) 前のポーラーから遅れて届いた更新は捨てられる、(f) `unreadCount` に `.disabled` のアカウントは入らない
- [ ] 5.3 `FakeHTTPTransport` を使った結合のテストで、作り直したポーラーの最初の取得に `If-Modified-Since` が付かず、`gh auth token`（`TokenProviding.refreshToken`）が呼ばれないことを確かめる。確認: テストが通る

## 6. macOS の通知（Notifications）

- [ ] 6.1 `ThreadNotifying` に `resetBaseline(_:)` と `notificationsDisabled(_:)` を足し、`SystemNotifier` で通知がオフのアカウントは `post` だけを捨てる（D7）。確認: `FakeUserNotificationCenter` でテストを足して通す: (a) オフの `alice` の新しいスレッドは `add` されず、オンの `dave` は `add` される、(b) オフの間に 5 件届いた後にオンに戻し、次に 1 件届くとその 1 件だけが `add` される、(c) `notificationsDisabled(alice)` で `alice` の出ている通知だけが `remove` される、(d) `resetBaseline(alice)` の後の最初の `.loaded` では `add` されず、今の一覧に無い `alice` の通知だけが `remove` される、(e) オフでも、取得で一覧から消えたスレッドの通知は `remove` される
- [ ] 6.2 `ThreadNotificationContent` に `playsSound` を足し、`LiveUserNotificationCenter.add` で `playsSound` のときだけ `sound = .default` にする。確認: テストを足して通す: 音の設定がオフのとき `SystemNotifier` が作る中身の `playsSound` が false、オンのとき true。既存の `SystemNotificationTests` が通る

## 7. ログイン時起動（Settings）

- [ ] 7.1 `LoginItemService` と `MainAppLoginItem`（`SMAppService.mainApp`）、`LaunchAtLogin` を作る（D8）。確認: fake の `LoginItemService` でテストを足して通す: (a) オンにすると `register` が呼ばれ、表示は読み直した状態になる、(b) `register` が投げると、表示は `status` に戻り、固定の失敗の文が出る（エラーの文は出ない）、(c) `requiresApproval` のときは承認が要る表示になる、(d) 読み直すと、外部で外された（`notRegistered`）ことが表示に出る

## 8. UI

- [ ] 8.1 `OpenSettingsButton`（歯車、⌘,、`.help`、アクセシビリティのラベル、`NSApp.activate()` の後に `openSettings`）を作り、ポップオーバーの見出しに置く。`MewbellApp` に `Settings` シーンを足し、`AppDelegate` で `AppSettings` と各コールバックを配線する（D3、D9）。確認: ビルドが通り、プレビューで見出しに歯車が出る。前面に出ることは 9.3 で確かめる
- [ ] 8.2 `SettingsView` の General タブ（ログイン時起動、承認が要るときの案内とボタン、通知の音）を作る。確認: プレビューに「登録なし」「登録済み」「承認が要る」「失敗」を並べて見る
- [ ] 8.3 Accounts タブを作る（アカウントの行、3 つのトグル、無効の行の 2 つを押せなくする、`participating` の説明、アカウントが無いときの文）。確認: プレビューに「3 アカウント（1 つ無効）」「未ログイン」を並べて見る。トグルで `AppSettings` のメソッドが呼ばれることは 9.3 で確かめる
- [ ] 8.4 gh タブを作る（2 つの入力欄、`onSubmit` で確定、Choose…（`NSOpenPanel`）、Reset、控えの文、使えないときの表示）。確認: プレビューに「上書きなし」「使える上書き」「使えない上書き」を並べて見る。入力の途中で読み直さないことは 9.3 で確かめる
- [ ] 8.5 ポップオーバーで無効のアカウントの区画を出さない、すべて無効のときの表示（文と `OpenSettingsButton`）、`participating` の印を見出しに出す。`GuidanceView` に上書きの有無を渡し、gh のパス・設定ディレクトリを上書きしているときの案内と `OpenSettingsButton` を出す（D9）。確認: プレビューを足して見る（すべて無効、上書きした gh が使えない、上書きした設定ディレクトリが読めない）。`NotificationGrouping` などの表示用のロジックを変えたらユニットテストも足す
- [ ] 8.6 `MarkAllReadButton` に `participatingOnly` を足し、確認の表示を `Mark all as read?` に、`.help` とアクセシビリティのラベルを一覧に出ていない未読も既読になることにする（D10）。確認: プレビューに `participatingOnly` の「確認中」を足して見る。確認を元に戻す条件が変わらないことは既存のテストで確かめる
- [ ] 8.7 README の現状の説明を更新する（設定ウィンドウの項目、ログイン時起動は `/Applications` に置いたビルドで使うこと、gh の設定ディレクトリの上書き）。確認: 差分を読み、CLAUDE.md の約束と食い違いが無い

## 9. 最終確認

- [ ] 9.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [ ] 9.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 9.3 手元で起動して確認した: (a) ほかのアプリが前面にあるときに歯車と ⌘, で設定ウィンドウが前面に開き、ポップオーバーが閉じ、Dock にアイコンが出ない。開いたまま押しても 2 つ目は開かない、(b) アカウントを無効にすると、ポップオーバー・バッジ・通知センターからすぐ消え、`log show` でそのアカウントの `gh auth token` と `GET /notifications` がその後に出ない。有効に戻すと取得が始まる、(c) 「参加しているスレッドだけにする」を切り替えると、一覧が取り直され、macOS の通知は出ず、見出しに印が出る。その状態の「すべて既読」が `Mark all as read?` になる、(d) 通知をオフにしたアカウントの新着は通知されず、一覧には入る、(e) 音をオフにすると新着が音なしで出る、(f) ログイン時に起動するをオン・オフでき、システム設定のログイン項目と表示が合う、(g) gh のパスに使えないパスを入れると案内が変わり、Reset で戻る。入力の途中では読み直さない、(h) gh の設定ディレクトリを上書きするとそのディレクトリのアカウントが出る、(i) 再起動しても設定が残り、`defaults read com.codingfeline.mewbell` にトークン・API の URL・gh の出力が無い

## 10. 別コンテキストでのレビュー

- [ ] 10.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 10.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 10.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認を PR 本文に書いた
