# Design

## Context

スレッドを開く処理は、`NotificationStore.open` が `APIEndpoints(host:)` から `ThreadWebURL.make` で URL を組み立て、検査（`ThreadWebURL.isOpenable`）を通ったものだけを、初期化で受け取った `openURL`（本番は `NSWorkspace.shared.open`、テストは記録するだけ）で開いている。アカウントの区画の見出し（`AccountSectionView.header`）には、開閉のボタンと「すべて既読」（`MarkAllReadButton`）が並んでいる。見出しは、トークンや取得の状態にかかわらず、一覧に出るアカウントにはいつも描かれる。一覧での操作は `ThreadListActions` のクロージャで `MenuBarContentView` から `NotificationStore` に渡している。

## Goals / Non-Goals

**Goals:**

- スレッドを開くのと同じ経路（`APIEndpoints` → `ThreadWebURL` の検査 → `openURL`）で Web の通知一覧を開き、テストで開いた URL を確かめられるようにする

**Non-Goals:**

- ポップオーバーの見出し行（Mewbell・設定・再読み込み）に、全アカウントをまとめた導線を置くこと
- リポジトリの見出しから `repo:` で絞った一覧を開くこと、`reason:participating` を付けること
- ブラウザ側でログインしているアカウントの切り替え（URL で GitHub のユーザーを指定する手段が無い）

## Decisions

### D1: URL の組み立てと検査は `ThreadWebURL` に置く

`ThreadWebURL.notificationsPage(endpoints:) -> URL?` を足し、`endpoints.webBaseURL.appending(path: "notifications")` を `isOpenable(_:host:)` に通したものを返す。リポジトリのページ（`repositoryPage`）と同じ形にして、ブラウザで開く URL の検査を 1 か所にまとめる。

- 代替案: `APIEndpoints` に `webNotificationsURL` を足す。`APIEndpoints` はトークンを送ってよい相手を決める型で、ブラウザで開く URL の検査は持っていないので、置き場所が分かれる。採らない

### D2: 開くのは `NotificationStore.openWebNotifications(for:)`

`func openWebNotifications(for account: AccountID)` を足し、`APIEndpoints(host: account.host)` と D1 で URL を作って `openURL` に渡す。作れなければ何もしない。既読化（`perform`）は呼ばない。`openURL` を `NotificationStore` に閉じ込めているので、View から `NSWorkspace` を直接呼ばずに済み、テストでは既存の `openURL` の記録で開いた URL と、PATCH・PUT が送られていないことを確かめられる。

- 代替案: View で `@Environment(\.openURL)` を使う。テストで開いた URL を確かめられず、スレッドを開く経路と検査の場所が分かれる。採らない

### D3: 見出しのボタン

`ThreadListActions` に `openWebNotifications: (AccountID) -> Void` を足し、`AccountSectionView.header` の `Spacer` の後、「すべて既読」の前にアイコンのボタン（`.plain`、SF Symbols の `arrow.up.forward.square`、`MarkAllReadButton` と同じ大きさと色）を置く。ツールチップとアクセシビリティのラベルは `Open notifications on <host>`。ボタンはトークンの状態や取得の状態で条件を付けずに出す（spec のとおり、止まっているアカウントでも Web では通知を見られる）。無効のアカウントの区画は `NotificationListView` が出さないので、ここでは条件を足さない。

- 代替案: 見出しの右クリックのメニューに入れる。見つけにくいので採らない

### スレッドと actor の境界

`NotificationStore` と View はどちらも `@MainActor` で、ボタンの処理はメインスレッドの上で同期的に終わる（URL の組み立てと `openURL` の呼び出しだけで、ポーラーの actor にもネットワークにも触れない）。テストでの差し替えは、既存の `openURL` クロージャ（`NotificationStoreOpenTests` の記録）をそのまま使う。

## セキュリティ

- トークンの流れ: このボタンはトークンを取得も参照もしない。URL にもトークンを含めない
- URL を開く処理（security.md「ブラウザで開く URL は `https` で、ホストがアカウントの Web ホストと一致するものだけにする」）: ホストは `hosts.yml` の解析で検証済みの値を、さらに `APIEndpoints(host:)` が `GhIdentifier.isValidHost` で検証する。組み立てた URL は `ThreadWebURL.isOpenable` で、スキームが `https`、ホストが一致、ポートとユーザー情報が無いことを確かめてから開く。API のレスポンスに含まれる URL は使わない。ユニットテストで確かめる
- gh サブプロセス・ネットワーク・ログ・通知の本文: 触れないので、該当する項目は無い
- 依存: 追加しない

## Risks / Trade-offs

- [ブラウザで同じホストの別のアカウントにログインしていると、そのアカウントの一覧が開く] → URL でユーザーを指定する手段は無いので受け入れる。ツールチップにはホストだけを出し、ユーザーの一覧を開くとは書かない
- [見出しのボタンが 1 つ増え、ホスト名が長いと見出しの文がさらに省略される] → ホストの文は今も `.truncationMode(.middle)` で省略している。アイコン 1 つ分なので受け入れ、手元で長いホスト名の見え方を確かめる
