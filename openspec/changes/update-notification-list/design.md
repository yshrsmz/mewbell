# Design

## Context

- 一覧は `NotificationListView` → `AccountSectionView`（見出し、取得の状態、操作の失敗、`NotificationGrouping.groups` でまとめたリポジトリのグループ）→ `ThreadRow` の順に組み立てている。どれも `NotificationStore.feeds` を読むだけで、自分の状態を持たない
- ポップオーバーは `MenuBarExtra`（`.window` スタイル）の中身で、開くたびに View が作り直されることがある。View の `@State` に置いた値が閉じた後も残るとは限らない
- 新着の判定は `SystemNotifier` が持つ `NotificationTracker` が行っている。基準の取得（最初の取得、`resetBaseline` の後）では何も出さず、その後は初めて見たスレッドか `updated_at` が進んだスレッドを `Changes.post` に入れる。「macOS の通知を出す」がオフでも `tracker.update` は呼んでいて、通知を出すかどうかだけを `notifies` で決めている
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

### D2. 新着は `SystemNotifier` が知らせる

`SystemNotifier` に `onNewThreads: (@MainActor (AccountID, [NotificationThread]) -> Void)?` を足し、`feedChanged` の `.loaded` の分岐で `tracker.update` が返した `changes.post` が空でなければ、`notifies(account)` で絞る前の値で呼ぶ。`AppDelegate` がこれを `ListExpansion.expand(account:repositories:)` につなぐ。`expand` は、そのアカウントを `collapsedAccounts` から、新着のスレッドのリポジトリを `collapsedRepositories` から外す。

- 基準の取得、`resetBaseline` の後の最初の取得、同じ `updated_at` で戻ったスレッドは `changes.post` に入らないので、spec の「開いてはならない」場合はそのまま満たされる
- 代替案: `ListExpansion` を `ThreadNotifying` にして、自分の `NotificationTracker` を持たせ、`NotificationStore` から両方に知らせる（合成の notifier）。判定の呼び出し方（いつ基準にするか、`scopeInsufficient` で捨てるか）を `SystemNotifier` と同じに保ち続ける必要があり、ずれると「通知は出たのに開かない」が起こる。判定を 1 か所に置くほうを選ぶ
- 代替案: View が前の `FeedState` と今のものを比べる。基準の取得や、失敗して戻ったスレッドを区別できない

### D3. アカウントが消えたときの片付け

`AppDelegate` の `accountStore.onStateChange` で、`NotificationStore.sync(with:)` に続けて `ListExpansion.retain(_:)` を、「無効」以外のアカウントの ID で呼ぶ。全体の状態が「アカウントあり」でないとき（`.checking`、`hosts.yml` を読めないなど。gh の読み直しの途中で一時的になることがある）は呼ばない。`retain` は、それ以外のアカウントの `collapsedAccounts` と `collapsedRepositories` を捨てる。リポジトリのグループが空になって消えたときは、そのリポジトリの状態を捨てない（次に現れるスレッドは新着なので D2 で開く。失敗して同じ `updated_at` で戻ったときは、折りたたんだままにしておく）。

### D4. 番号は `ThreadWebURL` から取り出す

`ThreadWebURL` に `static func subjectNumber(for thread: NotificationThread, endpoints: APIEndpoints) -> String?` を足し、`suffix(for:endpoints:)` が `["pull", id]` か `["issues", id]` を返したときだけ `id` を返す。開く URL と同じ検証（API ベース URL の下にあること、リポジトリの一致、`ThreadID.isValid`）を通るので、表示する番号と開く URL は一致する。`AccountSectionView` が `APIEndpoints(host: account.host)` をアカウントごとに 1 回作り、`ThreadRow` に `number: String?` を渡す。`ThreadRow` は 2 行目を `#<番号> · <理由> · <更新日時>` にする（番号が無ければ今と同じ）。

- 代替案: `NotificationThread` を作るとき（API のレスポンスを読むとき）に番号を持たせる。読む場所では `APIEndpoints` を持たず、オリジンの検査を 2 か所に書くことになる

### D5. 見出しの見た目と操作

- アカウントの見出し: 先頭に開閉の山形（`chevron.right`、開いているときは 90° 回す）のボタンを置き、ユーザー名・ホストまでを同じボタンにする。「すべて既読」のボタンは別のボタンのまま残す（押し間違えて開閉しないように）。折りたたんでいて未読が 1 件以上あるときは、件数を見出しに出す
- リポジトリの見出し: 山形と `owner/name` をまとめて 1 つのボタンにし、折りたたんでいるときは件数を出す
- ツールチップ（`Collapse alice (github.com)` / `Expand octo/app` など）は山形にだけ付け、ボタンには `accessibilityValue`（`Collapsed` / `Expanded`）と `accessibilityHint` を付ける。ボタン全体に `.help` や `accessibilityLabel` を付けると、見出しの中のトークンの状態のアイコンなどのツールチップと読み上げを上書きするため
- トークンを取れないアカウントと、通知の一覧をまだ出していないアカウントでは、山形を出さずに同じ幅を空け、押せなくする（畳むものが無く、押しても山形の向きが変わるだけになるため）
- 開閉に短いアニメーションを付けるが、「視差効果を減らす」がオンのときは付けない
- 字下げ（`padding(.leading, 22)`）は今のまま。山形は幅 16（スレッドの行の種類のアイコンと同じ）にし、アカウントの見出しではトークンの状態のアイコンの前に置く。これで、区画の中身はトークンの状態のアイコンの列に、リポジトリ名とスレッドの件名はユーザー名の列に揃う

## Risks / Trade-offs

- [新着で開くと、ユーザーが閉じたものが勝手に開く] → ユーザーの判断で決めた仕様。開くのは新着を含むグループだけに限る
- [`SystemNotifier` が UI の都合のコールバックを持つ] → 中身はスレッドの一覧だけで、UI の型には依存しない。テストでは偽のコールバックで確かめる
- [ポップオーバーを開いている間に新着でグループが開き、行がずれる] → 今も新着で行は増えるので、同じ程度の動き。行の操作のボタンの位置は #15 で上端に揃えてある
- [表示用に `subject.url` を読む] → 開く URL と同じ検証を通った値だけを出し、ネットワークには使わない

## セキュリティ

- トークン: この change はトークンを取得・保持・送信しない。トークンの流れ（`gh auth token` で取得し、`AccountPoller` の中だけに持ち、API ベース URL にだけ送り、アカウントの削除・無効化・終了で捨てる）は変えない
- 永続化: 折りたたみの状態はメモリにだけ持ち、UserDefaults にもファイルにも書かない。中身はアカウント ID とリポジトリ名だけで、トークンや API の URL は含まない
- gh サブプロセス: 触れない
- ネットワーク: リクエスト、オリジンの検査、リダイレクト、キャッシュの扱いは変えない
- URL を開く処理: `ThreadWebURL.make` の振る舞いは変えない。番号の取り出しは同じ検証を共有し、別のホストを指す `subject.url` からは番号を出さない（テストで確かめる）
- ログ: 新しくログを出さない
- 通知の本文: 変えない

## テストでの差し替え

- `ListExpansion` は依存を持たないので、そのままテストする
- `SystemNotifier.onNewThreads` は、既存の偽の `UserNotificationCenter` を使ったテストに、呼ばれた値を集めるクロージャを渡して確かめる
- 番号は `ThreadWebURL.subjectNumber` を `APIEndpoints` と `NotificationThread` のフィクスチャでテストする
- 見た目はプレビュー（折りたたんだアカウント、折りたたんだリポジトリ、番号のある行と無い行）と手元での起動で確かめる
