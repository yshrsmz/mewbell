# Tasks

各グループの終わりに `xcodebuild test -only-testing:MewbellTests/<スイートの型名>` で触ったスイートを流し、結果のスイート数が渡した数と合うことを確かめる（ファイル名ではなくスイートの型名を渡す）。

## 1. 合流の待ち（D1）

- [x] 1.1 `AccountDiscovery.hasJoinedTokenFetch(for:)` を足し、`waitUntilAsync` をテストのターゲットの中で使えるようにする。
- [x] 1.2 `AccountDiscoveryTests.keepsGhRunningForAJoinedCallerWhenTheFirstIsCancelled` と `sharesARunningTokenFetchBetweenReloadAndRefresh` の 200ms の待ちを、`hasJoinedTokenFetch` を `waitUntilAsync` で待つ形に置き換える。`fetchToken` で `isShared` を立てる行を一時的に消して、`keepsGhRunning...` が落ちることを確かめてから戻す。
- [x] 1.3 スキル `update-architecture-doc` の手順で、`docs/architecture.md` の A10 の適用外に `AccountDiscovery.hasJoinedTokenFetch` を足す。`docs/testing.md` の T6 の例にも足す。`bash scripts/check-architecture.sh` を流す。

## 2. ポーラーを進める待ち（D2）

- [x] 2.1 `NotificationStoreSettingsTests` にアカウントごとの `ManualSleeper` を持たせ、`advance(until:)` を消して、呼び出し元で目的のアカウントの sleeper を起こし次の待ちを待つ形にする。スイートの 7 本が通り、`-test-iterations 30` で繰り返しても落ちないことを確かめる。

- [x] 2.2 `ManualSleeper` で、待つ前に止められていたら登録せずに `CancellationError` を投げる（D5）。`stopsADisabledAccount` で bob の sleeper も起こし、bob のポーラーを止めないように本体を一時的に壊すと落ちることを確かめる。全体を `-test-iterations 10` で流して落ちないことを確かめる。

## 3. 詳細の取得の打ち切り（D3）

- [x] 3.1 `ThreadDetailsFetcher` に `sleep` を足す（既定値は `Task.sleep`）。`AccountPoller+ThreadDetails.swift` の呼び出しは変えない。
- [x] 3.2 `ThreadDetailsFetcherTests.reportsTimedOutFetchesAsFailures` を `ManualSleeper` で打ち切らせる形にする。`doesNotReportCancelledFetchesAsFailures` は変えない。

## 4. 孫プロセス（D4）

- [x] 4.1 `SubprocessRunnerTests.returnsWhenABackgroundChildKeepsThePipeOpenIfAllowed` と `failsWhenTheOutputMayBeIncomplete` で、孫の PID を一時ファイルに書かせ、テストの終わりに終了させる。テストの後に `pgrep -f "/bin/sleep 60"` で孫が残っていないことを確かめる。

## 5. 文書

- [x] 5.1 `docs/testing.md` の「既知の逸脱」から、この change で直した 3 件を消す。

## 6. 確認

- [x] 6.1 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通ることを確かめる。`bash scripts/lint.sh`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルド、`pnpm exec openspec validate --all --strict` が通ることを確かめる。本体の振る舞いは変えないので、手元での起動の確認は省く。

## 7. レビュー

- [x] 7.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込む。
- [x] 7.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
