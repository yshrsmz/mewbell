# Design

## Context

proposal.md の Why のとおり。今の流れは次のとおり（どれも `@MainActor`）。

- `NotificationStore.perform(_:in:)` は、一覧から外したスレッドの ID を `Set` にまとめたうえで、1 件ずつ `ThreadChangeDispatcher.threadRemoved` を呼ぶ。
- `ThreadChangeDispatcher.threadRemoved` は、`NotificationTracker.remove` で今の一覧から外し、`ThreadNotifying.threadRemoved` を呼ぶ。
- `SystemNotifier.threadRemoved` は、通知の ID を 1 つ作り、`enqueue` で前の操作の `Task` を待つ新しい `Task` を作って、`UserNotificationCenter.removeDelivered(identifiers: [id])` を呼ぶ。

`UserNotificationCenter.removeDelivered(identifiers:)` はもともと配列を受け取り、`threadsChanged` はそれで消えたスレッドをまとめて 1 回で取り下げている。

## Goals / Non-Goals

**Goals:**

- 1 回の `perform` で外したスレッドの通知を、通知センターへの 1 回の操作で取り下げる。

**Non-Goals:**

- 取り下げる通知・取り下げる時機を変えること。
- ポーラーへの既読・Done のリクエストの送り方を変えること（送る間隔や 1 回に送る数の上限は、この change では扱わない）。
- `UserNotificationCenter` の口を変えること。

## Decisions

### D1. 1 件の口を、集合を受け取る口に置き換える（A9・A5）

`ThreadNotifying.threadRemoved(_ threadID: String, for:)` を `threadsRemoved(_ threadIDs: Set<String>, for:)` に置き換える。`ThreadChangeDispatcher` の口と `NotificationTracker.remove` も同じく集合を受け取る形にする。1 件の既読・Done・通知のクリックも、`perform` が作る 1 件の集合で同じ口を通る。

- 代替案: 1 件の口を残し、まとめた操作の口を足す。呼び出し元は `perform` の 1 か所だけで、口を 2 つにすると、どちらを呼ぶかの分岐と、2 つの口のテストが増えるだけになる（A9）。
- 代替案: 口はそのままにし、`SystemNotifier` の中で同じ周回の呼び出しを溜めて 1 回にまとめる。溜める期間を決める仕組みが要り、テストも時機に依存する。呼び出し元がもともと集合を持っているので、それを渡せば足りる。

`ThreadNotifying` はプロトコルの裏に置いたまま（A5）で、テストの `RecordingNotifier` は集合を受け取って 1 つの出来事として記録する。

### D2. `SystemNotifier` は 1 回の `enqueue` で取り下げる（A2）

今の形: `threadsRemoved` は、新着の無い `threadsChanged(for:posted: [], retracted:)` に委ねる。`threadsChanged` は、受け取った ID から通知の ID の配列を作り、`enqueue` を 1 回だけ呼んで `removeDelivered(identifiers:)` に渡す。出すものも取り下げるものも無ければ何もせず（`perform` は空のときに呼ばないが、口として空を受け取っても順番待ちを増やさない）、取り下げるものが無ければ `removeDelivered` を呼ばない（新着だけの取得で空の取り下げを呼ばない）。`enqueue` の直列化（同じスレッドの追加と取り下げが入れ替わらない）は今のまま使う。

- 代替案: `threadsRemoved` に、通知の ID の組み立てと `enqueue` を `threadsChanged` と別に書く。最初はこの形にしたが、同じ 3 行が 2 か所に並び、空のときの扱いも兄弟の 2 つで食い違ったので、code-review の指摘を受けて委ねる形に改めた（A9）。

## 境界とスレッド

`NotificationStore`・`ThreadChangeDispatcher`・`SystemNotifier` は今までどおり `@MainActor` で動き、通知センターへの操作は `SystemNotifier` の `enqueue` が作る `Task` の中で、呼んだ順に 1 つずつ動く（A2）。変えるのは、1 回の `perform` につき作る `Task` の数（スレッドの数から 1 つへ）だけ。

## テストでの差し替え

通知センターは今までどおり `UserNotificationCenter` の偽物（`FakeUserNotificationCenter`）に差し替える。`removeDelivered(identifiers:)` に渡された配列を呼ばれた順に記録するようにし、まとめた取り下げが 1 回の呼び出しになることを確かめる。`NotificationStore` のテストは、`RecordingNotifier` が受け取った集合で、グループの Done とすべて Done が 1 回の `threadsRemoved` になることを確かめる。

## セキュリティ

トークン・gh サブプロセス・ネットワーク・URL を開く処理のどれにも触れないので、`.claude/rules/security.md` のトークン・サブプロセス・ネットワークの項目は該当しない。通知センターに渡すのは今までどおり通知の ID（`<host>/<user>/<threadId>`）だけで、通知の本文（API が返す表示用の情報だけを入れる）も変えない。

## Risks / Trade-offs

- [1 件の操作の取り下げが 1 件の集合を作るぶん、わずかに重くなる] → `perform` はもともと集合を作っているので、新しく作るものは無い。
- [取り下げを 1 回にまとめると、途中で失敗したときに残りもまとめて残る] → `removeDeliveredNotifications(withIdentifiers:)` は失敗を返さない口で、1 件ずつ呼んでも同じ。外したスレッドは新着の判定の今の一覧からも外すので、次の取得では取り下げ直さない。残った通知は、次の基準の取得（`baselineSet`。ポーラーを作り直したときか、アプリを起動し直したとき）で、今の一覧に無いものとして取り下げられる。
