# Tasks

## 1. 見出しの高さ

- [x] 1.1 `ListLayout` に `headingHeight`（24）を足し、`DisclosureButton` の畳めるときのラベルの枠に `minHeight`、畳めないときの `HStack` に `.frame(minHeight:)` を付ける（design D1・D2）。`RepositoryGroupView` の `#Preview("Collapsed")` で、見出しが上下に広がり、長いホスト名の `grace` の見出しの省略の仕方が変わらないことを確かめる
- [x] 1.2 `MewbellTests/` に、`.headline` と `.subheadline.weight(.semibold)` の中身で、畳めるときと畳めないときの `DisclosureButton` の `fittingSize` の高さが `ListLayout.headingHeight` であることを `NSHostingView` で測るテストを足す（design D4）。1.1 の下限を外すと落ちることを一度確かめてから戻す。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/<スイートの型名>` で、結果のスイート数が 1 であることも確かめる
- [x] 1.3 スキル `update-architecture-doc` の手順で、`docs/architecture.md` の A16 に押せる範囲の大きさ（縦横 20pt 以上、見出しは `ListLayout.headingHeight`）を書き足す（design D5）。ポップオーバーのアイコンのボタンの押せる範囲が 20pt 以上かを手元で確かめ、満たさないものがあれば「既知の逸脱」に行を足す（コピーのボタンのコピーした後が 19pt だったので、design D5 のとおり枠の高さを決めて直した）。`bash scripts/check-architecture.sh` が通ることを確かめる
- [x] 1.4 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` を `-only-testing` を付けずに回し、寸法を測る既存のテスト（`IconColumnTests` など）を含めて通ることを確かめる

## 2. 手元での確認（spec の Scenario ごと）

- [x] 2.1 `bash scripts/run.sh` で起動し、リポジトリの見出しの文字より少し上（約 3pt）を押すと折りたたまれることを確かめる
- [x] 2.2 アカウントの見出しにマウスを載せると、塗りの高さが約 24pt で、山形・トークンの状態・ユーザー名が塗りの縦の中央に出ること、Web の通知一覧とすべて既読のボタンの大きさと塗りが `main` のビルドと変わらないことを確かめる
- [x] 2.3 起動直後の最初の取得中（畳めない見出し）から取得ができて畳めるようになるとき、見出しの高さと下の表示の位置が変わらないことを確かめる。トークンを取れないアカウント（設定で gh の設定ディレクトリを空のものにするなど）の見出しの高さもほかと同じであることを確かめる
- [x] 2.4 スレッドの行の高さと、ポップオーバーの上の見出し（歯車・再読み込み）の大きさが変わらないこと、リポジトリが多いアカウントで一覧の伸び方とグループの間隔が不自然でないことを確かめる（design の Risks）

## 3. 仕上げ

- [x] 3.1 `bash scripts/lint.sh` が通ることを確かめる
- [x] 3.2 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build` と同じ Release のビルドが通り、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通り、手元で起動して 2 の確認を終えたことを確かめる

## 4. レビュー（.claude/rules/review-process.md）

- [x] 4.1 別コンテキストの opus サブエージェント（`general-purpose`）で `simplify` を実行し、入った変更を確かめる
- [x] 4.2 別の opus サブエージェントで `code-review` を effort `medium` で実行し、指摘ごとに直す・直さない（理由）を決めて対応する。ロジックの変更を含む修正が多いときは、もう一度 `code-review` を新しいサブエージェントで回す
- [x] 4.3 PR 本文の Test plan に、simplify と code-review をサブエージェントで実行したこと、指摘の件数と対応を書く
