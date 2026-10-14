# Tasks

## 1. ボタンのスタイル

- [x] 1.1 `ReloadButton.swift` の `PressableIconButtonStyle` を `UI/HoverHighlightButtonStyle.swift` の `HoverHighlightButtonStyle` に改名して移し、塗りの内側の余白（既定 4）を引数にする。押せないときはラベルに `.foregroundStyle(.tertiary)` を付ける（design D1・D2）。`ReloadButton` と `OpenSettingsButton` の呼び出しを直し、`#Preview` で歯車と再読み込みの見た目が変わっていないことを確かめる
- [x] 1.2 `project.xcproj` に新しいファイルが要るかを確かめ（フォルダの同期で入るなら不要）、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell build` が通ることを確かめる

## 2. アイコンのボタン

- [x] 2.1 `OpenWebNotificationsButton` と `CommandRow` のコピーのボタンを `HoverHighlightButtonStyle(padding: 0, outset: 4)` にする（枠を広げると見出しの高さが変わるため。design D1）。プレビューでアイコンの色と大きさが `.borderless` のときと同じに見えることを確かめる
- [ ] 2.2 `MarkAllReadButton` を `HoverHighlightButtonStyle(padding: 0, outset: 4)` にし、確認の文の `Text` に `.foregroundStyle(.tint)` を付ける（design D2）。`#Preview("Mark all as read")` で、確認の文がアクセントカラーのままであること、`isEnabled: false` のアイコンが薄く出ることを確かめる
- [x] 2.3 `ThreadActionButtons` の既読・Done を `HoverHighlightButtonStyle(padding: 0)` にする。22pt 四方の枠と `ThreadActionButtons.size` が変わらないことをコードで確かめる

## 3. 行と見出し

- [x] 3.1 `ThreadRow` の `.mask` を `Button` のラベルの `HStack` に付け替え、行のボタンを `HoverHighlightButtonStyle(padding: 0, isHovering: isHovering)` にする（design D3）。`#Preview("Thread row hovered")` で、件名がボタンの下で消えたまま、行の塗りがボタンの下にも出ることを確かめる
- [ ] 3.2 `DisclosureButton` のラベルに `.frame(maxWidth: .infinity, alignment: .leading)` を `.contentShape` の前に付け、ボタンを `HoverHighlightButtonStyle(padding: 0)` にする（design D4）。`RepositoryGroupView` の `#Preview("Collapsed")` で、長いホスト名の `grace` の見出しが今と同じに省略されること、見出しの高さが変わらないことを確かめる
- [x] 3.3 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` を `-only-testing` を付けずに回し、寸法を測るテスト（`IconColumnTests`、`AccountDisclosureTests` など）を含めて通ることを確かめる

## 4. 手元での確認（spec の Scenario ごと）

- [x] 4.1 `bash scripts/run.sh` で起動し、スレッドの行にマウスを載せると行の全体に塗りが出て、件名の折り返しと行の高さが変わらず、外すと消えることを確かめる
- [x] 4.2 行の「Done にする」にマウスを移すと、行の塗りが出たまま、Done のアイコンの後ろにだけ塗りが重なることを確かめる
- [x] 4.3 アカウントの見出しの Web の通知一覧とすべて既読のボタンに、載せたボタンにだけ塗りが出ること、すべて既読の確認の表示（`Mark N as read?`）にも塗りが出て文がアクセントカラーのままであることを確かめる
- [ ] 4.4 未読が 0 件のアカウントのすべて既読のボタンと、再読み込み中の再読み込みのボタンに、塗りが出ないことを確かめる
- [x] 4.5 リポジトリの見出しのリポジトリ名より右の空いたところで塗りが出て、押すと折りたたまれることを確かめる
- [x] 4.6 アカウントの見出しの空いたところで、山形から Web の通知一覧のボタンの手前まで塗りが出て、押すと開閉し、すべて既読が確認の表示にならないことを確かめる
- [ ] 4.7 トークンを取れないアカウント（または取得前）の見出しに塗りが出ないこと、Quit と案内の Open Settings… が標準の見た目のままであること、コマンドの行のコピーのボタンに塗りが出ることを確かめる
- [ ] 4.8 Done で行が消えたとき、次の行の塗りがマウスを動かせば出ることを確かめる（design の Risks）
- [ ] 4.9 ライトとダーク、「コントラストを上げる」「透明度を下げる」をオンにした状態で、塗りが見えて文字が読めることを確かめる

## 5. 仕上げ

- [x] 5.1 `bash scripts/lint.sh` が通ることを確かめる
- [ ] 5.2 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build` と同じ Release のビルドが通り、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通り、手元で起動して 4 の確認を終えたことを確かめる

## 6. レビュー（.claude/rules/review-process.md）

- [ ] 6.1 別コンテキストの opus サブエージェント（`general-purpose`）で `simplify` を実行し、入った変更を確かめる
- [ ] 6.2 別の opus サブエージェントで `code-review` を effort `medium` で実行し、指摘ごとに直す・直さない（理由）を決めて対応する。ロジックの変更を含む修正が多いときは、もう一度 `code-review` を新しいサブエージェントで回す
- [ ] 6.3 PR 本文の Test plan に、simplify と code-review をサブエージェントで実行したこと、指摘の件数と対応を書く
