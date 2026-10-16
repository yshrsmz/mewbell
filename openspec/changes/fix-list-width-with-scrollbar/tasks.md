# Tasks

## 1. 余白の幅の判断

- [x] 1.1 `UI/ListScroller.swift` に `ListScroller.contentWidthLimit(scrollerStyle:listWidth:)` を足す（design D2）。legacy で幅を測った後は「一覧の幅 − スクロールバーの幅」、overlay のときと幅をまだ測っていないときは nil
- [x] 1.2 `MewbellTests/ListScrollerTests.swift` に、legacy・overlay・幅をまだ測っていないときのテストを足し、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/ListScrollerTests` が通り、結果のスイート数が 1 であることを確かめる

## 2. 一覧のスクロール

- [x] 2.1 `NotificationListView` で、一覧の幅を `onGeometryChange` で `@State` に持ち（D1）、スクロールバーの表示のしかたを `@State` に持って `NSScroller.preferredScrollerStyleDidChangeNotification` で読み直し（D3）、`ListScroller.contentWidthLimit` を中身の `.frame(maxWidth:alignment: .leading)` に渡して左に寄せる。`NotificationListView` と `ThreadListActions`、一覧のプレビュー、`HidesScrollIndicatorsWhileAnimating`（`private` のまま）を `UI/NotificationListView.swift` に分ける（D2）。「すべて無効」の後にも古い表示のしかたが残らないよう、一覧の `onAppear` でも読み直す（D3）
- [x] 2.2 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell build` が通ること、`#Preview("Notifications")` の見た目が overlay で変わっていないことを確かめる

## 3. テストと lint

- [x] 3.1 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` を `-only-testing` を付けずに回し、通ることを確かめる
- [x] 3.2 `bash scripts/lint.sh` が通ることを確かめる

## 4. 手元での確認（spec の Scenario ごと）

- [ ] 4.1 システム設定で「スクロールバーを表示」を「常に」にし、`bash scripts/run.sh` で起動する。一覧がポップオーバーに収まらない状態で、スレッドの行の Done を続けて押し、一覧が収まってスクロールバーが消えるときも、次の行のボタンがカーソルの下に出て続けて押せることを確かめる
- [ ] 4.2 同じ設定で、収まっている状態からリポジトリを開いてはみ出させ、すべて既読のボタンと行のボタンの横の位置が変わらず、スクロールバーが右の空きに出ることを確かめる（スクロールバーの幅と空きの幅が合っていることも見る。合わなければ design の Risks のとおり、差の分だけずれる）
- [ ] 4.3 同じ設定で、はみ出している状態でリポジトリを折りたたみ、アニメーションの間もその後も中身の幅が変わらないことを確かめる。「視差効果を減らす」をオンにしても同じであることを確かめる
- [ ] 4.4 「常に」の設定で一覧が収まっている状態でポップオーバーを開き、開いた直後にボタンや件名が横に動いて見えないことを確かめる（design の Risks の最初の 1 フレーム）
- [ ] 4.5 「マウスまたはトラックパッドに応じて自動的に」でトラックパッドだけのとき（または「スクロール時に表示」）、収まっている一覧の右に空きが出ず、`main` のビルドと同じ幅であることを確かめる
- [ ] 4.6 ポップオーバーを開いたまま「スクロール時に表示」から「常に」へ切り替え、空きが付くこと、ポップオーバーの幅が変わらず横にスクロールしないことを確かめる

## 5. 仕上げ

- [ ] 5.1 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build` と同じ Release のビルドが通り、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通り、手元で起動して 4 の確認を終えたことを確かめる

## 6. レビュー（.claude/rules/review-process.md）

- [x] 6.1 別コンテキストの opus サブエージェント（`general-purpose`）で `simplify` を実行し、入った変更を確かめる
- [x] 6.2 別の opus サブエージェントで `code-review` を effort `medium` で実行し、指摘ごとに直す・直さない（理由）を決めて対応する。ロジックの変更を含む修正が多いときは、もう一度 `code-review` を新しいサブエージェントで回す
- [ ] 6.3 PR 本文の Test plan に、simplify と code-review をサブエージェントで実行したこと、指摘の件数と対応を書く
