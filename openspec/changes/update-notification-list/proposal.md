# Proposal

## Why

ポップオーバーの一覧はアカウント → リポジトリの 2 段で全部を開いたまま並べるので、未読が多いアカウントや、よく見ないリポジトリがあると、見たいスレッドまでスクロールが要る。また、スレッドの行には件名しか出ないので、Issue や Pull request を番号で見分けられない（GitHub の一覧やコミットメッセージでは `#1234` で呼ぶことが多い）。

この change は M5（v0.1.0）の公開後の、M4（設定と操作）の UI の延長にあたる改善。

## What Changes

- アカウントの区画とリポジトリのグループを、それぞれ見出しで折りたためるようにする。折りたたんだ見出しには未読の件数を出す
- 折りたたんだ状態は Mewbell が起動している間だけ覚える。ポップオーバーを閉じても残るが、ディスクには保存せず、再起動するとすべて開いた状態に戻る
- 折りたたんだアカウントやリポジトリに新着（macOS の通知の対象になるのと同じ、新しいスレッドか更新されたスレッド）が届いたら、そのアカウントの区画と、新着を含むリポジトリのグループを自動で開く。アカウントの「macOS の通知を出す」がオフでも開く。macOS の通知とメニューバーの件数の扱いは変えない
- スレッドの行の 2 行目（理由と更新日時の行）の先頭に、Issue と Pull request の番号を `#1234` の形で出す。番号はブラウザで開く URL と同じ規則で `subject.url` から読み、読めないとき（Commit、Release、Discussion、形の合わない URL など）は出さない

## Capabilities

### New Capabilities

（なし）

### Modified Capabilities

- `ui`: 「アカウント一覧の表示」のスレッドの行に Issue・Pull request の番号を足す。「一覧の折りたたみ」の Requirement を新しく足す

## Impact

- 変わるコード: `Mewbell/UI/`（`AccountSectionView`、`ThreadRow`、`NotificationListView`、共有の部品の `DisclosureButton.swift`、新規の `ListExpansion.swift`（折りたたみの状態。アカウントごとの `AccountExpansion` を含む）と `RepositoryGroupView.swift`（リポジトリのグループ））、`Mewbell/App/`（`MenuBarContentView`、`MewbellApp.swift`、`AppDelegate` での組み立て）、`Mewbell/GitHubAPI/ThreadWebURL.swift`（番号の読み取りを開く URL の組み立てと共有する）、`Mewbell/GitHubAPI/NotificationThread.swift` と `GitHubAPIClient.swift`（読み取るときに番号を求める）、`Mewbell/Polling/NotificationStore.swift`（新着の判定を持つ）、`Mewbell/Polling/FeedState.swift`（リポジトリのグループ分けを持つ）、新規の `Mewbell/Polling/RepositoryGroup.swift`（`UI/NotificationGrouping.swift` から移す）、新規の `Mewbell/Polling/ThreadChangeDispatcher.swift`（tracker の操作と通知の取り下げを組にして行う）、`NotificationTracker.swift` の `Mewbell/Notifications/` から `Mewbell/Polling/` への移動、`Mewbell/Notifications/SystemNotifier.swift`（判定を `NotificationStore` に渡す）、`Mewbell/Accounts/AccountDiscovery.swift`（`enabledStatuses` と `retainedAccountIDs`）、`ThreadNotifying` の形（新着の判定を `NotificationStore` に移す）
- トークン: 扱わない。折りたたみの状態にも番号にもトークンは関わらず、何も永続化しない
- gh サブプロセス: 触れない
- ネットワーク: 触れない。リクエストもポーリングも変えない
- URL を開く処理: 開く URL の組み立ては変えない。番号の読み取りは表示だけに使い、開く URL と同じオリジン検査（`subject.url` が API ベース URL の下にあり、リポジトリが一致する）を通ったものだけを出す
- 外部依存: 追加しない
