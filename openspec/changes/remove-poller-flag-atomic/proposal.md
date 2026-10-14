# Proposal

## Why

`AccountPoller` の、次の取得を条件なし（`If-Modified-Since` なし）にする印 `unconditionalRequested` は `Atomic<Bool>` で持っている。fix-stale-notification-list で入れたときは、再読み込みのボタンが `NotificationStore` から actor に入らずに同期的に印を立てていたので、`Atomic` が要った。update-reload-fetch-now で再読み込みが `refreshNow()`（actor のメソッド）に替わり、その呼び出しは無くなった。今は印を読み書きする 5 か所（立てる 4 か所と、`fetch` で下ろす 1 か所）がすべて actor の中にある。

それでも印は `Atomic` のままで、立て方も 2 通りある。`refreshNow` は `private nonisolated` の `requestUnconditionalFetch()` を通し、`perform`・`markAllRead`・`fetch` の失敗時は `unconditionalRequested.store(true, ordering: .relaxed)` と直接書いている。`docs/architecture.md` の A2 では「actor の外から同期的に触る状態は `Mutex` や `Atomic` で持つ」としている。印はこの条件に当たらないのに `Atomic` で持っていて、読み手に「actor の外から触る経路がある」と思わせる。

## What Changes

- `unconditionalRequested` を `Atomic(false)` から、`hidden`・`readThroughs` と同じ actor の `var unconditionalRequested = false` にする。
- `requestUnconditionalFetch()` を消し、印を立てる 4 か所をすべて `unconditionalRequested = true` と書く。
- `fetch` で印を下ろす `exchange(false, ordering: .relaxed)` を、値を読んでから `false` を代入する 2 行にする。送る前に下ろす順序は変えない。
- `AccountPoller+ThreadActions.swift` の `import Synchronization` を消す（`AccountPoller.swift` は `loop` の `Mutex` で引き続き使う）。
- `docs/architecture.md` の A2 から、コードに無くなる `Atomic` の名前を外し、今の形（外から触る状態は `Synchronization` の型、中だけで触る状態は actor の `var`）に書き直す。

アプリの振る舞いは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。状態の持ち方を変えるだけで、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。M2（fix-stale-notification-list）と M4（update-reload-fetch-now）で入れた `AccountPoller` の印を、A2 に合わせる。
- 変更するもの: `Mewbell/Polling/AccountPoller.swift`、`Mewbell/Polling/AccountPoller+ThreadActions.swift`、`docs/architecture.md`（A2）。テストは変えない。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: いずれにも触れない。取得の条件（`If-Modified-Since` を付けるか）を決める印の持ち方だけを変え、送り先・ヘッダー・トークンの扱いは変えない。トークンは今までどおりメモリにだけ持ち、永続化しない。
