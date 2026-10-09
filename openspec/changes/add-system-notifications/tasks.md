# Tasks

## 1. 既読化のリクエスト（GitHubAPI）

- [x] 1.1 `ThreadID` の検証（1〜20 桁の ASCII 数字）を足す。確認: 空文字・21 桁・`12a`・`../1`・全角数字・`-1` を拒否し、`1` と 20 桁を通すテストが通る
- [x] 1.2 `GitHubAPIClient.send` に HTTP メソッドの引数を足し、`markThreadRead(endpoints:token:threadID:)` と `MarkReadResult` を実装する（D3）。確認: `GitHubAPIClientTests` に次を足して通す: (a) `PATCH https://api.github.com/notifications/threads/123` が `Authorization`・`Accept`・`X-GitHub-Api-Version`・`User-Agent` 付きで送られる、(b) GHES では `https://<host>/api/v3/notifications/threads/77`、(c) `205`・`304`・`404` は `.read`、`401` は `.unauthorized`、`403`（`X-RateLimit-Remaining: 0`）は `.rateLimited`、`422` と `500` は `.failed`、(d) `307` はリダイレクトとして失敗、(e) 数字でない ID では何も送らない、(f) 既存の `GET` のテストが変わらず通る

## 2. ポーラーでの既読化（Polling）

- [x] 2.1 `AccountPoller.markRead(threadID:)` を実装する。取得に連番を振り、`hidden` で既読化より前に始めた取得の結果からスレッドを取り除き、既読化の後に始めた取得の `200` で隠すのをやめる。既読化の後に条件なしの印を立てる。止まっている・トークンが無いときは送らずに印だけ立てる（D4）。確認: `PollingTests` に次を足して通す: (a) `markRead` の直後に `state.threads` から外れて `onUpdate` が呼ばれる、(b) `PATCH` が送られる、(c) 次の取得に `If-Modified-Since` が付かない、(d) 既読化が失敗し次の取得で返ったスレッドは一覧に戻る、(e) 取得の応答を止めている間に `markRead` し、その取得が同じスレッドを返しても戻らない、(f) 既読化は取得の待ち時間を変えない（`sleep` に渡る値が同じ）
- [x] 2.2 `NotificationStore` に `open(_:in:)`、`openFromNotification(_:)`、保留の既読化（`pendingReads`）、`unreadCount` を足し、`openURL` を注入できるようにする（D5）。確認: 偽の `PollerFactory` と `openURL` の記録で次のテストが通る: (a) `open` で URL が開かれ、`feeds` からすぐ外れ、ポーラーの `markRead` が呼ばれる、(b) URL を組み立てられないスレッドでは何も開かず既読にもしない、(c) ポーラーが無いアカウントの `openFromNotification` は保留され、`sync` でポーラーを作るときに `start` より前に `markRead` される、(d) アカウントが一覧に無い・トークンを取れない状態の `sync` で保留が捨てられる、(e) `unreadCount` が `feeds` の合計で、止まったアカウントは 0 件

## 3. macOS の通知（Notifications）

- [x] 3.1 `NotificationTracker` を実装する（D2）。確認: 次のテストが通る: (a) 基準では何も出さない、(b) 新しいスレッドを出す、(c) `updated_at` が進んだスレッドを出し、同じものは出さない、(d) 消えたスレッドを取り下げる、(e) 消えて同じ `updated_at` で戻ったスレッドは出さない、(f) `reset` の後はまた基準から、(g) 2 つのアカウントの結果が混ざらない
- [x] 3.2 `ThreadNotificationContent` と `ThreadOpenRequest` を実装する（D7）。確認: 次のテストが通る: (a) タイトル・サブタイトル・本文・`threadIdentifier`・識別子 `<host>/<user>/<threadId>` が spec どおり、(b) 中身と `userInfo` のどこにもトークンの文字列（`test-token`）と API ベース URL が入らない、(c) `userInfo` の検証で、不正なホスト名・`-` で始まるユーザー名・数字でないスレッド ID は nil、(d) URL のホストが違う・`http`・ポート付き・ユーザー情報付きなら `https://<host>/<owner>/<name>` に置き換わり、`repository` も不正なら nil
- [x] 3.3 `UserNotificationCenter`（protocol）、`LiveUserNotificationCenter`、`SystemNotifier`（直列のキュー、アカウント単位と全体の取り下げ、前回の実行の掃除）を実装し、`NotificationStore.apply` と `sync` から `ThreadNotifying` に渡す（D2、D6）。確認: 偽の `UserNotificationCenter` で次のテストが通る: (a) `.loading` → `.loaded` では `add` されず、前回の実行の通知のうち一覧に無いものが `remove` される、(b) 次の取得の新着で `add` される、(c) `open` で既読にしたスレッドが `remove` される、(d) `.retrying` では何も起きない、(e) `.unauthorized` とアカウントの削除で、そのアカウントの前方一致の通知だけが `remove` される、(f) 全体が「gh が見つからない」になるとすべて `remove` される
- [x] 3.4 `NotificationClickHandler` と `NotificationPermission` を実装し、`AppDelegate` で組み立てる（delegate は `init` で設定、許可は `applicationDidFinishLaunching` で求める、テストのホストとプレビューでは何もしない）（D6、D9）。確認: ユニットテストのホストで通知の許可のダイアログが出ず、既存のテストが通る。delegate の配線は 5.3 の手元確認で見る

## 4. UI

- [x] 4.1 `AccountSectionView` のクリックを `NotificationStore.open` に渡し、`NotificationPermissionBanner`（`.denied` のときだけ、システム設定を開くボタン付き）をポップオーバーの一覧の上に出す。ポップオーバーの `onAppear` で許可の状態を読み直す。プレビューに案内ありの状態を足す。確認: プレビューで案内と一覧が並んで表示される
- [x] 4.2 `UnreadBadge.text(for:)` と `MenuBarExtra` のラベルを実装する（D8）。確認: `0` → nil、`1` → `1`、`99` → `99`、`100` → `99+` のテストが通る。ラベルの見た目は 5.3 で確かめ、崩れたら `ImageRenderer` の代替案に切り替える
- [x] 4.3 README の現状の説明を M3 の内容（macOS の通知、クリックで開いて既読、未読バッジ）に更新し、ad-hoc 署名のローカルビルドで通知の許可について分かったことがあれば書く。CLAUDE.md の約束と食い違いが無いかを読む。確認: 差分を読む

## 5. 最終確認

- [x] 5.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [x] 5.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 5.3 手元で起動して確認した: (a) 初回起動で許可のダイアログが出て、起動直後の未読は通知されない、(b) メニューバーに猫と未読の合計が出る（ライトとダーク）、(c) 自分宛てに Issue のコメントなどで新着を作ると、次の取得で 1 スレッド 1 通知が出る、(d) 通知をクリックするとブラウザで開き、一覧・バッジ・通知センターから消え、Web でも既読になっている、(e) 一覧のクリックでも同じ、(f) Web で既読にしたスレッドの通知が次の条件なしの取得で消える、(g) 終了中に通知をクリックすると起動して開き、既読になる、(h) システム設定で通知を切ると、ポップオーバーに案内が出る。`log show` でトークンとレスポンスボディが出ていないことも見る

## 6. 別コンテキストでのレビュー

- [ ] 6.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 6.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 6.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認を PR 本文に書いた
