# Proposal

## Why

`docs/testing.md` の T6（実時間と同期的な待ちに頼らない）に合わないテストが残っている。「既知の逸脱」の 3 件と、整理の途中で見つけた 2 件である。

- `AccountDiscoveryTests` の合流の 2 本が、合流が起きるのを 200ms の固定の待ちで待っている。負荷の高い機械では合流の前に先へ進み、誤って落ちる。
- `NotificationStoreSettingsTests` の `advance(until:)` が、ポーラーを進めるたびに 30ms の固定の待ちを挟み、試行の回数で諦める。遅い機械では条件が満たされる前に試行が尽きる。
- `ThreadDetailsFetcherTests.reportsTimedOutFetchesAsFailures` が、打ち切りを 50ms の実時間で待っている。
- `SubprocessRunnerTests` の 2 本（`returnsWhenABackgroundChildKeepsThePipeOpenIfAllowed`、`failsWhenTheOutputMayBeIncomplete`）が、`sleep 60` の孫プロセスをテストの後も 60 秒残す。

## What Changes

- `AccountDiscovery` に、走っている `gh auth token` にほかの呼び出し元が合流したかを返す読み取りの口を足し、合流の 2 本の 200ms の待ちを、これを `waitUntilAsync` で待つ形に置き換える。`docs/architecture.md` の A10 の適用外に、この口を足す。
- `NotificationStoreSettingsTests.advance(until:)` を、起こしたポーラーが次の待ちに入るまで待つ形にする（30ms の待ちを消す）。
- `ThreadDetailsFetcher` に打ち切りの待ちのクロージャ（`sleep`）を注入できるようにし、テストでは `ManualSleeper` で進める。本番の呼び出し元は既定の `Task.sleep` のままにする。
- `SubprocessRunnerTests` の 2 本で、孫プロセスの PID をファイルに書かせ、テストの終わりに終了させる。
- `docs/testing.md` の「既知の逸脱」から 3 件を消す。

本体の振る舞いは変えない。本体で変えるのは、`ThreadDetailsFetcher` の待ちの注入（既定値は今と同じ `Task.sleep`）と、`AccountDiscovery` のテスト用の読み取りの口の追加だけ。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。テストの待ち方だけの変更で、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。
- 変更するもの: `MewbellTests/` の `AccountDiscoveryTests.swift`、`SettingsPollingTests.swift`、`ThreadDetailsCacheTests.swift`、`SubprocessRunnerTests.swift`。本体の `Mewbell/Accounts/AccountDiscovery.swift` と `Mewbell/Polling/ThreadDetailsFetcher.swift`。`MewbellTests/Support/PollingFakes.swift`（`waitUntilAsync`）。`docs/architecture.md`（A10）と `docs/testing.md`（T6 の例と既知の逸脱）。
- トークン・gh サブプロセス: `AccountDiscovery` のトークンの取得の経路に読み取りの口を足すが、この口はメモリ上の合流の有無を読むだけで、トークンを返さず、取得・保存・破棄の流れを変えない。`SubprocessRunner` の本体には触れない。
- ネットワーク・URL を開く処理: `ThreadDetailsFetcher` の打ち切りの待ちの差し替えだけで、リクエスト先の検査やトークンの付け方には触れない。
- トークンの永続化に関わる変更は無い。
