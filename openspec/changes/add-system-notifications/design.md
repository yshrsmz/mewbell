# Design

## Context

M2 の時点の構成（動機は proposal.md の Why、満たすべき振る舞いは `specs/notifications`、`specs/github-api`、`specs/polling`、`specs/ui`）:

- `AccountPoller`（actor）が 1 アカウントのポーリングのループと `FeedState`（`phase` と `threads`）を持ち、変わるたびに `onUpdate` で `NotificationStore`（`@MainActor @Observable`）へ渡す。`NotificationStore.apply` は世代番号で、止めたポーラーから遅れて届いた更新を捨てる
- `AccountPoller` は取得の `await` の間も actor に入れる（actor は再入可能）。`requestUnconditionalFetch()` は `Atomic<Bool>` の印で、次の取得を条件なしにする
- `GitHubAPIClient`（状態なしの struct）の `send` が、トークンを付ける唯一の場所。今は `GET` に固定されている。オリジン検査は `APIEndpoints.isAllowedRequestURL`
- スレッドを開く処理は `AccountSectionView.open(_:)` にあり、`ThreadWebURL.make` で組み立てて `NSWorkspace.shared.open` するだけ
- `AppDelegate` がストアを作り、テストのホストやプレビューでは `LaunchContext.isTestHostOrPreview` で gh もポーリングも動かさない
- `MewbellApp` の `MenuBarExtra("Mewbell", systemImage: "cat.fill")` はラベルが固定

macOS と GitHub の前提:

- `UNUserNotificationCenter` は同じ識別子で `add` すると置き換える。前方一致で消す API は無く、消すには識別子の列が要る（`getDeliveredNotifications` で今出ている通知を取れる）
- アプリが終了しているときに通知をクリックすると、macOS がアプリを起動し、`delegate` の `didReceive` を呼ぶ。`delegate` は `applicationDidFinishLaunching` を返す前に設定しておく必要がある
- `PATCH /notifications/threads/{thread_id}` は成功で `205 Reset Content` を返す。ドキュメントに載っている他の状態コードは `304` と `403`

## Goals / Non-Goals

**Goals:**

- 「何を通知し、何を取り下げるか」を、`UNUserNotificationCenter` に触れない純粋な型で決め、ユニットテストで確かめられるようにする
- 一覧のクリックと macOS の通知のクリックを、同じ「開く → 既読」の経路に通す
- 既読化のリクエストも `GitHubAPIClient` の 1 か所で組み立て、トークンを付ける場所を増やさない

**Non-Goals:**

- 通知の内容の設定（音の有無、participating だけ通知、など）。M4 で扱う
- Done（`DELETE /notifications/threads/{id}`）と全既読（`PUT /notifications`）。M4 で扱う
- アプリのアイコンのバッジ（`LSUIElement` なので Dock に出ない）

## Decisions

### D1. モジュールと型の分担

| 置き場所 | 型 | 役割 |
| --- | --- | --- |
| `GitHubAPI/` | `GitHubAPIClient.markThreadRead(endpoints:token:threadID:)`、`MarkReadResult` | 既読化のリクエスト。`send` に HTTP メソッドの引数を足して共有する（D3） |
| `GitHubAPI/` | `ThreadID`（検証） | 1〜20 桁の数字かを確かめる関数。API の URL のパスに入れる前と、`userInfo` から戻ってきた値に使う |
| `Polling/` | `AccountPoller.markRead(threadID:)` | 一覧から外す・隠す・既読化を送る・次の取得を条件なしにする（D4） |
| `Polling/` | `NotificationStore` | `open(_:in:)`（開く → 既読）、`openFromNotification(_:)`、起動直後の既読の保留、`unreadCount`、`ThreadNotifying` への受け渡し（D5、D6） |
| `Notifications/` | `NotificationTracker`（struct） | アカウントごとに「見たスレッドと、そのときの `updated_at`」を持ち、取得の結果から「出す」「取り下げる」を決める純粋な型（D2） |
| `Notifications/` | `ThreadNotificationContent` | スレッドから通知のタイトル・本文・`userInfo` を作る。`userInfo` から `ThreadOpenRequest` を検証して作り直す（D7） |
| `Notifications/` | `UserNotificationCenter`（protocol）と `LiveUserNotificationCenter` | `requestAuthorization`、`authorizationStatus`、`add`、`removeDelivered(identifiers:)`、`deliveredIdentifiers()` だけの薄い口。テストでは偽物に差し替える |
| `Notifications/` | `SystemNotifier`（`@MainActor`、`ThreadNotifying` に準拠） | `NotificationTracker` の結果を `UserNotificationCenter` に流す。アカウント単位・全体の取り下げ |
| `Notifications/` | `NotificationPermission`（`@MainActor @Observable`） | 許可の状態。ポップオーバーを開いたときに読み直す |
| `Notifications/` | `NotificationClickHandler`（`UNUserNotificationCenterDelegate`） | `willPresent` で前面でもバナーを出し、`didReceive` で `userInfo` を検証して `NotificationStore` に渡す |
| `App/` | `AppDelegate`、`MewbellApp` | 上の型を組み立てる。delegate を `init` で設定し、許可を `applicationDidFinishLaunching` で求める。`MenuBarExtra` のラベルにバッジを出す（D8） |
| `UI/` | `AccountSectionView`、`NotificationPermissionBanner` | クリックを `NotificationStore.open` に渡す。許可が無いときの案内 |

### D2. 何を通知し、何を取り下げるか（`NotificationTracker`）

アカウントごとに `seen: [threadID: Date]`（そのスレッドを最後に見たときの `updated_at`）と、`current: Set<threadID>`（今の一覧）を持つ。`NotificationStore.apply` が `FeedState` の変化を見て、次の入力を渡す。

| 変化 | 入力 | 結果 |
| --- | --- | --- |
| `phase` が `.loading` から `.loaded` | `baseline(threads)` | 何も出さない。`seen` と `current` を作る。前回の実行の通知の掃除（下）をする |
| `.loaded` のまま `threads` が変わった（取得・既読化） | `update(threads)` | `seen` に無いか、`updated_at` が `seen` より新しいスレッドを出す。`current` から消えたスレッドを取り下げる。`seen` を更新する |
| `.retrying` | なし | 何もしない（spec の「通信の失敗では消さない」） |
| `.scopeInsufficient` / `.unauthorized` | `reset` | そのアカウントの通知をすべて取り下げ、`seen` と `current` を捨てる（再開の後はまた基準から） |
| アカウントが一覧から消えた（`sync` でポーラーを止めた）・全体が「アカウントあり」以外 | `reset` | 同上 |

- `seen` は、一覧から消えたスレッドの分も消さない。既読化に失敗して同じ `updated_at` のまま一覧に戻ったスレッドを出し直さないためと、Web で既読にした後に動きがあったスレッドを「進んだ」と判定するため。増えるのは実行中に見たスレッドの数だけで、アカウントの `reset` で捨てる
- `304` の後も `FeedState` は `phase` の時刻が変わるだけで、`threads` は同じなので何も出さない
- 「すでに出ている通知を取り下げる」には識別子の列が要るので、アカウント単位の取り下げと前回の実行の掃除は `deliveredIdentifiers()` を `<host>/<user>/` で前方一致させて求める。識別子の `<user>` は `/` を含まない（gh-cli の検証）ので、前方一致で別のアカウントに当たらない
- 前回の実行の掃除: 基準の取得のとき、そのアカウントの出ている通知のうち、今の一覧に無いスレッドのものを取り下げる。全体の状態が変わったとき（`sync`）は、一覧に無いアカウントの通知をまとめて取り下げる

代替案: ポーラー（actor）の中で差分を出す。ポーラーは「基準かどうか」を知っているが、アカウントの増減や全体の状態は `NotificationStore` しか知らないので、取り下げの契機が 2 か所に分かれる。`FeedState` の変化だけで決められるので、`@MainActor` の側に置く。

### D3. 既読化のリクエスト

- `send(_:method:endpoints:token:ifModifiedSince:)` に `method` を足し、`GET` と `PATCH` で共有する。オリジン検査・ヘッダー・リダイレクトの拒否（`URLSessionTransport` の delegate）・ログの規則はそのまま掛かる。`PATCH` はボディを送らない
- URL は `endpoints.apiURL(path: "notifications/threads/\(id)")`。`id` は先に `ThreadID` の検証（1〜20 桁の ASCII 数字）を通す。通らなければ送らずに `.failed(.rejectedURL)`
- 結果は `MarkReadResult`（`.read`、`.unauthorized`、`.rateLimited`、`.failed`）。`205`・`304`・`404` は `.read`。状態コードの分類は `classifyFailure` を共有せず、短い `switch` で書く（`GET` 用の結果の型に依存させないため）
- 既読化の失敗では、トークンを取り直さず、ポーリングの待ち時間も変えない。次の条件なしの取得で、失敗したスレッドは一覧に戻る

### D4. ポーラーでの既読化（`AccountPoller.markRead`）

```
markRead(id):
  hidden[id] = .untilRequestFinishes      // 取得の結果から取り除く
  state.threads から id を外して publish
  token が無い / 止まっている → hidden[id] = .untilFetch(nextFetchNumber)、印を立てて終わり
  result = await client.markThreadRead(...)   // actor は再入可能なので、取得のループは止まらない
  hidden[id] = .untilFetch(nextFetchNumber)    // この後に始める取得の 200 で隠すのをやめる
  unconditionalRequested を立てる
```

- 取得には連番（`fetchNumber`）を振る。`.updated` を受け取ったら、`hidden` のうち「この取得の番号以降で外してよい」ものを外し、残りは `threads` から取り除いてから `state.threads` に入れる。これで、既読化より前に送った取得の結果でスレッドが戻らない（spec「取得中に既読にする」）
- `304` では `threads` は変わらないので、隠したスレッドはそのまま外れている。次の条件なしの取得（印による）の `200` で、既読にできていれば返らず、失敗していれば戻る
- 停止やトークンの取り直しでも `hidden` は捨てない。どの印も、既読化が終わった後に始めた取得の `200` で外れるので、残り続けることはない

代替案: `NotificationStore` の側でだけ一覧から外す。ポーラーの `state` に残っていると、次の `304` の後の `publish` でスレッドが戻ってしまうので、ポーラーの状態から外す必要がある。

### D5. 開く → 既読の経路（`NotificationStore`）

- `open(_ thread: NotificationThread, in account: AccountID)`: `APIEndpoints` と `ThreadWebURL.make` で URL を組み立て、組み立てられなければ何もしない。注入した `openURL`（既定は `NSWorkspace.shared.open`、テストでは記録するだけ）で開き、`feeds[account]` からすぐに外し（バッジがすぐ減る）、ポーラーの `markRead` を呼ぶ
- `openFromNotification(_ request: ThreadOpenRequest)`: 検証済みの URL を開き、ポーラーがあれば `markRead` を呼ぶ。ポーラーがまだ無ければ `pendingReads[account]` に積む
- `sync(with:)` でポーラーを作るとき、`pendingReads` にある分を `start()` の前に `markRead` する（最初の取得より前に既読化の印と `hidden` が入る）。`sync` の状態が「アカウントあり」でそのアカウントが一覧に無い、トークンを取れない、または全体の状態が「アカウントあり」以外（確認中を除く）なら、保留を捨てる
- `unreadCount`: `feeds` の `threads.count` の合計。止まったアカウントは `threads` が空なので 0 件になる。トークンを取れないアカウントは `feeds` に無い（ポーラーが無い）か、あっても `stopAll` / `sync` で消える

### D6. `ThreadNotifying` への受け渡しと actor の境界

- `NotificationStore` は `ThreadNotifying?`（`@MainActor` の protocol）を持ち、`apply` で `FeedState` を差し替える前後の値を比べて D2 の入力を渡す。テストのホストとプレビューでは nil
- `SystemNotifier` は `@MainActor`。`UserNotificationCenter` の呼び出しは `async` で、結果を待たずに `Task` で流す（`apply` を止めない）。同じアカウントの `add` と `remove` の順序が入れ替わらないよう、`SystemNotifier` が 1 本の直列のキュー（前の `Task` を待ってから次を始める）で流す
- `NotificationClickHandler` は `NSObject` で `UNUserNotificationCenterDelegate` に準拠する。delegate のメソッドは任意のスレッドから呼ばれるので `nonisolated` にし、`userInfo` を `ThreadOpenRequest`（`Sendable` な値）に検証してから `MainActor` に渡す
- スレッドと処理の対応: 取得・既読化のリクエストは `AccountPoller`（actor）の上、差分と UI の状態は `MainActor`、通知センターへの `add` / `remove` は `UNUserNotificationCenter` の内部のキュー

### D7. 通知の中身と `userInfo` の検証

- `title`: `subject.title`、`subtitle`: `owner/name`、`body`: `NotificationGrouping.reasonText(reason)` と `<user>@<host>`、`threadIdentifier`: `<host>/<user>`（アカウントでまとまる）、`sound`: `.default`、`identifier`: `<host>/<user>/<threadId>`
- `userInfo`: `host`、`user`、`threadID`、`repository`（`owner/name`）、`url`（`ThreadWebURL.make` の結果の文字列）。`subject.url` などの API の URL は入れない
- `ThreadOpenRequest.init?(userInfo:)`: `host` と `user` を `GhIdentifier.isValidHost` / `isValidUser`、`threadID` を `ThreadID` で検証し、どれかが通らなければ nil（何もしない）。`url` は `https` でホストが `host` と一致し、ユーザー情報もポートも含まないときだけ使い、通らなければ `repository` を `RepositoryName` で検証して `https://<host>/<owner>/<name>` を組み立てる。それも通らなければ nil を返す（ui「通知のスレッドを開く」と同じく、開けなかったスレッドは既読にもしない）

### D8. メニューバーのバッジ

- `MenuBarExtra { … } label: { MenuBarLabel(count:) }` にする。ラベルは `Text("\(Image(systemName: "cat.fill")) 5")` のように画像を埋め込んだ 1 つの `Text` で作る（`MenuBarExtra` のラベルは `HStack` を並べても画像しか出ないことがあるため）。テンプレート画像として描かれ、ライトとダークの両方で他のアイコンと同じ色になる
- 数字は `UnreadBadge.text(for:)`（0 → nil、1〜99 → そのまま、100 以上 → `99+`）。純粋な関数にしてテストする
- 手元の確認で `Text` の埋め込みが崩れたら、`ImageRenderer` で猫と数字をテンプレートの `NSImage` にして渡す（代替案）

### D9. 許可

- `applicationDidFinishLaunching` で `requestAuthorization(options: [.alert, .sound])`。結果は `NotificationPermission.status` に入れ、ポップオーバーの `onAppear` で `authorizationStatus()` を読み直す
- `.denied` のときだけ案内を出す。`.notDetermined` は求めている途中なので出さない。ボタンは `x-apple.systempreferences:com.apple.Notifications-Settings.extension` を開く（固定の文字列で、API の値は入れない）
- 許可が無くても `add` は呼んでよい（macOS が出さないだけ）。`SystemNotifier` は許可の状態で分岐しない

## テストでの差し替え

- ネットワーク: 既存の `FakeHTTPTransport` で `PATCH` のメソッド・URL・ヘッダーを見る。状態コードごとの結果、`ThreadID` の拒否、`307` の拒否をテストする
- ポーラー: 既存の `PollingFakes`（偽のトークン、`sleep`、`now`）で、`markRead` の後の `state`、取得中の既読化（`FakeHTTPTransport` で 1 回目の取得の応答を止めておく）、次の取得に `If-Modified-Since` が付かないこと、失敗したスレッドが戻ることを確かめる
- 通知: `UserNotificationCenter` の偽物（`add` / `remove` / `delivered` を記録）を `SystemNotifier` に渡す。`NotificationTracker` は入力と出力だけでテストする
- `NotificationStore`: 偽の `PollerFactory` と `openURL` の記録で、開く → 既読、保留の既読化、`unreadCount` を確かめる
- `NotificationClickHandler` は `UNNotificationResponse` を作れないので、`userInfo` の検証（`ThreadOpenRequest`）だけをユニットテストし、delegate の配線は手元で確かめる

## セキュリティ

トークンの流れ:

- 取得: 変わらない（`gh auth token` の標準出力から `AccountDiscovery` が取得し、`CredentialStore` に入れる）
- 保持: 変わらない（`CredentialStore` の中だけ）。`AccountPoller.markRead` は取得と同じく、送る直前に `TokenProviding.currentToken` で受け取り、リクエストの組み立てにだけ使う
- 送り先: `GET /notifications` に加えて `PATCH <API ベース>/notifications/threads/<id>`。どちらも `GitHubAPIClient.send` を通り、送る前にオリジン検査をする
- 破棄: 変わらない（アカウントの削除・終了時）。既読化の失敗ではトークンを捨てない

security.md の各項目:

- トークンを型で伏せる・ログに出さない: 既存の `AccessToken` をそのまま使う。既読化のログはパス・ホスト・状態コード（`.private`）だけ
- 通知の本文: タイトル・リポジトリ名・理由・アカウント名だけ。トークンと API の URL を入れない（`userInfo` にも）。テストで、作った通知の中身と `userInfo` にトークンの文字列と API ベース URL が含まれないことを確かめる
- ネットワーク: オリジン検査（`PATCH` にも掛かることをテスト）、HTTPS のみ、リダイレクトの拒否（`307` のテスト）、キャッシュなし、共有ヘッダーにトークンを入れない、は `send` の共有で満たす
- URL を開く: 一覧のクリックは既存の `ThreadWebURL.make`。通知のクリックは `userInfo` を信用せず、ホスト名・ユーザー名・スレッド ID・URL のホストを検証し直す（テストする）
- gh サブプロセス: 触れない
- 永続化: アプリは書かない。通知センターに残る `userInfo` には Web の URL とアカウント名が入るが、トークンも API の URL も入らない（proposal の Impact に書いた）
- Hardened Runtime と entitlement: 通知に entitlement は要らないので変えない

## Risks / Trade-offs

- [ローカルビルド（ad-hoc 署名）で通知の許可が効かない、または再ビルドで許可が外れる] → 手元の確認で確かめ、外れるなら README に「再ビルドの後はシステム設定で許可し直す」と書く。spec は許可が無くても一覧とバッジが動くことを求めているので、機能は壊れない
- [`MenuBarExtra` のラベルに `Text` の画像埋め込みが出ない] → D8 の代替案（`ImageRenderer` のテンプレート画像）に切り替える
- [取り下げは次の取得まで遅れる（Web で既読にしてから最大 5 分と `X-Poll-Interval`）] → 条件なしの取得の間隔（M2 の修正）で上限が決まる。Mewbell で既読にした分はすぐに取り下げる
- [10 ページ（500 件）を超える未読があると、一覧に入らないスレッドの通知が「一覧から消えた」として取り下げられる] → 500 件を超えるのはまれで、取り下げても未読のまま GitHub に残るので受け入れる
- [起動直後に通知をクリックし、トークンを取る前にアカウントが「トークンを取れない」になった] → 既読化は捨てる（spec の MAY）。ページは開く
- [`seen` が実行中に増え続ける] → スレッド ID と日時だけで、アカウントの `reset` で捨てる。長く動かしても数千件程度

## Migration Plan

保存するデータが無いので、移行は要らない。初回の起動で通知の許可を求める。戻すときは前のビルドに戻せばよい（通知センターに残った通知は、クリックしても前のビルドでは何もしない）。
