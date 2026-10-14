# Design

## Context

- 設定ウィンドウのルートは `SettingsView`（`Mewbell/UI/SettingsView.swift`）で、`MewbellApp` の `Settings` シーンが `AppSettings`・`AccountStore`・`NotificationStore`・`LaunchAtLogin` を渡す。タブの中身は `GeneralSettingsView`・`AccountsSettingsView`（区画は `AccountSettingsSection`）・`GhSettingsView`・`DiagnosticsSettingsView`（`Mewbell/UI/DiagnosticsSettingsView.swift`）で、どれも store を受け取っている（proposal.md の Why）。
- store の変化のうち、ユーザーの操作なしに起きるのは、ポーリングのたびに変わる `NotificationStore.feeds` と、アカウントの読み直しで変わる `AccountStore.state`・`ghDetection` だけ。設定の値と `LaunchAtLogin` の状態は、ユーザーが設定ウィンドウで操作したときと、General タブを開いたときの `refresh()` でしか変わらない。
- 今のルートは `accounts.state` を読んで `AccountsSettingsView` に渡している。`feeds` を読むのは `DiagnosticsSettingsView` の `body`（`report` の計算）だけ。
- 部品の兄弟: 一覧の操作は `ThreadListActions`（`Mewbell/UI/AccountSectionView.swift`）で、クロージャのメンバーと、プレビュー用の `static var none` を持つ。パスの入力の `PathOverrideField` は、値の `path` と確定の `commit` クロージャを受け取る。
- 設定の View を描くテストは無い（`MewbellTests` に名前が出てこない）。下位の View を呼んでいるのは、`SettingsView` の `body` と同じファイルの `#Preview` だけ。

## Goals / Non-Goals

**Goals:**

- store を受け取る View を、設定ウィンドウではルートの `SettingsView` だけにする（A4）。
- ポーリングのたびに描き直す範囲を、今と同じ Diagnostics タブの中にとどめる（A3）。

**Non-Goals:**

- 設定ウィンドウの見た目・文言・振る舞いを変えること。
- `AppSettings`・`LaunchAtLogin` の API と、`MewbellApp` からの呼び出しを変えること。
- `PathOverrideField` と `DiagnosticsReportView` の形を変えること（すでに値とクロージャだけを受け取っている）。

## Decisions

### D1. 設定の操作は 1 つの `SettingsActions` にまとめ、ルートが組み立てる（A4・A9）

`Mewbell/UI/SettingsView.swift` に、`ThreadListActions` と同じ形の `SettingsActions` を置く。メンバーはクロージャで、通知の音、ログイン項目（切り替え・システム設定を開く・読み直し）、アカウントごとの設定（有効・参加しているスレッドだけ・macOS の通知。`AccountID` を受け取る）、gh の実行ファイルと設定ディレクトリの上書きの確定を持つ。プレビュー用に何もしない `static var none` を持つ。

`SettingsView` は `body` で `AppSettings` と `LaunchAtLogin` のメソッドから `SettingsActions` を組み立て、タブの中身に同じ値を渡す。操作は今と同じメソッドを呼ぶだけで、変化の伝え方（`AppSettings` のコールバックを `AppDelegate` がつなぐ。A14）は変えない。

型は `UI/` に置く。使うのは設定ウィンドウの View だけ（A1）。

採らなかった案:

- タブごとに操作の型を分ける（`AccountSettingsActions`・`GhSettingsActions` など）: 型が 3 つに増える。どの操作も同じルートが同じ store から組み立て、一覧の側も `ThreadListActions` 1 つを区画と行に渡しているので、分けて得るものが無い。
- `Binding` で渡す: 兄弟の `ThreadListActions`・`PathOverrideField` と形が揃わず、アカウントごとの `Binding` を作るクロージャも要る。

### D2. General・gh タブは、ルートが store を読んで値を渡す（A4・A3）

- `GeneralSettingsView` は、`notificationSound: Bool` と、ログイン項目の `launchAtLoginStatus: LoginItemStatus`・`launchAtLoginFailed: Bool`・`launchAtLoginIsOn: Bool` を値で受け取る。`isOn` は `LaunchAtLogin.isOn` の値をそのまま渡し、承認待ちを含めるという判断を `LaunchAtLogin` の 1 か所に残す。開いたときの読み直し（`.onAppear`）は `SettingsActions` の読み直しを呼ぶ。
- `GhSettingsView` は、`executableOverride: String?` と `configDirectoryOverride: String?` を値で受け取り、`PathOverrideField` の `commit` に `SettingsActions` の確定を渡す。パスの検査（`ExecutableValidator`・`ConfigDirectoryValidator`）は今のまま `GhSettingsView` から呼ぶ。

ルートの `body` がこれらの値を読むので、値が変わるとルートの `body` が評価し直される。変わるのはユーザーの操作と、General タブを開いたときの読み直しだけなので、描き直しの粒度は問題にならない。

`LaunchAtLogin` も A4 の store として扱う。`Settings/` に置かれ、状態を持つ `@Observable` で、`AppSettings` と同じく操作で状態を変える。この扱いは別の画面を足すときにも同じ問いが出るので、A4 の本文の store の例に `LaunchAtLogin` を足す（D5）。

採らなかった案:

- `LaunchAtLogin` を store に含めず、そのまま渡す: A4 の「store」の範囲が型ごとの判断になり、次に `@Observable` の型が増えたときに同じ問いが出る。

### D3. アカウントの区画は、設定の読み取りのクロージャと値で受け取る（A4・A3）

- `AccountsSettingsView` は、`state: DiscoveryState`（今と同じくルートが `accounts.state` を読んで渡す）と、`preferences: (AccountID) -> AccountPreferences` と `SettingsActions` を受け取る。`ForEach` の中でアカウントごとに `preferences` を呼び、値を `AccountSettingsSection` に渡す。
- `AccountSettingsSection` は、`account: Account`・`preferences: AccountPreferences`・`SettingsActions` を受け取る。トグルの `Binding` は、値から読んで、`SettingsActions` の操作で書く。

`preferences` はクロージャで渡すので、`AppSettings.accountPreferences` を読むのは `AccountsSettingsView` の `body` になる。アカウントの設定を変えたときに描き直すのは Accounts タブの中だけになる。

`accountPreferences` は 1 つの辞書のプロパティで、Observation はプロパティの単位で観測する。区画の `body` で読んでも、1 つのトグルで全区画を評価し直す（store を受け取っていた形でも同じだった）。区画ごとに観測を分けるには、アカウントごとの `@Observable` の型が要る。それを求める要件もテストも無いので足さない（A9）。

採らなかった案:

- ルートが `[AccountID: AccountPreferences]` を作って渡す: ルートが設定を読むことになり、トグルのたびにルート全体を評価し直す。既定値の補い（`AppSettings.preferences(for:)`）を View の側で繰り返すことにもなる。

### D4. Diagnostics は、報告を作るクロージャを受け取り、自分の body で呼ぶ（A4・A3）

`DiagnosticsSettingsView` は `report: () -> DiagnosticsReport` だけを受け取り、`body` で呼んだ結果を `DiagnosticsReportView` に渡す。ルートは、今 `DiagnosticsSettingsView` が持っている組み立て（`accounts.ghDetection`・`accounts.state`・`notifications.feeds`・`settings.preferences(for:)`・アプリと OS の版）をクロージャにして渡す。アプリと OS の版を 1 回だけ読む `static let` は、クロージャを作るルートの `SettingsView` に移す。

クロージャは `DiagnosticsSettingsView` の `body` の中で評価されるので、`feeds` などの読み取りは今と同じくこの View の観測に入る。ポーリングのたびに描き直すのは Diagnostics タブの中だけで、ルートと他のタブは描き直さない。`DiagnosticsSettingsView` の doc コメントに、クロージャを自分の `body` で呼ぶ理由（観測の粒度）を書く。

採らなかった案:

- ルートで `DiagnosticsReport` の値を作って渡し、`DiagnosticsSettingsView` を無くす: 設定ウィンドウを開いている間、ポーリングのたびにルートとすべてのタブの `body` を評価し直す（A3 の観測の粒度に反する）。
- 版の `static let` を `DiagnosticsSettingsView` に残してルートから参照する: 下位の View の型にルートが使う値を置くことになり、読む場所が分かれる。

### D5. プレビューと設計方針の文書を直す（A4）

- `SettingsView.swift` の `#Preview` は、値と `SettingsActions.none`（Accounts は `preferences` のクロージャ）で描く。プレビューで `AppSettings`・`LaunchAtLogin` を組まない。今のプレビューが描いている状態（承認待ちのログイン項目、無効のアカウントと参加しているスレッドだけのアカウント、使えない gh のパス）は残す。
- スキル `update-architecture-doc` の手順で、`docs/architecture.md` の「既知の逸脱」から A4 の行を消し、A4 の本文の store の例に `LaunchAtLogin` を、操作のクロージャの例に `SettingsActions` を足す。根拠に `fix-settings-view-inputs D1・D2` を足す。文書にバッククォートで書かれている名前のうち、消える行の `DiagnosticsSettingsView`・`AccountSettingsSection` はコードに残るので、`scripts/check-architecture.sh` の「コードの名前」の検査は止まらない。

## Risks / Trade-offs

- [ルートの `body` が設定の値を読むので、General と gh の操作のたび、General を開いたときの読み直しでログイン項目の状態が変わったときに、ルートの `body` を評価し直す。子に渡すクロージャ（`SettingsActions`、`report`）は比較できないので、作られているタブの `body` もすべて評価し直し、Diagnostics の報告も組み直す] → きっかけはユーザーの操作だけで回数が少なく、Form 数枚の評価し直しは設定ウィンドウでは問題にならない。ポーリングのたびの描き直しは D4 のとおり Diagnostics の中にとどまる。各タブに読み取りのクロージャを渡してルートが store を読まない形は、クロージャが 6 つ増え、プレビューも値で書けなくなるので採らない。
- [`SettingsActions` のメンバーを足し忘れたり、別のメソッドにつないだりしても、コンパイラでは気づけない] → 組み立ては `SettingsView` の 1 か所だけにする。手元で各タブの操作を確かめる（tasks の確認）。
- [`DiagnosticsSettingsView` が、クロージャを呼ぶだけの薄い View になる] → 観測の粒度を保つために要る。doc コメントに理由を書き、次のレビューで「畳める」と指摘されたときに理由が読めるようにする。

## セキュリティ

トークンの流れは変えない。トークンは `gh auth token` の標準出力から取得し、actor の中にだけ持ち、API のリクエストにだけ付け、アカウントの削除と終了時に捨てる。この change は設定ウィンドウの View の引数だけを変え、そのどこにも触れない。

`.claude/rules/security.md` の項目への対応:

- gh サブプロセス: gh のパスの上書きは、今と同じく `AppSettings` の setter で保存し、検査は `ExecutableValidator`・`ConfigDirectoryValidator` を今と同じ場所から呼ぶ。gh の実行・検出の経路は変えない。
- 表示: Diagnostics に出す内容は `DiagnosticsReport` が決めたまま変えない（トークン・API の URL・スレッドの件名を出さない）。
- トークンの扱い・ネットワーク・URL を開く処理・アプリとビルドの設定・依存には触れないので、該当しない。

actor の境界とスレッド: 変える型はすべて `UI/` の View と値型で、`@MainActor` の上で動く。`SettingsActions` のクロージャは `@MainActor` の `AppSettings`・`LaunchAtLogin` のメソッドを呼ぶ。actor・ネットワーク・gh サブプロセスには触れないので、テストでの差し替え（`HTTPTransport`・gh の実行のプロトコル）にも変わりは無い。
