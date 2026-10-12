# Tasks

## 1. アイコンの列

- [x] 1.1 `ListLayout.chevronWidth`（16pt）を `ListLayout.iconColumnWidth`（24pt）に改名し、呼び出し側（`ThreadRow`、`DisclosureChevron`、`AccountSectionView` の `tokenIcon`）の名前を差し替える。`contentIndent` は今の式のままにする。「山形の幅」と書いていたドキュメントコメントを、山形・トークンの状態・スレッドの行の種類のアイコンを置く列の説明に直す（design D2）。確認: `git grep chevronWidth` が `Mewbell/` と `MewbellTests/` で何も返さない。書体・記号・`ThreadIcon`・View の構造は変わっていない

## 2. テスト

- [x] 2.1 `MewbellTests/IconColumnTests.swift` を足す（design D3）。スレッドの行の種類と状態（nil を含む）のすべての組の記号、トークンの状態の記号、山形を、View と同じ書体で、倍率 1 と 2 の `fittingSize` で測り、列の幅に収まることを確かめる。種類と状態の一覧の隣に、`default` の無い網羅的な `switch` を置く。確認: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/IconColumnTests` が通る
- [x] 2.2 テストが不具合を拾えることを確かめる。確認: 列を一時的に 16pt にすると落ち、22pt にすると倍率 1 の Discussion で落ち、24pt に戻すと通る。結果: 16pt では `bubble.left.and.bubble.right`（倍率 1 で 23×17pt、倍率 2 で 22×17pt）、`point.3.connected.trianglepath.dotted`（18×14pt、17×14pt）、`tag`（倍率 1 と 2 で 17×17pt）、`exclamationmark.triangle.fill`（倍率 2 で 17×15pt）で落ちた。22pt では `bubble.left.and.bubble.right`（倍率 1 で 23×17pt）だけで落ちた。24pt に戻して通った

## 3. 確認

- [x] 3.1 ビルドとテストが通ることを確かめる。確認: `bash scripts/format.sh` の後に `bash scripts/lint.sh`、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルド、`npx --no-install openspec validate fix-thread-icon-column --strict` が通る
- [x] 3.2 `bash scripts/run.sh` で起動し、手元のポップオーバーで確かめる（ユーザーが行う）。確認: Discussion のスレッドの行の種類のアイコンが、倍率 1 の画面でも、行にマウスを載せているときも欠けずに出る。スレッドの行の種類のアイコン、見出しの山形、トークンの状態のアイコンが同じ幅の列に揃う。長い件名と長いホスト名が、決まりどおりに省略される。結果: ユーザーが手元の画面で確かめ、問題なし（倍率 1 の画面は IconColumnTests で確かめている）

## 4. レビュー

- [ ] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する（`.claude/rules/review-process.md`）。変更を確かめてから取り込み、テストが通ることを確かめる
- [ ] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く
- [ ] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する
