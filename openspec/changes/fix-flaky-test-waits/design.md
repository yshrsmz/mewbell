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

- 起きないことを確かめるための短い固定の待ち（`SettingsPollingTests`・`NotificationStoreOpenTests`・`PollingTests`・`RefreshNowTests` の 20〜50ms）。T6 が許す形で、短すぎても見逃すだけで誤って落ちない。
- `SubprocessRunner` が、終わった子プロセスの残した孫プロセスを止めないこと。本番の振る舞いで、この change では変えない。
- spec の要件と、本体の振る舞いの変更。

## Decisions

### D1. 合流は `AccountDiscovery` のテスト用のフックで待つ（A10 の適用外、T6）

合流（`fetchToken` で走っている取得を見つけて `isShared` を立て、その結果を待つこと）は gh も `CredentialStore` も呼ばない。fake の側からは見えず、actor の再入があるので、`AccountDiscovery` の別のメソッドを呼んでも順序は決まらない。待ちが短すぎると、`keepsGhRunningForAJoinedCallerWhenTheFirstIsCancelled` では合流の前に最初の呼び出し元を止めて gh ごと止まり、誤って落ちる。T6 の「起きないこと」の例外にも当たらない。

そこで `AccountDiscovery` に次のフックを足す。

```swift
/// `id` の走っている `gh auth token` に、ほかの呼び出し元が合流するまで待つ（テスト用）。
func waitForJoinedTokenFetch(for id: AccountID) async
```

actor の中で、`inFlightTokenFetches[id]` の `isShared` が立つまで、1ms ずつ待ちながら確かめ直す。止められたら返す。合流が起きないまま待ち続けたときにテストが止まらないよう、2 本のテストに `.timeLimit(.minutes(1))` を付ける。

- `AccountStore.waitForReload` と `SystemNotifier.waitForPendingWork` と同じく、非同期の処理の区切りを待つフックなので、A10 の適用外に足す（手順は `update-architecture-doc`）。合流の有無を返す読み取りの口（`Bool` を返すメンバー）にはしない。A10 の適用外は待つフックに限っているため。
- `sharesARunningTokenFetchBetweenReloadAndRefresh` の `#expect(gated.waitingCount == 1)` は残す。フックが返った後に 2 つ目の gh が門の前に並んでいないことを確かめる。
- 採らなかった案:
  - 合流のたびに continuation を起こす仕組みを `TokenFetch` に持たせる: 本番の型にテストのためだけの状態が増える。待つ時間が 1ms 単位で十分なテストのために要らない。
  - 固定の待ちを長くする: 遅くなるだけで、誤って落ちる可能性は消えない。

### D2. `advance(until:)` は、起こしたポーラーが次の待ちに入るまで待つ（T6）

`ManualSleeper.advance()` は最も古い待ちを 1 つ起こす。起こしたポーラーは取得を終えると次の待ちに入るので、それを区切りにする。

```swift
for _ in 0..<6 where !condition() {
    let sleeps = sleeper.durations.count
    sleeper.advance()
    await sleeper.waitForSleeps(sleeps + 1, sourceLocation: sourceLocation)
}
```

- 6 回の上限は、時間ではなく起こす回数の上限なので残す。
- 待ちが 1 つも無いときに呼ぶと、`waitForSleeps` が 30 秒待って Issue を記録する。今の 3 か所の呼び出しは、どれも待っているポーラーがいる。前提を doc comment に書く。
- ポーラーは store への反映（`onUpdate` を await し、`@MainActor` の `apply` が終わる）を済ませてから次の待ちに入る。次の待ちに入った時点で、起こした取得の結果は store に出ているので、そこで条件を確かめ直せばよい。

### D3. `ThreadDetailsFetcher` の打ち切りの待ちをクロージャで注入する（A5、T6）

`ThreadDetailsFetcher` に `sleep: AccountPoller.Sleep` を足し、既定値を `{ try await Task.sleep(for: $0) }` にする。テストでは `ManualSleeper.sleep` を渡し、`waitForSleeps(1)` の後に `advance()` で打ち切らせる。`ManualSleeper` は止められたときに `CancellationError` を投げるので、打ち切りと止められたことの区別（`(try? await sleep(timeout)) == nil`）は今と同じに動く。

- 本番の呼び出し元（`AccountPoller+ThreadDetails.swift` の 2 か所）は既定値のままにし、ポーラーの `sleep` を渡さない。渡すと、詳細の取得のたびにポーラーのテストの `ManualSleeper` に待ちが増え、`waitForSleeps(n)` の数え方と `advance()` が起こす相手が変わる。ポーラーの層で詳細の取得の打ち切りを待つテストは無い（`AccountPoller` の `detailsTimeout` で間に合っている）。
- A5 は、テストで制御する必要のある待ちをクロージャで注入するとしている。既定値を持たせないのは URL を開くクロージャだけなので、既定値を持たせてよい。

### D4. 孫プロセスは PID を書かせてテストの終わりに終了させる

2 本のシェルを `/bin/sleep 60 & echo $! > "$0"; echo done` にし、`childIsGoneAfterTheTimeout` と同じく一時ファイルに PID を書かせる。テストの `defer` で `kill(pid, SIGTERM)` を送り、ファイルを消す。

- 寝る時間を短くする案は採らない。`SubprocessRunner` は子の終了から `drainTimeout` の後に EOF の有無を判定するので、孫がそれより先に終わると、確かめたい「パイプが開いたまま」の状態にならない。
- `echo $!` は `echo done` より前に一時ファイルへ書くので、標準出力（`done\n`）は変わらない。

## Risks / Trade-offs

- D1 のフックは、合流が起きないと 1ms ごとに確かめ続ける。テストでは `.timeLimit` で止める。本番からは呼ばない。
- D2 で、起こしたポーラーが次の待ちに入らずに止まる場面（無効化など）で使うと、30 秒待って落ちる。今の呼び出しには無い。

## セキュリティ

トークンの流れは変えない。トークンは `gh auth token` の標準出力から取得し、`CredentialStore` の actor の中にだけ持ち、リクエストごとにアカウントの API ベースへ送り、アカウントを外すときと終了時に破棄する。

- D1 のフックは、`AccountDiscovery` の actor の中で `TokenFetch.isShared` を読むだけで、トークンを返さず、ログにも出さない。取得・保存・破棄の順序には関わらない。
- `SubprocessRunner`（`Process` に絶対パスと引数配列を渡すこと、環境変数の除去、タイムアウトと出力の上限）には触れない。D4 はテストの中のシェルの引数だけを変える。
- D3 は打ち切りの待ちの差し替えだけで、リクエスト先の検査とトークンの付け方には触れない。
- security.md の性質を確かめるテストは削らない。
