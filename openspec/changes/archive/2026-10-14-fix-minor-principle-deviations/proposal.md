# Proposal

## Why

`docs/architecture.md` の「既知の逸脱」に、小さな逸脱が 2 つ残っている。

- A10: `AccountPoller.pendingRefreshCount` は、テストの `PollerFixture.waitForPendingRefresh()` のためだけに公開されている（`// テスト用`）。本体はこれを使わない。値の元になる `RefreshWaiters.count` も、このプロパティからしか使われていない。
- A11: `App/SingleInstance.swift` のロガーのカテゴリが `SingleInstance` で、ほかの型と違ってモジュールのディレクトリ名（`App`）になっていない。Console でカテゴリ `App` を指定して絞っても、このログが出てこない。

## What Changes

- テストの `waitForPendingRefresh()` は、再読み込みが待ちに入ったかを、本体が使っている `AccountPoller.refreshWaitsForNextFetch` で確かめる。
- `AccountPoller.pendingRefreshCount` と `RefreshWaiters.count` を消す。
- `SingleInstance` のロガーのカテゴリを `"App"` にする。
- `docs/architecture.md` の「既知の逸脱」から A10 と A11 の行を消す。原則と適用外は変えない。

アプリの振る舞いは変えない。ログのカテゴリが変わるだけになる。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。コードの形とログのカテゴリだけを変え、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。add-architecture-principles が「既知の逸脱」に記録した行を片付ける。
- 変更するもの: `Mewbell/Polling/AccountPoller.swift`、`Mewbell/Polling/RefreshWaiters.swift`、`Mewbell/App/SingleInstance.swift`、`MewbellTests/Support/PollingFakes.swift`、`docs/architecture.md`（既知の逸脱）。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: いずれにも触れない。トークンは今までどおりメモリにだけ持ち、永続化しない。ログは今までと同じメッセージで、カテゴリだけが変わる。可変値の伏せ方（`.private`）は変えない。
