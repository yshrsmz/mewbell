# Tasks

## 1. トークンの状態の値型

- [x] 1.1 `Mewbell/UI/TokenStateIcon.swift` に `TokenStateIcon` を置く（design D1）。`TokenState` と `FeedPhase?` から記号（取得中は nil）・色（nil なら薄い色）・名前を決める。名前は `Getting token`、`Ready`、`Stopped`、`No token`、`Disabled`。記号と色は今の `tokenIcon` と同じにする。確認: ビルドが通る
- [x] 1.2 `MewbellTests/ThreadPresentationTests.swift` に `TokenStateIconTests` を足す（design D4）。状態ごとの名前、「止まっている」と「トークンを取れない」が記号と色は同じで名前が違うこと、取得中だけ記号が nil であること、止まっていない取得の状態と取得の状態が無いときは `Ready` であることを確かめる。確認: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/TokenStateIconTests` が通る

## 2. 見出しの表示とテスト

- [x] 2.1 `AccountSectionView` の `tokenIcon` を `TokenStateIcon` から作る形にし、`.help` と `.accessibilityLabel` を分岐の外で 1 回だけ付ける（design D2）。色の nil は `ThreadRow` と同じ書き方で `.secondary` にする。確認: `git grep -n '\.help("\(Stopped\|Ready\|No token\|Disabled\)")' Mewbell/` が何も返さない。プレビュー（`Notifications`、`Empty and loading`）で記号・色・配置が main と変わらない。結果: `git grep` は何も返さない。記号と色の値は main の分岐と同じ。Xcode でワークスペースを開いていなかったのでプレビューは描かず、見た目は 3.2 の起動確認で確かめる
- [x] 2.2 `IconColumnTests.fitsTheTokenIcon` を、記号名の一覧の代わりに `TokenStateIcon` から記号を集める形にする（design D3）。`TokenState` の一覧の隣に `default` の無い網羅的な `switch` を置く。確認: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/IconColumnTests` が通り、集めた記号が `checkmark.circle.fill`・`exclamationmark.triangle.fill`・`pause.circle` の 3 つである

## 3. 確認

- [x] 3.1 ビルドとテストが通ることを確かめる。確認: `bash scripts/format.sh` の後に `bash scripts/lint.sh`、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルド、`pnpm exec openspec validate fix-account-token-status-labels --strict` が通る。結果: すべて通った（テストは 422 件）
- [ ] 3.2 `bash scripts/run.sh` で起動し、手元の VoiceOver で確かめる（ユーザーが行う）。確認: 畳める見出し（使える）と畳めない見出し（止まっている、トークンを取れない）のどちらでも、トークンの状態が `Ready`・`Stopped`・`No token` と読まれ、記号の既定の名前は読まれない。取得中は `Getting token` と読まれる（再読み込みの直後など）。アイコンにマウスを載せると同じ名前のツールチップが出る。記号・色・配置、折りたたみの値と説明の読み上げは変わらない

## 4. レビュー

- [x] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する（`.claude/rules/review-process.md`）。変更を確かめてから取り込み、テストが通ることを確かめる。結果: 4 件を取り込んだ（`TokenStateIcon` の使われない `Equatable` を外す、重なるテストの組を減らす、`showsProgressOnlyWhileFetching` をトークンの状態ごとに確かめる形にする、design D1 のコード例を合わせる）
- [x] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。結果: 7 件（中 2・低 5）。中の 2 件（状態ごとの記号と色を固定するテストが無い、スコープ不足の「止まっている」を確かめていない）は、`TokenStateIconTests` を状態ごとの記号・色・名前の表にして直した。低の 5 件は直さず、理由を PR 本文に書いた（取得中の名前が効くかは 3.2 で確かめる）
- [x] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する。結果: 直したのはテストだけでロジックの変更が無いので、実行しない
