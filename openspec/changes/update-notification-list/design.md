# Design

## Context

- 一覧は `NotificationListView` → `AccountSectionView`（見出し、取得の状態、操作の失敗、リポジトリのグループ）→ `ThreadRow` の順に組み立てている。どれも `NotificationStore.feeds` を読むだけで、自分の状態を持たない
- ポップオーバーは `MenuBarExtra`（`.window` スタイル）の中身で、開くたびに View が作り直されることがある。View の `@State` に置いた値が閉じた後も残るとは限らない
- main では、新着の判定は `SystemNotifier` が持つ `NotificationTracker`（`Mewbell/Notifications/` にある）が行っている。notifications「新着の通知」で通知の対象にならない取得（アカウントの最初の成功した取得）では何も出さず、その後は初めて見たスレッドか `updated_at` が進んだスレッドを `Changes.post` に入れる。「macOS の通知を出す」がオフでも `tracker.update` は呼んでいて、通知を出すかどうかだけを `notifies` で決めている。この change で、この判定を `NotificationStore` に移し、`NotificationTracker` を `Mewbell/Polling/NotificationTracker.swift` に移す（D2）
- ブラウザで開く URL は `ThreadWebURL.make` が `subject.url` の検証済みのパスから組み立てている（`suffix(for:endpoints:)`）。Issue と Pull request の番号はこの中で `ThreadID.isValid` を通った値として既に取り出している

## Goals / Non-Goals

**Goals:**

- 折りたたみの状態を、起動している間だけ、ポップオーバーを閉じても残るところに置く
- 「新着」の判定を macOS の通知と同じにし、判定のコードを 2 つに分けない
- 表示する番号と、クリックで開く URL の番号が必ず一致するようにする

**Non-Goals:**

- 折りたたみの状態の永続化（ユーザーの判断で、起動中だけにする）
- すべて開く・すべて折りたたむの一括操作、キーボードでの開閉のショートカット
- Commit の SHA や Discussion の番号の表示（Discussion は `subject.url` が無いことが多く、番号を確実に読めない）

## Decisions

### D1. 折りたたみの状態は `AppDelegate` が持つ `ListExpansion` に置き、アカウントごとの `@Observable` な `AccountExpansion` に分ける

`Mewbell/UI/ListExpansion.swift` に `@MainActor final class ListExpansion`（`@Observable` ではない）と `@MainActor @Observable final class AccountExpansion` を作る。

- `AccountExpansion`: 1 つのアカウントの状態だけを持つ。そのアカウントが畳まれているかと、畳んだリポジトリの集合。リポジトリの操作は `isRepositoryCollapsed(_:)` と `toggleRepository(_:)`
- `ListExpansion`: アカウントから `AccountExpansion` を引く辞書を持つ。操作は `state(for:)`（無ければ作る）、`expand(account:newThreads:)`（新着のスレッドからリポジトリを取り出して開く。`expand(account:repositories:)` は外から使わない）、`retain(_ accounts: Set<AccountID>)`。`ListExpansion` 自身は観測されない。`RepositoryKey` は持たない（アカウントごとに分けたので、リポジトリはアカウントの `AccountExpansion` の中でリポジトリ名だけで引ける）

`AppDelegate` が `NotificationStore` などと同じように `ListExpansion` を 1 つ作って持ち、`MewbellApp` から `MenuBarContentView` → `NotificationListView` → `AccountSectionView` に渡す。各区画は `state(for:)` で自分のアカウントの `AccountExpansion` だけを読む。

- 観測の粒度を、それを読む View の粒度に合わせる理由: 区画は自分のアカウントの `AccountExpansion` だけを読むので、そのアカウントの開閉や新着の自動展開で描き直されるのはその区画だけになる。ほかのアカウントの区画は描き直されない
- 代替案: 1 つの `@Observable` が全アカウントの Set を持つ（前の形）。すべての区画が同じ Set を読むので、1 か所の開閉で全区画が描き直される
- 代替案: View の `@State`。ポップオーバーを作り直すと消えることがあり、「閉じても残る」を満たせない
- 代替案: `@SceneStorage` / `@AppStorage`。ディスクに残り、「起動中だけ」に反する
- すべて `@MainActor` の上で動く。ネットワークやポーラーの actor には触れない

### D2. 新着は `NotificationStore` が判定して配る

新着の判定（`NotificationTracker`）を `SystemNotifier` から `NotificationStore` に移す。`NotificationStore` は内部の型 `ThreadChangeDispatcher`（`Mewbell/Polling/ThreadChangeDispatcher.swift`）を 1 つ持ち、`NotificationTracker`、notifier、`onNewThreads` はこの中に置く。`ThreadChangeDispatcher` は `feedChanged(for:from:to:)`・`threadRemoved(_:for:)`・`accountRemoved(_:)`・`restarted(_:)`・`retainOnly(_:)`・`stopAll()` を持ち、それぞれで tracker の操作と通知の取り下げの「どちらを行うか」をこの型の中で決める。`NotificationStore` は取得の結果やスレッド・アカウントの増減を受けるたびにこれらを呼び、tracker の結果を 2 つの先に配る。

- 組にして行う: `feedChanged`（判定と、新着の通知・取り下げ）、`threadRemoved`（tracker から外し、そのスレッドの通知を取り下げる）、`accountRemoved`（tracker を捨て、`retractAll(for:)` でそのアカウントの通知を取り下げる）
- tracker だけ: `restarted`（出ている通知は、次の最初の成功した取得で `baselineSet(for:keeping:)` が整理する）、`stopAll`（終了のとき）
- 通知だけ: `retainOnly`（消えたアカウントの tracker は、その前に `accountRemoved` で捨てている）
- `ThreadChangeDispatcher` にまとめる理由: tracker の操作と通知の取り下げのどちらを行うかを呼び出し側（`NotificationStore`）で決めていると、新しい経路で片方だけ呼んで、tracker と出ている通知が食い違う。どちらを行うかを 1 つの型の中で決め、呼び出し側は起きたことを知らせるだけにする
- macOS の通知: `ThreadNotifying` は `baselineSet(for:keeping:)`、`threadsChanged(for:posted:retracted:)`、`threadRemoved(_:for:)`、`retractAll(for:)`、`retainOnly(_:)` にする。`retractAll(for:)` は、今までの `accountRemoved` と `notificationsDisabled` をまとめたもの。`ThreadNotifying` から `feedChanged(for:from:to:)` と `resetBaseline(_:)` は無くす。`SystemNotifier` は判定を持たず、通知センターの操作だけをする（「macOS の通知を出す」がオフのアカウントの `posted` を出さないのは、今までどおり `SystemNotifier` が `notifies` で決める）
- 一覧の自動展開: `NotificationStore` の init の引数 `onNewThreads`（`ThreadChangeDispatcher` に渡して持たせる）に、新着のスレッドを、「macOS の通知を出す」で絞る前の値で渡す。`AppDelegate` はこれを `ListExpansion.expand(account:newThreads:)` につなぐだけにする。`expand` は、新着のスレッドからリポジトリを取り出し、そのアカウントの `AccountExpansion` で、アカウントの畳みを外し、そのリポジトリを畳んだリポジトリの集合から外す

notifications「新着の通知」で通知の対象にならない取得（アカウントの最初の成功した取得）と、同じ `updated_at` で戻ったスレッドは新着に入らないので、spec の「開いてはならない」場合はそのまま満たされる。macOS の通知と自動展開は同じ判定の結果から作るので、両者がずれて「通知は出たのに開かない」ことは起こらない。

- 代替案: `SystemNotifier` に `onNewThreads` を足して知らせる（前の案）。UI の都合のコールバックが通知の部品に入り、通知の部品を作らない構成では自動展開が効かなくなる。判定を通知の部品から外し、`NotificationStore` に置くほうを選ぶ
- 代替案: `ListExpansion` を `ThreadNotifying` にして、自分の `NotificationTracker` を持たせ、`NotificationStore` から両方に知らせる（合成の notifier）。判定の呼び出し方（いつ基準にするか、`scopeInsufficient` で捨てるか）を `SystemNotifier` と同じに保ち続ける必要があり、ずれると「通知は出たのに開かない」が起こる。判定を 1 か所に置くほうを選ぶ
- 代替案: View が前の `FeedState` と今のものを比べる。アカウントの最初の成功した取得や、失敗して戻ったスレッドを区別できない

### D3. アカウントが消えたときの片付け

消えたアカウントの状態を捨てる規則は、`DiscoveryState.retainedAccountIDs: Set<AccountID>?` の 1 か所にまとめる。

- 全体の状態が「確認中」（`.checking`）のときは `nil` を返し、呼び出し側は何も捨てない（折りたたみは表示だけの状態で、確認が終わると同じアカウントが一覧に戻ることが多いため）
- 「アカウントあり」のときは、「無効」でないアカウントの ID を返す
- それ以外（gh からログアウトした、gh が見つからない、`hosts.yml` を読めないなど）は空集合を返し、すべてを捨てる

`retainedAccountIDs` が nil（確認中）なら何も捨てず、nil でなければその集合に無いアカウントの状態を捨てる。判断は `NotificationStore.sync` の 1 か所で行う。nil でないときに、出ている通知の整理（`ThreadChangeDispatcher` の `retainOnly`）と、まだ送っていない既読化の整理と一緒に、init の引数 `onAccountsRetained` でその集合を一覧に知らせる。`AppDelegate` は `onAccountsRetained` を `ListExpansion.retain(_:)` につなぐだけで、自分では判断しない。`retain` は、渡された ID 以外のアカウントの `AccountExpansion`（アカウントの畳みと畳んだリポジトリ）を辞書ごと捨てる。

確認中は `enabledStatuses` が空なので、ポーラー・一覧・tracker を捨て、出ている通知も `accountRemoved` → `retractAll(for:)` で取り下げる（main と同じ。notifications「通知の取り下げ」の「全体の状態が『アカウントあり』以外になったとき」）。確認中に残るのは、まだ送っていない既読化（`pendingReads`）と一覧の折りたたみだけになる。

リポジトリのグループが一覧から消えたとき（スレッドが無くなったとき）は、そのリポジトリの状態を捨てない。畳んだアカウントの区画のスレッドの一覧が一度消えて（止まった、「参加しているスレッドだけにする」の切り替えや再開の後の取得中）、または畳んだリポジトリのグループが一度消えて（すべて既読にした）、アカウントの最初の成功した取得で戻ってきたときは、畳んだまま戻す。最初の成功した取得のスレッドは新着ではないので D2 では開かず、ユーザーが開くか新着が届くまで畳んだままにする（ユーザーの判断）。

### D4. 番号は読み取るときに `NotificationThread.decodeList(from:endpoints:)` が 1 回だけ求める

`NotificationThread.decodeList(from:endpoints:)` が API のレスポンスからスレッドを読み取るときに、`ThreadDTO` が `NotificationThread` を作る前に、そのアカウントの `APIEndpoints` で `ThreadWebURL.subjectNumber(kind:subjectURL:repository:endpoints:)` を呼んで番号を求め、その値を入れて `NotificationThread` を 1 回で作る。`NotificationThread` の `let subjectNumber: String?` には既定値が無い（必須）ので、作る経路が増えても番号の渡し忘れはコンパイルで分かる。`GitHubAPIClient` のループで読み取った後から書き込むことはしない。求め方は `ThreadWebURL` の検証を共有する: `target(for:endpoints:)` が Pull request か Issue を返したときだけ、その `id` を番号にする。種類が Release と Discussion のスレッドは番号を持たない（`target` が URL の形を見ずに決まる）。それ以外は、番号を持つかどうかは種類ではなく `subject.url` の形で決まる。開く URL（`ThreadWebURL.make`）が nil になる（開かない）ときも持たせない。開く URL と同じ検証（API ベース URL の下にあること、リポジトリの一致、`ThreadID.isValid`）を通るので、表示する番号と開く URL は一致する。

番号を出さない分岐のうち「開く URL を組み立てられない（`make` が nil）」は、Web ベース URL がいつも `https` でアカウントのホストを持つので、API のデータからは届かない安全のための分岐で、テストは書いていない。

`ThreadRow` は `thread.subjectNumber` を読むだけで、描画のときには計算せず、番号の引数も持たない。2 行目を `#<番号> · <理由> · <更新日時>` にする（番号が無ければ今と同じ）。

- 代替案: 描画のたびに `ThreadWebURL.subjectNumber(kind:subjectURL:repository:endpoints:)` を呼ぶ（`AccountSectionView` が `APIEndpoints` を作って `ThreadRow` に番号を渡す）。開閉や再描画のたびに全行の `subject.url` を解析し直すことになる。読み取るときに 1 回だけ求めるほうを選ぶ
- 代替案: `GitHubAPIClient` のループで、読み取った後に `var subjectNumber` に書き込む（前の案）。読み取りの経路が増えたときに書き込み忘れが起こりうる。読み取るときに `let` で決めるほうを選ぶ
- 代替案: `NotificationThread` を作った後にそれを引数にして番号を求め、番号を入れて作り直す（`subjectNumber` に既定値を置く、前の形）。同じスレッドを 2 回作ることになり、既定値があると番号を渡し忘れても気づけない。番号を先に求めて 1 回で作るほうを選ぶ

### D5. 見出しの見た目と操作

- 共有の部品（`DisclosureButton`、`DisclosureChevron`、`CollapsedCount`、`capsuleBadge`）は `Mewbell/UI/DisclosureButton.swift` に置き、アカウントとリポジトリの見出しで使う。`DisclosureButton` は `isCollapsible`（畳めるか）と `collapsedCount: Int?`（件数のバッジ）を引数に取る
- アカウントの見出し: 開閉のボタンは、山形（`chevron.right`、開いているときは 90° 回す）・トークンの状態のアイコン・ユーザー名・active の印・ホスト・参加のみの印・件数を覆う。右の余白は押せる範囲に入れない。「すべて既読」のボタンは別のボタンのまま残す（押し間違えて開閉しないように）
- リポジトリの見出し: 開閉のボタンは、山形・`owner/name`・件数を覆う。右の余白は押せる範囲に入れない
- 件数: 折りたたんでいて 1 件以上のときだけ出す（`CollapsedCount`）。VoiceOver では「N unread」と読む
- ツールチップ（`Collapse alice (github.com)` / `Expand octo/app` など）は山形にだけ付け、ボタンには `accessibilityValue`（`Collapsed` / `Expanded`）と `accessibilityHint` を付ける。ボタン全体に `.help` や `accessibilityLabel` を付けると、見出しの中のトークンの状態のアイコンなどのツールチップと読み上げを上書きするため
- 畳めるかどうか、件数を出すかどうか、通知の一覧を出すかどうかは `AccountDisclosure` の結果だけで決める。`AccountDisclosure` は `showsThreads`（通知の一覧を出すか）と `isCollapsible`（畳めるか）を分けて持つ。畳むものは通知の一覧だけなので、`isCollapsible` は `showsThreads` と同じ値になる。畳めるのは、トークンの状態が「取得中」か「使える」で、通知の一覧（スレッドの一覧か、未読の通知が無いことを示す表示）を出しているときだけ。それ以外（トークンを取れない、取得の前、スコープ不足・認証エラーで止まった、「参加しているスレッドだけにする」の切り替えや再開の後の取得中）は、山形を出さずに同じ幅を空け、押せなくする（畳むものが無く、押しても山形の向きが変わるだけになるため）。このとき `ListExpansion` に覚えている状態は残すが、表示は開いた状態と同じにする（何も隠さず、件数も出さない）
- ユーザーが開閉したときは短いアニメーションを付けるが、「視差効果を減らす」がオンのときは付けない。新着で自動で開くときはアニメーションを付けない（ユーザーが開閉したときだけ付ける）
- 字下げ（`padding(.leading, 22)`）は今のまま。山形は幅 16（スレッドの行の種類のアイコンと同じ）にし、アカウントの見出しではトークンの状態のアイコンの前に置く。これで、区画の中身はトークンの状態のアイコンの列に、リポジトリ名とスレッドの件名はユーザー名の列に揃う

### D6. リポジトリのグループ分けは `NotificationStore` が feeds を更新したときにアカウントごとに 1 回だけ作る

`RepositoryGroup` と `RepositoryGroup.groups(from:)` を `Mewbell/Polling/RepositoryGroup.swift` に移す（`UI/NotificationGrouping.swift` から。UI に残る理由の表示は、`Mewbell/UI/ThreadReason.swift` の `ThreadReason` に改名する）。`NotificationStore`（`@MainActor`）は `feeds` の `didSet` で、スレッドが変わったアカウントのグループ分けだけを作り直して `repositories: [AccountID: [RepositoryGroup]]` に持つ（ユーザーの判断）。取得の状態や診断の値だけが変わった更新では作り直さず、`feeds` から消えたアカウントは `repositories` からも消す。`FeedState` はグループ分けを持たない。一覧の描画は `NotificationStore` が持つグループ分けを並べるだけで、描画の中でグループ分けをしない。

- 理由: グループ分けは取得のときにしか変わらない派生データなので、描画の中で作ると、開閉や新着で区画が描き直されるたびにやり直すことになる。一覧だけが使う並べ方の計算なので、一覧が読む `NotificationStore` の上で、feeds の更新に合わせて 1 回だけ作る
- 代替案: 描画の中で `RepositoryGroup.groups(from:)` を呼ぶ（前の形）。描き直しのたびにグループ分けをやり直す
- 代替案: `FeedState` が持つ（スレッドを受け取るときに作る。6.3 の形）。一覧だけが使う並べ方の計算が、`FeedState` の書き換えのたびにポーラーの actor の上で走る。`FeedState` の比較（`==`）にグループ分けも入り、スレッドと同じ中身を 2 回比べることになる。Polling の値に一覧の都合が入る。`NotificationStore` に置くほうを選ぶ

## Risks / Trade-offs

- [新着で開くと、ユーザーが閉じたものが勝手に開く] → ユーザーの判断で決めた仕様。開くのは新着を含むグループだけに限る
- [ポップオーバーを開いている間に新着でグループが開き、行がずれる] → 今も新着で行は増えるので、同じ程度の動き。行の操作のボタンの位置は #15 で上端に揃えてある
- [表示用に `subject.url` を読む] → 開く URL と同じ検証を通った値だけを出し、ネットワークには使わない

## セキュリティ

- トークン: この change はトークンを取得・保持・送信しない。トークンの流れ（`gh auth token` で取得し、`AccountPoller` の中だけに持ち、API ベース URL にだけ送り、アカウントの削除・無効化・終了で捨てる）は変えない
- 永続化: 折りたたみの状態はメモリにだけ持ち、UserDefaults にもファイルにも書かない。中身はアカウント ID とリポジトリ名だけで、トークンや API の URL は含まない
- gh サブプロセス: 触れない
- ネットワーク: リクエスト、オリジンの検査、リダイレクト、キャッシュの扱いは変えない
- URL を開く処理: `ThreadWebURL.make` の振る舞いは変えない。番号の取り出し（読み取るときに `NotificationThread.decodeList(from:endpoints:)` が `NotificationThread` を作る前に行う）は同じ検証を共有し、別のホストを指す `subject.url` からは番号を出さない（テストで確かめる）
- ログ: 新しくログを出さない
- 通知の本文: 変えない

## テストでの差し替え

- `ListExpansion` と `AccountExpansion` は依存を持たないので、そのままテストする。観測の粒度は `withObservationTracking` で確かめる: あるアカウントの `AccountExpansion` を読んでいる間に、ほかのアカウントを開閉しても onChange が呼ばれず、そのアカウント自身を開閉すると呼ばれる
- グループ分けは、`RepositoryGroup.groups(from:)` の並べ方と、`NotificationStoreRepositoriesTests` で `NotificationStore.repositories` が、届いた feed のグループになる・診断の値だけの変化では書き込まれない（`withObservationTracking`）・既読化で消える・無効にしたアカウントで消えることをテストする
- 新着は、`NotificationStore` に偽の `PollerFactory` と偽の notifier（`ThreadNotifying`）を渡し、`onNewThreads` に呼ばれた値を集めるクロージャを渡して確かめる。`ThreadChangeDispatcher` は `NotificationStore` の内部の型なので、`NotificationStore` を通して確かめる（`baselineSet(for:keeping:)`、`threadsChanged(for:posted:retracted:)`、`threadRemoved(_:for:)`、`retractAll(for:)` の呼ばれ方も同じテストで見る）。アカウントを無効にしたときの `retractAll(for:)` と `retainOnly(_:)` の呼ばれ方は、`SettingsPollingTests.swift` の `NotificationStoreSettingsTests` で見る
- `onAccountsRetained` は、`NotificationStore` のテスト（`NotificationStoreNewThreadsTests.swift` の `NotificationStoreRetainedAccountsTests`）で、`sync` に渡した全体の状態ごとに確かめる: 確認中では呼ばれず、それ以外では `retainedAccountIDs` の集合で呼ばれる
- `SystemNotifier` は、既存の偽の `UserNotificationCenter` で、通知センターの操作だけを確かめる
- `AccountDisclosure` と `DiscoveryState.retainedAccountIDs` は純粋な値なので、入力の状態ごとにそのままテストする
- 番号は、`ThreadWebURL.subjectNumber(kind:subjectURL:repository:endpoints:)` のテストと、`GitHubAPIClient` の取得のテスト（偽の `HTTPTransport` とレスポンスのフィクスチャ）で、`decodeList(from:endpoints:)` が入れた `NotificationThread.subjectNumber` を確かめる
- 見た目はプレビュー（折りたたんだアカウント、折りたたんだリポジトリ、番号のある行と無い行）と手元での起動で確かめる
