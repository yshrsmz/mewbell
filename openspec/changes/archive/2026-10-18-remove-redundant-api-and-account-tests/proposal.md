# Proposal

## Why

2026-10-18 に `docs/testing.md` を作り、テストを残すかどうかの基準を T1〜T8 として書いた。テストを精査し直すと、この基準に照らして余分なテストが約 1,100 行あった。この change では、そのうち GitHubAPI・GhCLI・アカウント・設定・App・`scripts/tests` の側を整理する。

この側で多いのは次の 2 つ。

- 共有の `get()` と `apiURL` の分岐（401・403・404・レート制限・リダイレクト・GHES のパス）を、Issue・リリース・run の一覧・pending_deployments の入口ごとに確かめ直している（T2）
- 同じ分岐を通る引数を並べている（T4）

`rateLimit()`・`get()`・`apiURL` を直すたびに書き直すテストが 4〜6 か所あり、これを 1 か所にする。

## What Changes

- 次のテストを削除・統合・縮小する。対象の一覧と、それぞれの代わりに残るテストは design.md に書く。
  - GitHubAPI: `CheckSuiteTitleTests`、`ThreadDetailsRequestTests`（本体・`+Release`・`+Actions`）、`GitHubAPIModelTests`、`ThreadEventResolverTests`、`MarkThreadReadTests`
  - gh・アカウント・設定・App: `AccountDiscoveryTests`、`GhLocatorTests`、`AccountStoreTests`、`SingleInstanceTests`、`SettingsTests`、`StatusItemMenuTests`
  - シェルのテスト: `scripts/tests/verify-app-test.sh`、`scripts/tests/check-architecture-test.sh`
- 消すテストにしか無い確認は、残すテストに移す（`ghe.com` のホストの判定、`Retry-After: soon` の分類など）。
- 本体のコードと、テストの差し替えの仕組み（fake）は変えない。

削る量は約 240 行の見込み。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。テストだけの変更で、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。Polling・store・通知・UI の側の整理は、別の change で行う。2 つの change は同じファイルに触れない。
- 変更するもの: `MewbellTests/` の上記のファイルと、`scripts/tests/` の 2 本。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: 本体には触れない。ただし、これらを確かめるテスト（伏せ字、ID とホスト名の検証、オリジン検査、リクエストごとのトークン、リダイレクトの拒否）を整理するので、security.md の性質ごとに残るテストを design.md に書く。
- トークンの永続化に関わる変更は無い。
