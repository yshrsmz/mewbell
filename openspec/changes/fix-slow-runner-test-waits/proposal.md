# Proposal

## Why

v0.2.0 のリリースのワークフロー（run 38365829889）は、macOS ランナーでのテストが 28 件失敗したため止まり、Release が draft のまま残った。テスト 418 件の実行に、手元では 2.4 秒、v0.1.0 のときのランナーでは 2.6 秒かかっていたが、この回は 25.8 秒かかった。ランナーがこれだけ遅いと、テストの待ちの上限が切れる。

- `MewbellTests/Support/PollingFakes.swift` の `waitUntil` と `PollerFixture.waitForPendingRefresh` は、条件が満たされなくても 2 秒で黙って戻る。そのため次の `#expect` が古い状態を読み、`ifModifiedSince → [nil, nil]` のように原因のわからない値の食い違いとして落ちる。
- `SubprocessRunnerTests` は、実時間の余裕が 1〜2.5 秒しかない。具体的には、タイムアウト 500ms に対して「3 秒以内に戻る」を確かめるものと、排出の待ち 500ms と `sleep 3` の順序に頼るものがある。

PR の CI では `xcodebuild` を回さないので、こうしたテストの不安定さはリリースのときに初めて表に出て、リリースを止める。

## What Changes

- `waitUntil` と `waitForPendingRefresh` の上限を 2 秒から 30 秒に広げる。どちらも条件が満たされればすぐ戻るので、通るテストの実行時間は変わらない。
- 上限に達したら、呼び出し元の位置で `Issue` を記録する。待ちが切れたことがテストの失敗として直接わかるようにする。`ManualSleeper.waitForSleeps` と `FakeDiscovery.waitUntilWaiting` も呼び出し元の位置を引き継ぐ。
- `SubprocessRunnerTests` の実時間の余裕を広げる。子が戻らないことを表す `sleep` を長くし、タイムアウトと上限をそれに合わせる。プロセスが消えたことの確認は、固定の 300ms の待ちではなく条件の待ちにする。

テストとテスト用のコードだけを変え、アプリの振る舞いは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。テストとテスト用のコードだけの変更で、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: M5（配布）のリリースのワークフローを安定させるための保守の change。
- 変更するもの: `MewbellTests/Support/PollingFakes.swift`、`MewbellTests/Support/FakeDiscovery.swift`、`MewbellTests/SubprocessRunnerTests.swift`、`MewbellTests/SettingsPollingTests.swift`（上限で Issue を記録するようにして見つかった、条件が満たされないまま通っていた待ち。design.md D3）。本体（`Mewbell/`）とワークフローは変えない。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: 本体の処理には触れない。gh サブプロセスのタイムアウトと子プロセスの終了を確かめるテスト（`SubprocessRunnerTests`）の待ち方を変えるが、確かめる性質（タイムアウトで子が消える、出力が途中かもしれないときは結果を受け取らない）は変えない。
- トークンの永続化に関わる変更は無い。
- v0.2.0 の draft のリリースは、この change とは別に、失敗したジョブの再実行で出す。
