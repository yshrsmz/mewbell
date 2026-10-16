# Tasks

## 1. 余白の幅の判断

- [ ] 1.1 `UI/ListScroller.swift` に `ScrollerGutter`（`init(style:overflows:indicatorsHidden:)` と `width`）を足す（design D2）。legacy で収まっているとき・アニメーションで隠しているときはスクロールバーの幅、legacy ではみ出しているときと overlay のときは 0
- [ ] 1.2 `MewbellTests/ScrollerGutterTests.swift` に、spec の Scenario の 4 つの状態（legacy で収まっている、legacy ではみ出している、legacy でアニメーション中にはみ出している、overlay）を引数にしたテストを足し、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/ScrollerGutterTests` が通り、結果のスイート数が 1 であることを確かめる

## 2. 一覧のスクロール

- [ ] 2.1 `HidesScrollIndicatorsWhileAnimating` を `ListScrollerModifier` に改めて `UI/ListScroller.swift` に移す（design D2）。はみ出しを `onScrollGeometryChange` で `@State` に持ち（D1）、スクロールバーの表示のしかたを `@State` に持って `NSScroller.preferredScrollerStyleDidChangeNotification` で読み直し（D3）、`ScrollerGutter` の幅を `.contentMargins(.trailing, _, for: .scrollContent)` に渡す。`scrollIndicators` と `onAppear` での数の破棄は今のまま
- [ ] 2.2 `NotificationListView` の呼び出しを `ListScrollerModifier` に替え、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell build` が通ること、`#Preview("Notifications")` の見た目が overlay で変わっていないことを確かめる

## 3. テストと lint

- [ ] 3.1 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` を `-only-testing` を付けずに回し、通ることを確かめる
- [ ] 3.2 `bash scripts/lint.sh` が通ることを確かめる

## 4. 手元での確認（spec の Scenario ごと）

- [ ] 4.1 システム設定で「スクロールバーを表示」を「常に」にし、`bash scripts/run.sh` で起動する。一覧がポップオーバーに収まらない状態で、スレッドの行の Done を続けて押し、一覧が収まってスクロールバーが消えるときも、次の行のボタンがカーソルの下に出て続けて押せることを確かめる
- [ ] 4.2 同じ設定で、収まっている状態からリポジトリを開いてはみ出させ、すべて既読のボタンと行のボタンの横の位置が変わらず、スクロールバーが右の空きに出ることを確かめる（スクロールバーの幅と空きの幅が合っていることも見る。合わなければ design D2 の Risks のとおり測る形に改める）
- [ ] 4.3 同じ設定で、はみ出している状態でリポジトリを折りたたみ、アニメーションの間もその後も中身の幅が変わらないことを確かめる
- [ ] 4.4 「マウスまたはトラックパッドに応じて自動的に」でトラックパッドだけのとき（または「スクロール時に表示」）、収まっている一覧の右に空きが出ず、`main` のビルドと同じ幅であることを確かめる
- [ ] 4.5 ポップオーバーを開いたまま「スクロール時に表示」から「常に」へ切り替え、空きが付くこと、ポップオーバーの幅が変わらず横にスクロールしないことを確かめる

## 5. 仕上げ

- [ ] 5.1 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build` と同じ Release のビルドが通り、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通り、手元で起動して 4 の確認を終えたことを確かめる

## 6. レビュー（.claude/rules/review-process.md）

- [ ] 6.1 別コンテキストの opus サブエージェント（`general-purpose`）で `simplify` を実行し、入った変更を確かめる
- [ ] 6.2 別の opus サブエージェントで `code-review` を effort `medium` で実行し、指摘ごとに直す・直さない（理由）を決めて対応する。ロジックの変更を含む修正が多いときは、もう一度 `code-review` を新しいサブエージェントで回す
- [ ] 6.3 PR 本文の Test plan に、simplify と code-review をサブエージェントで実行したこと、指摘の件数と対応を書く
