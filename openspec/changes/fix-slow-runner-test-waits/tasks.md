# Tasks

## 1. 待ちの helper

- [ ] 1.1 `MewbellTests/Support/PollingFakes.swift` に待ちの上限（30 秒）の定数を置き、`waitUntil` と `PollerFixture.waitForPendingRefresh` で使う（design.md D1）。
- [ ] 1.2 `waitUntil` と `waitForPendingRefresh` が上限に達したら、`sourceLocation` の位置で `Issue.record` する。`sourceLocation: SourceLocation = #_sourceLocation` を引数に足す。
- [ ] 1.3 `ManualSleeper.waitForSleeps` と `GatedProcessRunner.waitUntilWaiting` も `sourceLocation` を受け取り、`waitUntil` に渡す。
- [ ] 1.4 全テストを流し、上限に達して Issue が記録されるテストが無いことを確かめる（条件が満たされないまま通っていた待ちがあれば、ここで見つかる。見つかったら AskUserQuestion で扱いを決める）。
- [ ] 1.5 待ちが切れたときの出方を手元で 1 回確かめる。たとえば 1 本のテストの条件を一時的に満たされないものに変え、失敗の場所がテスト本体の行として出ることを見てから元に戻す。

## 2. `SubprocessRunnerTests`

- [ ] 2.1 `childIsGoneAfterTheTimeout` の子の `sleep` を 60 秒、戻るまでの上限を 30 秒にする。子が消えたことは `waitUntil` で `ESRCH` になるまで待ってから確かめる（design.md D2）。
- [ ] 2.2 `failsWhenTheOutputMayBeIncomplete` と `returnsWhenABackgroundChildKeepsThePipeOpenIfAllowed` のバックグラウンドの `sleep` を 60 秒、タイムアウトを 30 秒にする。
- [ ] 2.3 `SubprocessRunnerTests` を流し、3 本とも今までと同じ時間（タイムアウトや排出の待ちの分だけ）で通ることを確かめる。

## 3. 確認

- [ ] 3.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell MEWBELL_WARNINGS_AS_ERRORS=YES test` で全テストを通し、全体の実行時間が変更の前（約 2.4 秒）から大きく変わらないことを PR に書く。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [ ] 3.2 遅い環境を近似して流す。`taskpolicy -b` などで優先度を下げて `xcodebuild ... test` を流し、通ることを確かめる（再現の手段にならなければ、その旨を PR に書く）。
- [ ] 3.3 `bash scripts/run.sh` で起動し、一覧の表示と再読み込みが今までどおり動くことを確かめる。本体は変えないので、動作確認として行う。
- [ ] 3.4 マージ後、次のリリースのワークフロー（v0.2.1）の build ジョブで、テストが通ることと実行時間を確かめる。

## 4. レビュー

- [ ] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する。
