# Design

## Context

- 一覧は `NotificationListView` → `AccountSectionView`（見出し、取得の状態、操作の失敗、`NotificationGrouping.groups` でまとめたリポジトリのグループ）→ `ThreadRow` の順に組み立てている。どれも `NotificationStore.feeds` を読むだけで、自分の状態を持たない
- ポップオーバーは `MenuBarExtra`（`.window` スタイル）の中身で、開くたびに View が作り直されることがある。View の `@State` に置いた値が閉じた後も残るとは限らない
- main では、新着の判定は `SystemNotifier` が持つ `NotificationTracker` が行っている。notifications「新着の通知」で通知の対象にならない取得（基準の取得）では何も出さず、その後は初めて見たスレッドか `updated_at` が進んだスレッドを `Changes.post` に入れる。「macOS の通知を出す」がオフでも `tracker.update` は呼んでいて、通知を出すかどうかだけを `notifies` で決めている。この change で、この判定を `NotificationStore` に移す（D2）
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

### D1. 折りたたみの状態は `AppDelegate` が持つ `@MainActor @Observable` のオブジェクトに置く

`Mewbell/UI/ListExpansion.swift` に `@MainActor @Observable final class ListExpansion` を作る。持つのは `collapsedAccounts: Set<AccountID>` と `collapsedRepositories: Set<RepositoryKey>`（`RepositoryKey` は `AccountID` と `RepositoryName` の組）だけ。操作は `isCollapsed(_:)`、`toggle(_:)`、`expand(account:repositories:)`、`retain(_ accounts: Set<AccountID>)`。`AppDelegate` が `NotificationStore` などと同じように 1 つ作って持ち、`MewbellApp` から `MenuBarContentView` → `NotificationListView` → `AccountSectionView` に渡す。

- 代替案: View の `@State`。ポップオーバーを作り直すと消えることがあり、「閉じても残る」を満たせない
- 代替案: `@SceneStorage` / `@AppStorage`。ディスクに残り、「起動中だけ」に反する
- すべて `@MainActor` の上で動く。ネットワークやポーラーの actor には触れない

### D2. 新着は `NotificationStore` が判定して配る

新着の判定（`NotificationTracker`）を `SystemNotifier` から `NotificationStore` に移す。`NotificationStore` は取得の結果を受けるたびに tracker を更新し、その結果を 2 つの先に配る。

- macOS の通知: `ThreadNotifying` の `baselineSet(for:keeping:)` と `threadsChanged(for:posted:retracted:)` で、通知の出し入れを知らせる。`ThreadNotifying` から `feedChanged(for:from:to:)` と `resetBaseline(_:)` は無くす。`SystemNotifier` は判定を持たず、通知センターの操作だけをする（「macOS の通知を出す」がオフのアカウントの `posted` を出さないのは、今までどおり `SystemNotifier` が `notifies` で決める）
- 一覧の自動展開: `NotificationStore` の init の引数 `onNewThreads` に、新着のスレッドを、「macOS の通知を出す」で絞る前の値で渡す。`AppDelegate` がこれを `ListExpansion.expand(account:repositories:)` につなぐ。`expand` は、そのアカウントを `collapsedAccounts` から、新着のスレッドのリポジトリを `collapsedRepositories` から外す

notifications「新着の通知」で通知の対象にならない取得（基準の取得）と、同じ `updated_at` で戻ったスレッドは新着に入らないので、spec の「開いてはならない」場合はそのまま満たされる。macOS の通知と自動展開は同じ判定の結果から作るので、両者がずれて「通知は出たのに開かない」ことは起こらない。

- 代替案: `SystemNotifier` に `onNewThreads` を足して知らせる（前の案）。UI の都合のコールバックが通知の部品に入り、通知の部品を作らない構成では自動展開が効かなくなる。判定を通知の部品から外し、`NotificationStore` に置くほうを選ぶ
- 代替案: `ListExpansion` を `ThreadNotifying` にして、自分の `NotificationTracker` を持たせ、`NotificationStore` から両方に知らせる（合成の notifier）。判定の呼び出し方（いつ基準にするか、`scopeInsufficient` で捨てるか）を `SystemNotifier` と同じに保ち続ける必要があり、ずれると「通知は出たのに開かない」が起こる。判定を 1 か所に置くほうを選ぶ
- 代替案: View が前の `FeedState` と今のものを比べる。基準の取得や、失敗して戻ったスレッドを区別できない

### D3. アカウントが消えたときの片付け

消えたアカウントの状態を捨てる規則は、`DiscoveryState.retainedAccountIDs: Set<AccountID>?` の 1 か所にまとめる。

- gh の読み直しの途中（`.checking`）では `nil` を返し、呼び出し側は何も捨てない（同じアカウントが戻ってくるため）
- 「アカウントあり」のときは、「無効」でないアカウントの ID を返す
- それ以外（gh からログアウトした、gh が見つからない、`hosts.yml` を読めないなど）は空集合を返し、すべてを捨てる

`NotificationStore.sync`（出ている通知と、まだ送っていない既読化）と `AppDelegate`（`accountStore.onStateChange` で `ListExpansion.retain(_:)` を呼ぶ）の両方がこれを使い、ポーラーと同じ規則で状態を捨てる。`retain` は、渡された ID 以外のアカウントの `collapsedAccounts` と `collapsedRepositories` を捨てる。

リポジトリのグループが一覧から消えたとき（スレッドが無くなったとき）は、そのリポジトリの状態を捨てない。畳んだアカウントやリポジトリが一覧から一度消えて（止まった、すべて既読にした、「参加しているスレッドだけにする」の切り替え、再開）、基準の取得で戻ってきたときは、畳んだまま戻す。基準の取得のスレッドは新着ではないので D2 では開かず、ユーザーが開くか新着が届くまで畳んだままにする（ユーザーの判断）。

### D4. 番号は取得したときに `GitHubAPIClient` が 1 回だけ求める

`GitHubAPIClient.fetchNotifications` が `subject.url` を読んだときに、そのアカウントの `APIEndpoints` で番号を 1 回だけ求め、`NotificationThread.subjectNumber: String?` に持たせる。求め方は `ThreadWebURL` の検証を共有する: `suffix(for:endpoints:)` が `["pull", id]` か `["issues", id]` を返したときだけ `id` を番号にする。番号を出すかどうかは種類ではなく `subject.url` の形で決まるが、種類が Release と Discussion のスレッドは URL の形にかかわらず番号を持たせない。開く URL（`ThreadWebURL.make`）が nil になる（開かない）ときも持たせない。開く URL と同じ検証（API ベース URL の下にあること、リポジトリの一致、`ThreadID.isValid`）を通るので、表示する番号と開く URL は一致する。

`ThreadRow` は `thread.subjectNumber` を読むだけで、描画のときには計算しない。2 行目を `#<番号> · <理由> · <更新日時>` にする（番号が無ければ今と同じ）。

- 代替案: 描画のたびに `ThreadWebURL.subjectNumber` を呼ぶ（`AccountSectionView` が `APIEndpoints` を作って `ThreadRow` に番号を渡す）。開閉や再描画のたびに全行の `subject.url` を解析し直すことになる。取得のときに 1 回だけ求めるほうを選ぶ

### D5. 見出しの見た目と操作

- 共有の部品（`DisclosureButton`、`DisclosureChevron`、`CollapsedCount`、`AccountDisclosure`、`capsuleBadge`）は `Mewbell/UI/DisclosureButton.swift` に置き、アカウントとリポジトリの見出しで使う
- アカウントの見出し: 開閉のボタンは、山形（`chevron.right`、開いているときは 90° 回す）・トークンの状態のアイコン・ユーザー名・active の印・ホスト・参加のみの印・件数を覆う。右の余白は押せる範囲に入れない。「すべて既読」のボタンは別のボタンのまま残す（押し間違えて開閉しないように）
- リポジトリの見出し: 開閉のボタンは、山形・`owner/name`・件数を覆う。右の余白は押せる範囲に入れない
- 件数: 折りたたんでいて 1 件以上のときだけ出す（`CollapsedCount`）。VoiceOver では「N unread」と読む
- ツールチップ（`Collapse alice (github.com)` / `Expand octo/app` など）は山形にだけ付け、ボタンには `accessibilityValue`（`Collapsed` / `Expanded`）と `accessibilityHint` を付ける。ボタン全体に `.help` や `accessibilityLabel` を付けると、見出しの中のトークンの状態のアイコンなどのツールチップと読み上げを上書きするため
- 畳めるかどうかと件数を出すかどうかは `AccountDisclosure` で 1 か所で決める。畳めるのは、トークンの状態が「取得中」か「使える」で、通知の一覧（スレッドの一覧か、未読が無いことの表示）を出しているときだけ。それ以外（トークンを取れない、取得の前、スコープ不足・認証エラーで止まった、「参加しているスレッドだけにする」の切り替えや再開の後の取得中）は、山形を出さずに同じ幅を空け、押せなくする（畳むものが無く、押しても山形の向きが変わるだけになるため）。このとき `ListExpansion` に覚えている状態は残すが、表示は開いた状態と同じにする（何も隠さず、件数も出さない）
- 開閉に短いアニメーションを付けるが、「視差効果を減らす」がオンのときは付けない
- 字下げ（`padding(.leading, 22)`）は今のまま。山形は幅 16（スレッドの行の種類のアイコンと同じ）にし、アカウントの見出しではトークンの状態のアイコンの前に置く。これで、区画の中身はトークンの状態のアイコンの列に、リポジトリ名とスレッドの件名はユーザー名の列に揃う

## Risks / Trade-offs

- [新着で開くと、ユーザーが閉じたものが勝手に開く] → ユーザーの判断で決めた仕様。開くのは新着を含むグループだけに限る
- [ポップオーバーを開いている間に新着でグループが開き、行がずれる] → 今も新着で行は増えるので、同じ程度の動き。行の操作のボタンの位置は #15 で上端に揃えてある
- [表示用に `subject.url` を読む] → 開く URL と同じ検証を通った値だけを出し、ネットワークには使わない

## セキュリティ

- トークン: この change はトークンを取得・保持・送信しない。トークンの流れ（`gh auth token` で取得し、`AccountPoller` の中だけに持ち、API ベース URL にだけ送り、アカウントの削除・無効化・終了で捨てる）は変えない
- 永続化: 折りたたみの状態はメモリにだけ持ち、UserDefaults にもファイルにも書かない。中身はアカウント ID とリポジトリ名だけで、トークンや API の URL は含まない
- gh サブプロセス: 触れない
- ネットワーク: リクエスト、オリジンの検査、リダイレクト、キャッシュの扱いは変えない
- URL を開く処理: `ThreadWebURL.make` の振る舞いは変えない。番号の取り出し（取得のときに `GitHubAPIClient` が行う）は同じ検証を共有し、別のホストを指す `subject.url` からは番号を出さない（テストで確かめる）
- ログ: 新しくログを出さない
- 通知の本文: 変えない

## テストでの差し替え

- `ListExpansion` は依存を持たないので、そのままテストする
- 新着は、`NotificationStore` に偽の `PollerFactory` と偽の notifier（`ThreadNotifying`）を渡し、`onNewThreads` に呼ばれた値を集めるクロージャを渡して確かめる（`baselineSet(for:keeping:)` と `threadsChanged(for:posted:retracted:)` の呼ばれ方も同じテストで見る）
- `SystemNotifier` は、既存の偽の `UserNotificationCenter` で、通知センターの操作だけを確かめる
- `AccountDisclosure` と `DiscoveryState.retainedAccountIDs` は純粋な値なので、入力の状態ごとにそのままテストする
- 番号は、`GitHubAPIClient` の取得のテスト（偽の `HTTPTransport` とレスポンスのフィクスチャ）で `NotificationThread.subjectNumber` を確かめる
- 見た目はプレビュー（折りたたんだアカウント、折りたたんだリポジトリ、番号のある行と無い行）と手元での起動で確かめる
