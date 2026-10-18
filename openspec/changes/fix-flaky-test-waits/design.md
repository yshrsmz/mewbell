# Design

## Context

テストは Swift Testing で書いている。gh は `ProcessRunning` を `FakeProcessRunner`（門を付けるときは `GatedProcessRunner`）に、HTTP は `FakeHTTPTransport` に、ポーラーの待ちは `ManualSleeper` に差し替えている（A5）。状態が変わるまで待つ道具は `waitUntil`（短い間隔で確かめ直し、30 秒で Issue を記録する）と `ManualSleeper.waitForSleeps`。

`docs/testing.md` の T6 は、起きるはずのことを固定の時間で待たないこと、起きないことを確かめるときは区切りまで待つことを求める。区切りが無いときだけ短い固定の待ちを許すが、それは待ちが短すぎても誤って落ちない場合に限る。

## Goals / Non-Goals

**Goals:**

- `docs/testing.md` の「既知の逸脱」の 3 件を、T6 に合う待ち方に直し、表から消す。
- `ThreadDetailsFetcherTests.reportsTimedOutFetchesAsFailures` の 50ms の実時間の待ちを無くす。
- `SubprocessRunnerTests` の 2 本が残す `sleep 60` の孫プロセスを、テストの終わりに終了させる。

**Non-Goals:**

- 起きないことを確かめるための短い固定の待ち（`SettingsPollingTests`・`NotificationStoreOpenTests`・`PollingTests`・`RefreshNowTests` の 20〜50ms と、`AccountStoreTests.doesNotRunTwoReloadsAtOnce` の `Task.yield()` 5 回）。どれも、起きるならその前に来る区切りが無い（止めたポーラーの遅れた更新、走らないはずの 2 回目の読み込み、など）。T6 が許す形で、短すぎても見逃すだけで誤って落ちない。
- `SubprocessRunner` が、終わった子プロセスの残した孫プロセスを止めないこと。本番の振る舞いで、この change では変えない。
- spec の要件と、本体の振る舞いの変更。

## Decisions

### D1. 合流は `AccountDiscovery` の読み取りの口を `waitUntilAsync` で待つ（A10 の適用外、T6）

合流（`fetchToken` で走っている取得を見つけて `isShared` を立て、その結果を待つこと）は gh も `CredentialStore` も呼ばない。fake の側からは見えず、actor の再入があるので、`AccountDiscovery` の別のメソッドを呼んでも順序は決まらない。待ちが短すぎると、`keepsGhRunningForAJoinedCallerWhenTheFirstIsCancelled` では合流の前に最初の呼び出し元を止めて gh ごと止まり、誤って落ちる。T6 の「起きないこと」の例外にも当たらない。

そこで `AccountDiscovery` に、合流したかを返す読み取りの口を足し、テストは `waitUntilAsync` で待つ。

```swift
/// `id` の走っている `gh auth token` に、ほかの呼び出し元が合流したか（テストが `waitUntilAsync` で合流を待つため）。
func hasJoinedTokenFetch(for id: AccountID) -> Bool
```

- 待つループと期限はテストの側に置く。`waitUntilAsync`（`PollingFakes.swift`）は 30 秒で呼び出し元の位置に Issue を記録するので、合流が起きないときもどこで止まったかが分かる。`waitUntilAsync` は今 `private` なので、`sourceLocation` に既定値を付けてテストのターゲットの中で使えるようにする。
- `AccountPoller.refreshWaitsForNextFetch` を `waitForPendingRefresh` で待つのと同じ形にする。`AccountStore.waitForReload` と `SystemNotifier.waitForPendingWork` は本体の Task を待つフックで、合流には待つ対象の Task が無い。
- A10 の適用外を、待つ対象の Task が無い区切りについて `waitUntilAsync` の条件にだけ使う読み取りの口まで広げる（手順は `update-architecture-doc`）。読み取りの口は `Bool` を返すだけにし、`#expect` で確かめない。
- `sharesARunningTokenFetchBetweenReloadAndRefresh` の `#expect(gated.waitingCount == 1)` は残す。合流した後に 2 つ目の gh が門の前に並んでいないことを確かめる。
- 採らなかった案:
  - actor の中で 1ms ごとに確かめ直す async のフック: 本体に期限の無いポーリングが入り、合流が起きないときは `.timeLimit` でしか止まらず、止まった位置も報告されない。
  - 合流のたびに continuation を起こす仕組みを `TokenFetch` に持たせる: 本体のコードが最も増え（待ち手の管理、取得の終わりや待ち手を止めたときの扱い）、合流の分岐にテストのための処理が入る。期限も無いまま。
  - 固定の待ちを長くする: 遅くなるだけで、誤って落ちる可能性は消えない。

### D2. `NotificationStoreSettingsTests` はアカウントごとの `ManualSleeper` で、目的のポーラーを起こして次の待ちまで進める（T6）

`advance(until:)` を消し、このスイートだけアカウントごとに `ManualSleeper` を持たせる（`makePoller` は `account` を受け取るので、その sleeper の `sleep` を渡す）。呼び出し元は、目的のアカウントの sleeper で `advance()` し、同じ sleeper の `waitForSleeps(n + 1)` で次の待ちを待つ。

```swift
sleeper(alice).advance()
await sleeper(alice).waitForSleeps(3)
#expect(store.feeds[alice]?.threads.map(\.id) == ["4", "5"])
```

- ポーラーは、取得の結果を store に出して（`onUpdate` を await し、`@MainActor` の `apply` が終わって）から次の待ちに入る。次の待ちに入った時点で、起こした取得の結果は store に出ている。
- 共有の sleeper では、古い順に起こすので目的でないポーラーを起こすことがあり、待ちの数も全ポーラーの合計になる。呼んだ時点で待ち手がいなければ `advance()` は空振りし、どの待ちが目的のポーラーのものかも決まらない（`letsAReloadSkipTheCarriedWait` の下限の待ち）。アカウントごとにすると、どれも「alice の何回目の待ちか」で決まり、上限の回数と繰り返しが要らなくなる。失敗すると `waitForSleeps` が 30 秒で呼び出し元の行に Issue を 1 件だけ記録する。
- 待ちの回数には、作り直す前のポーラーが入った待ちも含む（`ManualSleeper` は、待ちに入った後に止めた待ちを `durations` から消さない。待ちに入る前に止められた待ちは数えない。D5）。
- 作り直しで 1 つのアカウントのポーラーが入れ替わるのはこのスイートだけなので、共有の sleeper で両方を進める兄弟のスイート（`NotificationStoreActionTests` など）とは形を揃えない。
- 採らなかった案:
  - 補助関数の中だけで直す（待ち手の数を読む口を `ManualSleeper` に足し、起こす前に待ち手を待ち、期限が切れたら抜ける）: どのポーラーの待ちかは分からないまま、上限と繰り返しと期限切れの扱いが残り、共有の fake も変わる。
  - 共有の sleeper のまま呼び出し元で待ちの合計を数える: bob の振る舞いに依存して壊れやすく、どの待ちを確かめているかもあいまいなまま。

### D3. `ThreadDetailsFetcher` の打ち切りの待ちをクロージャで注入する（A5、T6）

`ThreadDetailsFetcher` に `sleep: AccountPoller.Sleep` を足し、既定値を `{ try await Task.sleep(for: $0) }` にする。テストでは `ManualSleeper.sleep` を渡し、`waitForSleeps(1)` の後に `advance()` で打ち切らせる。`ManualSleeper` は止められたときに `CancellationError` を投げるので、打ち切りと止められたことの区別（`(try? await sleep(timeout)) == nil`）は今と同じに動く。

- 本番の呼び出し元（`AccountPoller+ThreadDetails.swift` の 2 か所）は既定値のままにし、ポーラーの `sleep` を渡さない。渡すと、詳細の取得のたびにポーラーのテストの `ManualSleeper` に待ちが増え、`waitForSleeps(n)` の数え方と `advance()` が起こす相手が変わる。ポーラーの層で詳細の取得の打ち切りを待つテストは無い（`AccountPoller` の `detailsTimeout` で間に合っている）。
- A5 は、テストで制御する必要のある待ちをクロージャで注入するとしている。既定値を持たせないのは URL を開くクロージャだけなので、既定値を持たせてよい。

### D4. 孫プロセスは PID を書かせてテストの終わりに終了させる

2 本のシェルを `/bin/sleep 60 & echo $! > "$0"; echo done` にし、`childIsGoneAfterTheTimeout` と同じく一時ファイルに PID を書かせる。テストの `defer` で `kill(pid, SIGTERM)` を送り、ファイルを消す。

- 寝る時間を短くする案は採らない。`SubprocessRunner` は子の終了から `drainTimeout` の後に EOF の有無を判定するので、孫がそれより先に終わると、確かめたい「パイプが開いたまま」の状態にならない。
- `echo $!` は `echo done` より前に一時ファイルへ書くので、標準出力（`done\n`）は変わらない。

### D5. `ManualSleeper` は、待つ前に止められていたらすぐ投げる（T5）

本物の `Task.sleep` は、止められたタスクで呼ぶとすぐ `CancellationError` を投げる。`ManualSleeper` は、`withTaskCancellationHandler` の `onCancel` が待ちの登録より先に走ると、登録した待ちを誰も起こさず、`durations` にも数えていた。`AccountPoller.pause` は待ち用の Task を作ってから待つので、その Task が動き出す前に作り直しや無効化で止められると、この状態になる。D2 でアカウントごとに「何回目の待ちか」を数えるので、この待ちが数に紛れ込むと、目的の待ちを取り違える。

待ちを登録するロックの中で `Task.isCancelled` を確かめ、止められていれば登録せずに投げる。`onCancel` はキャンセルの印が立った後に走るので、登録の前に印を見るか、登録した後に `onCancel` が待ちを外すかのどちらかになる。

## Risks / Trade-offs

- D2 の待ちの回数は、作り直す前のポーラーの待ちを含めて数える。作り直しの回数が変わるテストでは数え直しが要る。

## セキュリティ

トークンの流れは変えない。トークンは `gh auth token` の標準出力から取得し、`CredentialStore` の actor の中にだけ持ち、リクエストごとにアカウントの API ベースへ送り、アカウントを外すときと終了時に破棄する。

- D1 の読み取りの口は、`AccountDiscovery` の actor の中で `TokenFetch.isShared` を読むだけで、トークンを返さず、ログにも出さない。取得・保存・破棄の順序には関わらない。
- `SubprocessRunner`（`Process` に絶対パスと引数配列を渡すこと、環境変数の除去、タイムアウトと出力の上限）には触れない。D4 はテストの中のシェルの引数だけを変える。
- D3 は打ち切りの待ちの差し替えだけで、リクエスト先の検査とトークンの付け方には触れない。
- security.md の性質を確かめるテストは削らない。
