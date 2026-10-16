# Proposal

## Why

既読・Done にしたスレッドの macOS の通知は、`NotificationStore.perform` がスレッドごとに `ThreadChangeDispatcher.threadRemoved` を呼び、`SystemNotifier.threadRemoved` がそのたびに通知センターへの操作を 1 つ順番待ちに積んで取り下げている。リポジトリのグループやアカウントのすべて Done（update-account-heading-actions）では、1 回の操作で最大 500 スレッドを外すので、`Task` を 500 個作り、`removeDeliveredNotifications(withIdentifiers:)` を 500 回呼ぶ。`removeDeliveredNotifications(withIdentifiers:)` は ID の配列を受け取るので、1 回の操作で外したスレッドの ID をまとめて 1 回で取り下げれば足りる。PR #66 の code-review で出て、そのときは直さなかった指摘への対応。

## What Changes

- `ThreadNotifying.threadRemoved(_:for:)` を、1 回の操作で外したスレッドの ID の集合を受け取る `threadsRemoved(_:for:)` に変える。`ThreadChangeDispatcher` の同じ名前の操作と、`NotificationTracker.remove(_:for:)` も集合を受け取る形にする。
- `SystemNotifier.threadsRemoved` は、受け取った ID の通知を通知センターへの 1 回の操作でまとめて取り下げる。
- `NotificationStore.perform` は、外したスレッドの ID をまとめて 1 回だけ渡す。1 件の既読・Done も、1 件の集合として同じ口を通る。
- テストの偽物（`RecordingNotifier`、`FakeUserNotificationCenter`）を合わせ、まとめた操作で取り下げが 1 回になることをテストで確かめる。

アプリの振る舞い（どの通知をいつ取り下げるか）は変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。通知の取り下げの呼び方をまとめるだけで、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。M3（macOS の通知と既読）の取り下げと、M4（操作）のまとめた既読・Done の組み合わせを直す。
- 変更するもの: `Mewbell/Notifications/SystemNotifier.swift`、`Mewbell/Polling/ThreadChangeDispatcher.swift`、`Mewbell/Polling/NotificationTracker.swift`、`Mewbell/Polling/NotificationStore.swift`、テストの `MewbellTests/SettingsPollingTests.swift`（`RecordingNotifier`）、`MewbellTests/Support/FakeUserNotificationCenter.swift`、`MewbellTests/SystemNotificationTests.swift`、`MewbellTests/NotificationStoreNewThreadsTests.swift`。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: どれにも触れない。macOS の通知の取り下げに渡すのは今までどおり通知の ID（`<host>/<user>/<threadId>`）だけで、通知の本文も変えない。
