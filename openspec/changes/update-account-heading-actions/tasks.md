# Tasks

## 1. 記号の枠の共有

- [ ] 1.1 `ListLayout.swift` に `ListLayout.actionIconSize`（22）と `ActionIcon`（記号をその四方の枠の中央に置く View）を足し、`HoverActionButtons.icon(_:)` と `iconSize` を消して、`rowSize` を `ListLayout.actionIconSize` から計算する。スレッドの行とリポジトリの見出しは `ActionIcon` を使う（design D1）。行とリポジトリの見出しのボタンの見た目が変わらないことは 4.5 で確かめる

## 2. アカウントの見出しのボタン

- [ ] 2.1 新しいファイル `UI/AccountHeadingButtons.swift` に、`ThreadRow.swift` から `MarkAllReadButton` と `MarkAllReadLabels` を移す。`MarkAllReadButton` は `@State` をやめて `confirming: Binding<Bool>` を受け取り、記号を `ActionIcon("envelope.open")` にし、`outset: 3` を外す（design D2・D3・D4）。プレビューは `.constant` で渡す。`MarkAllReadLabelsTests` が通ることを確かめる
- [ ] 2.2 `ConfirmingButton` の `outset` の引数を消す（design D2）
- [ ] 2.3 同じファイルに `MarkAllDoneLabels`（`Mark all as done`、`Mark N as done?`、確認中かどうかで変わるツールチップと読み上げ）と `MarkAllDoneButton`（`ActionIcon("checkmark")`、`target` はスレッド ID の並び）を足す（design D4）。`MarkAllDoneLabelsTests` を足す
- [ ] 2.4 `OpenWebNotificationsButton` の記号を `ActionIcon("arrow.up.forward")` にし、`HoverHighlightButtonStyle()` にする（design D2）
- [ ] 2.5 `AccountSectionView` に `@State private var confirming: AccountHeadingAction?` を置き、見出しの右端に Web の通知一覧・すべて既読・すべて Done を `HStack(spacing: 2)` で並べる。すべて Done は、すべて既読を出す条件で出し、一覧が 1 件以上のときだけ押せるようにする（design D2・D3。spec「すべて Done のボタン」「アカウントの見出しの確認の表示」）。`ThreadRow.swift` のプレビューで使っていた `MarkAllReadButton` の並びを、新しいファイルのプレビューに移し、すべて Done の各状態を足す

## 3. すべて Done の経路

- [ ] 3.1 `NotificationStore.markAllDone(in:)` を足し、`feeds[account]` のスレッドを `updatedAt` の新しい順に並べ直して Done の配列にし、`perform(_:in:)` に渡す（design D5）。`NotificationStoreActionTests` に、一覧のスレッドがすべて外れてポーラーに Done の配列が新しい順で 1 回渡ること（一覧の並びが新しい順でないときも）、一覧が空なら何もしないこと、ほかのアカウントの一覧が変わらないことのテストを足す
- [ ] 3.2 `ThreadListActions` に `markAllDone: (AccountID) -> Void` を足し、`.none` と `MenuBarContentView` のつなぎ込みを更新する（design D5）

## 4. 手元での確認（spec の Scenario ごと）

- [ ] 4.1 `bash scripts/run.sh` で起動し、アカウントの見出しに Web の通知一覧（囲みの無い矢印）、すべて既読（封筒）、すべて Done（チェック）がこの順に出て、記号と塗りの大きさがリポジトリの見出しの「既読にする」「Done にする」と同じであること、見出しの高さが 24pt のまま変わらないことを、変更前の画面と見比べて確かめる
- [ ] 4.2 すべて Done を 1 回押すと `Mark N as done?` になり、5 秒で元に戻ること、5 秒以内にもう一度押すと一覧が空になり、Web の受信箱からも消えることを確かめる。すべて既読の確認中にすべて Done を押すと、すべて既読が元に戻ることを確かめる
- [ ] 4.3 見出しのボタンの手前の空いたところにマウスを載せると、山形から Web の通知一覧のボタンの手前まで塗りが出て、押すと折りたたまれ、どのボタンも確認の表示にならないことを確かめる。長いユーザー名のアカウントで確認の表示にしたとき、ホスト名から省略され、確認の文が省略されないことを確かめる
- [ ] 4.4 VoiceOver で、アカウントの見出しの 3 つのボタンが読まれ、すべて Done のラベルと確認中のラベルが読まれることを確かめる
- [ ] 4.5 スレッドの行とリポジトリの見出しのボタンの見た目と、すべて既読の 2 段階の確認が `main` と同じに動くことを確かめる（1.1・2.1 の移動の確認）

## 5. 仕上げ

- [ ] 5.1 `bash scripts/lint.sh` が通ることを確かめる
- [ ] 5.2 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build` と同じ Release のビルドが通り、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通り、手元で起動して 4 の確認を終えたことを確かめる

## 6. レビュー（.claude/rules/review-process.md）

- [ ] 6.1 別コンテキストの opus サブエージェント（`general-purpose`）で `simplify` を実行し、入った変更を確かめる
- [ ] 6.2 別の opus サブエージェントで `code-review` を effort `medium` で実行し、指摘ごとに直す・直さない（理由）を決めて対応する。ロジックの変更を含む修正が多いときは、もう一度 `code-review` を新しいサブエージェントで回す
- [ ] 6.3 PR 本文の Test plan に、simplify と code-review をサブエージェントで実行したこと、指摘の件数と対応を書く。PR 本文に「セキュリティ上の確認」の節を設ける（トークンを付けたリクエストの数が増えるため）
