# Tasks

## 1. 状態が分からないときの記号

- [ ] 1.1 `ThreadIcon` の `kindSymbol(_:)` を `fallbackSymbol(_:)` に改め、Pull request に `arrow.triangle.branch`、Issue に `circle` を返すようにする。doc に、状態を持たない種類ではいつも、Pull request と Issue では状態が分からないときに使う記号だと書く（design D2）。確認: `git grep kindSymbol` が `Mewbell/` と `MewbellTests/` で何も返さない。状態のある記号・色と VoiceOver の名前は変わっていない
- [ ] 1.2 `ThreadIconTests.distinguishesStatesByShape` の Pull request と Issue の記号の集まりに、状態が nil のアイコンを加える（design D3）。確認: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/ThreadIconTests -only-testing:MewbellTests/IconColumnTests` が通る。1.1 の前の記号に戻すと `distinguishesStatesByShape` が落ちる

## 2. 確認

- [ ] 2.1 ビルドとテストが通ることを確かめる。確認: `bash scripts/format.sh` の後に `bash scripts/lint.sh`、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルド、`pnpm exec openspec validate update-unknown-state-icon --strict` が通る
- [ ] 2.2 `bash scripts/run.sh` で起動し、手元のポップオーバーで確かめる（ユーザーが行う）。確認: 状態が分からない Pull request・Issue の行のアイコンが、開いている行のアイコンと形で見分けられ、ライトとダークのどちらでも欠けずに列の中央に出る。VoiceOver で、状態が分からない行のアイコンが「Pull request」「Issue」と読まれる

## 3. レビュー

- [ ] 3.1 別コンテキストの opus サブエージェントで `simplify` を実行する（`.claude/rules/review-process.md`）。変更を確かめてから取り込み、テストが通ることを確かめる
- [ ] 3.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く
- [ ] 3.3 ロジックの変更を含む修正が多ければ、3.2 を新しいサブエージェントでもう一度実行する
