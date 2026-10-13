# Design

## Context

ポーラーと store のテストは、偽の時計（`ManualSleeper`）と偽のトランスポート（`FakeHTTPTransport`）で動かし、ポーラーが次の段階に進むのを `waitUntil` の系統で待つ。待つ helper は次の 4 つで、どれも条件が満たされればすぐ戻る「肯定の待ち」として使われている（呼び出し元は約 200 か所）。

- `waitUntil(_:)`（`MewbellTests/Support/PollingFakes.swift`）: 1ms ごとに条件を見て、2 秒で諦める。
- `ManualSleeper.waitForSleeps(_:)`: `waitUntil` を呼ぶ。
- `GatedProcessRunner.waitUntilWaiting(_:)`（`FakeDiscovery.swift`）: `waitUntil` を呼ぶ。
- `PollerFixture.waitForPendingRefresh()`: actor の `pendingRefreshCount` を 1ms ごとに見て、2 秒で諦める。

諦めたときに何も記録しないので、失敗は後続の `#expect` の値の食い違いとして現れる。

`SubprocessRunnerTests` は本物の `/bin/sh` と `/bin/sleep` を起動し、`SubprocessRunner` のタイムアウト（`request.timeout`）と、子の終了後にパイプの EOF を待つ排出の時間（`RunState.drainTimeout` = 500ms）を確かめている。

手元で CPU に負荷をかけても（コア数の 2 倍の `yes`）、失敗は再現しなかった。ランナーで何が遅くしたかは特定できていないので、どの程度遅くても通る形にする。

## Goals / Non-Goals

**Goals:**

- ランナーが手元の 10 倍以上遅くても、テストが待ちの上限で落ちないようにする。
- それでも待ちが切れたときは、どこで何を待って切れたかが失敗として出るようにする。

**Non-Goals:**

- 待ち方そのものの作り直し。たとえば、ポーリングで見る代わりに continuation で知らせる形にはしない。
- 並行実行の抑制や、ポーリング間隔の変更でランナーの負荷を減らすこと（Decisions の「採らなかった案」）。
- PR の CI で `xcodebuild` を回すこと（CLAUDE.md の方針で macOS ランナーはリリースだけに使う）。
- 固定の sleep で順序を作っているほかのテスト（`SettingsPollingTests` などの 20〜50ms の待ち）の見直し。今回の失敗には含まれていない。

## Decisions

### D1. 待ちの上限を 30 秒にし、切れたら Issue を記録する（A12）

`waitUntil` と `waitForPendingRefresh` の上限を 30 秒にする。条件が満たされればすぐ戻るので、通るテストの実行時間は変わらない。30 秒は、この回のランナーでのテスト全体の実行時間（25.8 秒）より長い値として選んだ。

上限に達したら `Issue.record` で「条件が満たされないまま 30 秒経った」と記録する。`sourceLocation: SourceLocation = #_sourceLocation` を引数に足して、記録の位置を呼び出し元にする。`waitForSleeps` と `waitUntilWaiting` も同じ引数を受け取って `waitUntil` に渡し、テスト本体の行が出るようにする。`IconColumnTests` の helper と同じ書き方。

上限の値は `PollingFakes.swift` に 1 つだけ定数として置き、`waitUntil` と `waitForPendingRefresh` で共有する。

採らなかった案:

- 上限を広げるだけにする: 次に切れたときも、原因のわからない値の食い違いとして落ちる。
- 上限を無くす: 不具合で条件が満たされないとき、テストが止まって CI の時間を使い切る。

### D2. `SubprocessRunnerTests` の余裕を広げる（A12）

実時間の順序に頼る 3 本で、「起きてはいけないこと」が起きるまでの時間を長くし、確かめたい処理（タイムアウト、排出の待ち）との差を十分に取る。

- `childIsGoneAfterTheTimeout`: 子の `sleep` を 5 秒から 60 秒にし、「タイムアウトで戻る」の上限を 3 秒から 30 秒にする。タイムアウト（500ms）は変えない。子が消えたことは、固定の 300ms の待ちの後に 1 回見るのではなく、`waitUntil` で `kill(pid, 0)` が `ESRCH` になるまで待ってから確かめる。
- `failsWhenTheOutputMayBeIncomplete` と `returnsWhenABackgroundChildKeepsThePipeOpenIfAllowed`: バックグラウンドの `sleep` を 3 秒から 60 秒にし、タイムアウトを 2 秒から 30 秒にする。排出の待ち（500ms）がタイムアウトより十分先に終わり、`sleep` の終了（パイプの EOF）がそれより後になる。

採らなかった案:

- `SubprocessRunner` の `drainTimeout` やタイムアウトをテストから差し替えられるようにする: 本体の API をテストのために広げることになる（A10）。
- これらのテストを手元だけで動かす: タイムアウトと子の終了は security.md の「サブプロセスにはタイムアウトを付ける」を確かめる最後のテストなので、CI でも動かす。

### 採らなかった案: ランナーの負荷を減らす

`waitUntil` の 1ms と `FakeHTTPTransport.send` の 5ms のポーリングが、並行に動く多数のテストで CPU を取り合っている可能性はある。ただし手元で再現できず、効き目を確かめる方法が無い。Swift Testing の並行実行を止める設定も、`xcodebuild` から何が効くかを確かめないまま入れることになる。上限を広げて失敗を見える形にすれば、次に落ちたときに原因を絞れるので、今回は入れない。

## セキュリティ

- トークン: 扱わない。テストのダミーのトークン（`test-token-alice`）も変えない。
- gh サブプロセス: 本体の `SubprocessRunner` は変えない。`.claude/rules/security.md` の「サブプロセスにはタイムアウトを付け、標準出力のサイズにも上限を設ける」を確かめるテスト（`childIsGoneAfterTheTimeout`、`failsWhenStdoutExceedsTheLimit`）は残し、確かめる性質も変えない。待ちの時間だけを変える。
- ネットワーク・URL を開く処理: 触れない。

## Risks / Trade-offs

- `failsWhenTheOutputMayBeIncomplete` と `returnsWhenABackgroundChildKeepsThePipeOpenIfAllowed` のバックグラウンドの `sleep 60` は、テストが終わった後も最大 60 秒残る。今までも 3 秒残っていた。害は無いが、手元で `ps` を見ると残っている。
- 待ちが本当に切れる不具合があると、そのテストは 30 秒かかってから落ちる。今までの 2 秒より遅いが、失敗の理由は Issue でわかる。
- 手元で再現できないので、効き目はランナーで次にリリースのワークフローが動くまで確かめられない。
