# Tasks

## 1. 待ちの helper

- [x] 1.1 `MewbellTests/Support/PollingFakes.swift` に待ちの上限（30 秒）の定数を置き、`waitUntil` と `PollerFixture.waitForPendingRefresh` で使う（design.md D1）。
- [x] 1.2 `waitUntil` と `waitForPendingRefresh` が上限に達したら、`sourceLocation` の位置で `Issue.record` する。`sourceLocation: SourceLocation = #_sourceLocation` を引数に足す。
- [x] 1.3 `ManualSleeper.waitForSleeps` と `GatedProcessRunner.waitUntilWaiting` も `sourceLocation` を受け取り、`waitUntil` に渡す。
- [x] 1.4 全テストを流し、上限に達して Issue が記録されるテストが無いことを確かめる（条件が満たされないまま通っていた待ちがあれば、ここで見つかる。見つかったら AskUserQuestion で扱いを決める）。
  - 結果: `NotificationStoreSettingsTests.dropsLateUpdatesFromTheStoppedPoller` の `waitUntil { gets("alice").count == 2 }` が 1 件見つかった（単独実行で 6 回中 2 回）。alice と bob は同じ `ManualSleeper` を共有し、`advance()` は先に寝た方を起こすので、bob が先だと alice の 2 回目の取得が始まらず、今までは 2 秒で黙って抜けていた。ユーザーの判断でこの change で直し、`stopsADisabledAccount` と同じく `advance()` を 2 回呼んで両方を起こす形にした（直した後は単独実行で 10 回とも通った）。全テストの実行時間は約 2.4 秒から 0.6〜0.7 秒になった。差の大半はこの待ちの 2 秒だった。
- [x] 1.5 待ちが切れたときの出方を手元で 1 回確かめる。たとえば 1 本のテストの条件を一時的に満たされないものに変え、失敗の場所がテスト本体の行として出ることを見てから元に戻す。

## 2. `SubprocessRunnerTests`

- [x] 2.1 `childIsGoneAfterTheTimeout` の子の `sleep` を 60 秒、戻るまでの上限を 30 秒にする。子が消えたことは `waitUntil` で `ESRCH` になるまで待ってから確かめる（design.md D2）。
- [x] 2.2 `failsWhenTheOutputMayBeIncomplete` と `returnsWhenABackgroundChildKeepsThePipeOpenIfAllowed` のバックグラウンドの `sleep` を 60 秒、タイムアウトを 30 秒にする。
- [x] 2.3 `SubprocessRunnerTests` を流し、3 本とも今までと同じ時間（タイムアウトや排出の待ちの分だけ）で通ることを確かめる。

## 3. 確認

- [x] 3.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell MEWBELL_WARNINGS_AS_ERRORS=YES test` で全テストを通し、全体の実行時間が変更の前（約 2.4 秒）から大きく変わらないことを PR に書く。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
  - 結果: 全テスト 418 件が 0.6〜0.7 秒で通った（3 回）。Debug と Release のビルド、lint、validate も通った。
- [x] 3.2 遅い環境を近似して流す。`taskpolicy -b` などで優先度を下げて `xcodebuild ... test` を流し、通ることを確かめる（再現の手段にならなければ、その旨を PR に書く）。
  - 結果: `taskpolicy -b` だけでは 1.7 秒（約 2.4 倍）で通った。コア数の 2 倍の `yes` だけでは 0.68 秒で、遅くならなかった。両方を重ねるとテストが 10 分経っても終わらず、止めた。どれもランナーの 10 倍の遅さの再現にはならないので、効き目は 3.4 で確かめる。
- [x] 3.3 `bash scripts/run.sh` で起動し、一覧の表示と再読み込みが今までどおり動くことを確かめる。本体は変えないので、動作確認として行う。
- [ ] 3.4 マージ後、次のリリースのワークフロー（v0.2.1）の build ジョブで、テストが通ることと実行時間を確かめる。

## 4. レビュー

- [x] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
  - 結果: 待ちのループを `waitUntilAsync` にまとめ、`childIsGoneAfterTheTimeout` の重複した `#expect` を消した。取り込んだ。
- [x] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
  - 結果: 指摘 8 件。`advance(until:)` が黙って戻る件を直した（design.md D4）。ほかの 7 件は直さない（理由は PR 本文）。
- [x] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する。
  - 結果: 直したのはテストの helper の数行（Issue の記録を足しただけ）なので、もう一度は実行しない。
