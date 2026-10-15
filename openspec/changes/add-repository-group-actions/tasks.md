## 1. ポーラーと store のグループの操作

- [x] 1.1 `AccountPoller.perform(_:)` を `perform(_ actions: [ThreadAction])` に変え、design D1 の順（すべて隠して外す → トークンを 1 回待つ → 1 件ずつ送り、そのたびに `endRequest` と `unconditionalRequested = true` → `401`・レート制限で残りを送らない → 送らなかった分の `endRequest` と `unconditionalRequested` → 最後の失敗を 1 回だけ記録）にする。1 件の操作の呼び出し元は要素 1 つの配列で呼ぶ。既存のテストの呼び出しを要素 1 つの配列に変えるだけで、`ThreadActionPollingTests`・`MarkReadPollingTests`・`PollingDiagnosticsTests` が通ることを確かめる
- [x] 1.2 ポーラーのテストを足す（design D7）: 3 件の Done で、`pausedMethod` で最初の `DELETE` を止めている間に 2 つ目が送られていないこと／最初が `401` かレート制限の `403` なら 2 つ目と 3 つ目が送られず、知らせる失敗が 1 つで、その後に送った取得の `200` で 3 件が一覧に戻ること／`500` が 2 件続いても 3 件目が送られ、知らせる失敗が 1 つであること／1 件目の結果が出た後、2 件目を止めている間に始まった取得が `If-Modified-Since` を付けずに送られること／トークンが無いときはリクエストが送られず `noToken` が 1 つ記録されること／送っている間の取得で届いた同じリポジトリの新しいスレッドは一覧に出ること。`-only-testing` にはスイートの型名を渡し、結果のスイート数を確かめる
- [x] 1.3 `NotificationStore` の `perform(_:in:)` を配列を受け取る形にし、`markRead(_ group: RepositoryGroup, in:)` と `markDone(_ group: RepositoryGroup, in:)` を足す（design D2）。対象が 0 件なら何もしない。`NotificationStoreActionTests` に、グループの操作で対象のスレッドがすべて `feeds` からすぐ消え、ほかのリポジトリのスレッドは残り、ポーラーに 1 回だけ渡ることを確かめるテストを足す

## 2. 確認のボタンとホバーのボタンの共有

- [x] 2.1 `UI/ConfirmingButton.swift` に `ConfirmingButton` を作り、`MarkAllReadButton` の確認の処理（5 秒、`isEnabled`・件数・最新のスレッドの変化、`onDisappear` で解く）を移す（design D3）。`MarkAllReadButton` は `@State confirming` を持って渡す形にする。`ThreadRow.swift` の `#Preview("Mark all as read")` の見た目が変わらないこと、`MarkAllReadLabelsTests` が通ることを確かめる プレビューは Xcode を開いていないので描けず、見た目は 4.6 で起動したアプリで確かめる
- [x] 2.2 `ThreadActionButtons` を `UI/HoverActionButtons.swift` の `HoverActionButtons` に移し、「Done にする」の位置にビューを受け取る形にする。行の件名のマスクは今の固定の幅のままにする（design D4）。`ThreadRow` の `#Preview("Thread row hovered")` で、行のボタンの大きさ・位置・件名の消え方が `main` と変わらないことを確かめる プレビューは Xcode を開いていないので描けず、見た目は 4.6 で起動したアプリで確かめる
- [x] 2.3 `DisclosureButton` に `isHovering: Bool?`（既定 nil）を足し、`HoverHighlightButtonStyle(isHovering:)` に渡す（design D5）。アカウントの見出しの呼び出しは変えない。`AccountDisclosureTests` と寸法のテスト（見出しの高さ）が通ることを確かめる

## 3. リポジトリの見出しの操作

- [x] 3.1 `RepositoryActionLabels` を作り、ツールチップ・アクセシビリティのラベル・確認の文（`Mark N as done?`、リポジトリ名入りのラベル）を決める（design D6）。単体テストを足す
- [x] 3.2 `ThreadListActions` に `markGroupRead` と `markGroupDone` を足し、`MenuBarContentView` で `NotificationStore` につなぐ。`.none` も更新する（design D2）
- [x] 3.3 `RepositoryGroupView` に、見出しのホバーの状態と Done の確認の状態（`@State`）を持たせ、マウスを載せている間か確認中だけ `HoverActionButtons`（既読は即時、Done は `ConfirmingButton`）を `overlay(alignment: .trailing)` で重ね、ボタンを出している間は見出しの中身の右に、`onGeometryChange` で測ったボタンの並びの幅の余白を空ける（design D4。リポジトリ名は中央が省略され、件数は消えない）。見出しに `contextMenu`（「Mark All as Read」「Mark All as Done」）と `accessibilityAction(named:)` を付け、Done はどちらも確認の表示にするだけにする（design D5）。`#Preview("Repository actions")` を足す。プレビューは Xcode を開いていないので描けず、見た目は 4.1・4.6 で起動したアプリで確かめる

## 4. 手元での確認（spec の Scenario ごと）

- [ ] 4.1 `bash scripts/run.sh` で起動し、リポジトリの見出しにマウスを載せると右端に 2 つのボタンが出て、外すと消えること、見出しの高さとリポジトリ名の位置が変わらないこと、ボタンに載せている間も見出しの塗りが出続け、ボタンの塗りが重なることを確かめる。長い名前のリポジトリを折りたたんだ見出しで、マウスを載せたときと確認の表示のときに、名前がボタンの手前で中央を省略され、件数が出たままで、省略した名前のツールチップが出ることを確かめる
- [ ] 4.2 「既読にする」でグループがすぐ消えてブラウザが開かず、見出しが折りたたまれないこと、Web の通知一覧で該当のスレッドが既読になっていることを確かめる
- [ ] 4.3 「Done にする」を 1 回押すと `Mark N as done?` になり、マウスを外しても出たままで、5 秒で元に戻ること、5 秒以内にもう一度押すとグループが消えて Web の受信箱からも消えることを確かめる。ほかのグループとアカウントのすべて既読のボタンが確認の表示にならないことも確かめる
- [ ] 4.4 見出しの右クリックで「Mark All as Read」はすぐ既読になり、「Mark All as Done」は見出しが確認の表示になるだけであることを確かめる。折りたたんだグループでも同じに動くことを確かめる
- [ ] 4.5 VoiceOver で、見出しの操作（アクション）に既読と Done が出て、ラベルにリポジトリ名が読まれること、Done を選ぶと確認のボタンが見出しの次に読まれ、それを押すと Done になることを確かめる（design の Risks）
- [ ] 4.6 スレッドの行のホバーのボタンの見た目と、アカウントのすべて既読の 2 段階の確認が `main` と同じに動くことを確かめる（2.1・2.2 の移動の確認）

## 5. 仕上げ

- [x] 5.1 `bash scripts/lint.sh` が通ることを確かめる
- [ ] 5.2 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build` と同じ Release のビルドが通り、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通り、手元で起動して 4 の確認を終えたことを確かめる

## 6. レビュー（.claude/rules/review-process.md）

- [ ] 6.1 別コンテキストの opus サブエージェント（`general-purpose`）で `simplify` を実行し、入った変更を確かめる
- [ ] 6.2 別の opus サブエージェントで `code-review` を effort `medium` で実行し、指摘ごとに直す・直さない（理由）を決めて対応する。ロジックの変更を含む修正が多いときは、もう一度 `code-review` を新しいサブエージェントで回す
- [ ] 6.3 PR 本文の Test plan に、simplify と code-review をサブエージェントで実行したこと、指摘の件数と対応を書く。PR 本文に「セキュリティ上の確認」の節を設ける（トークンを付けたリクエストの数が増えるため）
