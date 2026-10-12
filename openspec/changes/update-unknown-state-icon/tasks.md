# Tasks

## 1. 仕様と今の実装の突き合わせ

- [x] 1.1 書き直した Requirement の各 Scenario を、今の `ThreadIcon`（`Mewbell/UI/ThreadEventText.swift`）と `ThreadIconTests` が満たしていることを確かめる。確認: 状態が nil の Pull request・Issue は種類の記号・薄い色（`color == nil`）・種類だけの名前になり、Issue に merged が付いたときは nil のときと同じになる（`fallsBackToTheKindWithoutAMatchingState`）。Issue の nil の名前が「Issue」であることをテストが確かめていなければ、`fallsBackToTheKindWithoutAMatchingState` に足し、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/ThreadIconTests` が通る

## 2. 確認

- [x] 2.1 確認: `pnpm exec openspec validate update-unknown-state-icon --strict` が通る。1.1 でテストを足したときは、`bash scripts/lint.sh`、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルドも通る。表示は変わらないので、手元での起動の確認は要らない。結果: lint、全テスト（416 件）、Debug と Release のビルド、validate が通った

## 3. レビュー

- [x] 3.1 別コンテキストの opus サブエージェントで `simplify` を実行する（`.claude/rules/review-process.md`）。変更を確かめてから取り込む。結果: 変更なし
- [x] 3.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。結果: 7 件。6 件を直した（種類によらない記号にしないことのテスト、spec の言い方、薄い色の状態との関係を design に、proposal と design のテストの記述、`@Test(arguments:)` への書き換え）。1 件（取れたが状態が分からない場合の Scenario）は直さない。理由は PR 本文に書いた
- [x] 3.3 ロジックの変更を含む修正が多ければ、3.2 を新しいサブエージェントでもう一度実行する。結果: 本体のロジックの変更は無く、テストと文書だけなので不要
