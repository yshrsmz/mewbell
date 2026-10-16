# Design

## Context

動機は proposal.md の Why を参照。今の形は次のとおり。

- アカウントの見出し（`AccountSectionView.header`）は、`DisclosureButton`、`Spacer`、`OpenWebNotificationsButton`、`MarkAllReadButton` を `HStack(spacing: 6)` に並べている。後ろの 2 つは常に出ていて、ホバーで出すボタンではない
- `OpenWebNotificationsButton` は `Image(systemName: "arrow.up.forward.square")` を枠なしで置き、`HoverHighlightButtonStyle(outset: 3)` で押せる範囲を広げている。`MarkAllReadButton` も `checkmark.circle` を枠なしで `ConfirmingButton` に渡し、`outset: 3` を付けている。どちらも書体は既定の 13pt
- スレッドの行とリポジトリの見出しのボタンは、`HoverActionButtons.icon(_:)` で記号を 22pt 四方の枠に置き、`outset` は 0。記号は `envelope.open`（既読）と `checkmark`（Done）
- `MarkAllReadButton` は確認の状態を自分の `@State` に持ち、`ThreadRow.swift` に置かれている。リポジトリの見出しは確認の状態を `RepositoryGroupView` の `@State` に持ち、`ConfirmingButton` に `Binding` で渡している
- まとめた Done は、`NotificationStore.markDone(_ group: RepositoryGroup, in:)` が `perform(_:in:)` で一覧から外し、`AccountPoller.perform(_ actions: [ThreadAction])` が 1 件ずつ順に送る。止まったとき・トークンが無いとき・認証エラーとレート制限で残りを送らない処理と、失敗を 1 つにまとめる処理は、この `perform` にある
- アカウントの見出しの高さは `ListLayout.headingHeight`（24pt）を下限にしている。22pt のボタンはこの中に収まる
- `outset` は `CommandRow` のコピーのボタンでも使っている

## Goals / Non-Goals

**Goals:**

- アカウントの見出しのボタンと、行・リポジトリの見出しのボタンの記号の枠を 1 つの部品にする（同じ大きさを 2 か所で書かない）
- すべて Done を、リポジトリのグループの Done と同じ経路（`NotificationStore.perform` → `AccountPoller.perform`）に載せる
- アカウントの見出しの確認の状態を 1 か所に持ち、すべて既読とすべて Done が同時に確認の表示にならないようにする
- 見出しにホバーのボタンを重ねる仕組み（出さないときに隠す、幅を測って中身を手前で省略する）を、リポジトリの見出しとアカウントの見出しで 1 つにする

**Non-Goals:**

- すべて既読の振る舞い（`PUT /notifications`、押せる条件、確認の文）は変えない
- ポーラーの `perform` と、リクエストの送り方は変えない
- 歯車と再読み込みのボタン（16pt の枠と余白 4）の大きさは変えない

## Decisions

### D1. 記号の枠を `ActionIcon` にして `ListLayout.swift` に置き、行・リポジトリ・アカウントの見出しで共有する（A1・A9）

`HoverActionButtons.icon(_:)` と `iconSize` を、`ListLayout.swift` の `ActionIcon`（`systemName` を受け取り、記号を `ListLayout.actionIconSize`（22）四方の枠の中央に置く View）に移す。`HoverActionButtons` の `rowSize` は `ListLayout.actionIconSize` から計算する。スレッドの行、リポジトリの見出し、アカウントの見出しの 3 つのボタンは、どれも `ActionIcon` を使う。

`ActionIcon` という型を足すのは、spec の「アカウントの見出しのボタンの大きさ」が、リポジトリの見出しのボタンと同じ大きさを求めるため（大きさを 2 か所に書くと片方だけ変わる。A9）。置き場所を `ListLayout.swift` にするのは、記号の枠は一覧の寸法で、ホバーで重ねるボタンの並び（`HoverActionButtons`）とは別の部品だから（A1。UI の層の中の置き場所。一覧の寸法は `ListLayout` に集めている）。

採らなかった案:

- アカウントの見出しから `HoverActionButtons.icon(_:)` をそのまま呼ぶ: 型を足さずに済むが、ホバーしないボタンが「ホバーのボタン」の部品に依存し、読み手を迷わせる
- `.imageScale(.large)` で囲みのある記号を大きく描く: すべて既読が Done に見える問題が残り、行・リポジトリの記号とも揃わない。Web の通知一覧の囲みのある記号は、22pt の枠に入れて押せる範囲を揃えれば足りる（四角の枠から出ていく矢印は外部へ開く慣用の形なので、囲みを外さない）

### D2. アカウントの見出しのボタンは、`outset` を付けずに 22pt の枠で並べる（A16）

`OpenWebNotificationsButton` の記号を `ActionIcon("arrow.up.forward.square")` にし、`HoverHighlightButtonStyle()`（`outset` 0）にする。すべて既読とすべて Done は `ActionIcon("envelope.open")` と `ActionIcon("checkmark")` を `ConfirmingButton` に渡す。3 つのボタンは `HoverActionButtons` に並べる（D8）。並びは Web の通知一覧、すべて既読、すべて Done で、リポジトリの見出しの「既読にする」「Done にする」の順に合わせる。

22pt の枠は見出しの高さの下限 24pt に収まるので、見出しの高さは変わらない。押せる範囲は 22pt 四方になり、A16 の「20pt 以上」を満たす。`ConfirmingButton` の `outset` の引数は、使うところが無くなるので消す（A9）。`HoverHighlightButtonStyle` の `outset` は `CommandRow` が使うので残す。

### D3. 確認の状態は `AccountSectionView` の `@State` に 1 つの値で持つ（A3・A4）

`AccountSectionView` に `@State private var confirming: AccountHeadingAction?`（`enum AccountHeadingAction { case markAllRead, markAllDone }`）を置き、2 つのボタンにはそれぞれ「自分が確認中か」の `Binding<Bool>` を渡す。片方を true にすると値が置き換わるので、もう片方の確認は解ける（spec「アカウントの見出しの確認の表示」）。`ConfirmingButton` はすでに `@Binding var confirming: Bool` を受け取るので、変えなくてよい。

`MarkAllReadButton` は自分の `@State` をやめ、`confirming: Binding<Bool>` を受け取る形にする。プレビューの `confirming: true` は `.constant(true)` で渡す。確認の状態はポップオーバーを閉じれば消えてよいので View の `@State` のまま（A3）。

採らなかった案:

- 2 つのボタンがそれぞれ `@State` を持ち、`onChange` で相手を解く: 状態が 2 か所に分かれ、相手を解く処理を両側に書くことになる

### D4. すべて Done のボタンと文言は、すべて既読と同じ形の型にし、アカウントの見出しのボタンを 1 つのファイルにまとめる（A1・A4）

`MarkAllDoneButton`（`count`、`threadIDs`、`isEnabled`、`confirming: Binding<Bool>`、`action`）と `MarkAllDoneLabels`（`count`。`done`・`confirmation`（`Mark N as done?`）・`help(confirming:)`・`accessibilityLabel(confirming:)`）を足す。確認を解く値（`target`）はスレッド ID の並びにする（件数と最新が同じでもスレッドが入れ替わったら解く。spec「すべて Done のボタンの確認」。リポジトリの Done と同じ）。

`MarkAllReadButton` と `MarkAllReadLabels` は今 `ThreadRow.swift` にあるが、スレッドの行の部品ではない。新しいファイル `UI/AccountHeadingButtons.swift` に、`MarkAllReadButton`・`MarkAllReadLabels`・`MarkAllDoneButton`・`MarkAllDoneLabels` をまとめる（名前は変えないので、`docs/architecture.md` の更新は要らない）。`OpenWebNotificationsButton` は今のファイルのまま。

文言を型に分けるのは、確認中かどうかで変わるツールチップと読み上げをユニットテストで確かめるため（A4。`MarkAllReadLabels`・`RepositoryActionLabels` と同じ）。

### D5. すべて Done の入口は `NotificationStore.markAllDone(in:)` にし、押したときの一覧を store から読む（A2・A14）

`ThreadListActions` に `markAllDone: (AccountID) -> Void` を足し、`MenuBarContentView` で `NotificationStore.markAllDone(in:)` につなぐ。`markAllDone(in:)` は `feeds[account]?.threads` を `updatedAt` の新しい順に並べ直し、`perform(threads.map { .done(threadID: $0.id) }, in: account)` を呼ぶ。対象が 0 件なら `perform` が何もしない。並べ直すのは、`feeds` の並びが新しい順だと決まっていないため（`ThreadListMerge.merge` は受け取ったスレッドの後に今の一覧を並べるだけで、並べ替えない）。spec「リポジトリのグループの既読化と Done のリクエストの順」の「更新日時が新しい順」を守る（リポジトリのグループは `RepositoryGroup.groups(from:)` が並べ替えている）。

View が表示している一覧は `feeds` そのもの（どちらも `@MainActor`）で、確認の途中で一覧のスレッドが変わったら確認が解ける（D4 の `target`）。そのため、2 回目を押したときの `feeds` は、ユーザーが確認の表示で見ていたスレッドと同じになる（spec「アカウントのすべて Done」の「押したときに表示していたスレッドだけ」）。押した後に届いたスレッドは、`perform` が一覧から外した後に届くので、対象に入らない。

採らなかった案:

- View から `[NotificationThread]` を渡す（リポジトリのグループと同じ）: 対象は同じになるが、`ThreadListActions` の引数が増え、すべて既読の `markAllRead: (AccountID) -> Void` と形が揃わない

### D6. ポーラーは変えない（A7・A9）

`AccountPoller.perform(_:)` は、配列の順に 1 件ずつ送り、止まったとき・トークンが無いとき・認証エラーとレート制限で残りを送らず、失敗を最後の 1 つで記録する。これは spec「アカウントのすべて Done のスレッドごとの扱い」が求める振る舞いそのものなので、ポーラーに新しいメソッドは足さない。配列の順は D5 で並べ直した順（更新日時が新しい順）になる。

### D7. ポップオーバーの見出しは `account.host` を出し、`hostLabel` は設定ウィンドウだけが使う（A4）

`AccountSectionView.title` の `OneLineText(text: account.hostLabel, truncation: .middle)` を `account.host` にする。省略のしかた（中央を省略し、省略したときだけツールチップで全体を出す）と、薄い色・11pt は変えない。`Account.hostLabel`（`host — 種別`）は `SettingsView` の Accounts タブが使い続けるので残し、doc コメントの「見出しと設定画面」を「設定画面」に直す。

採らなかった案:

- github.com のときだけホスト種別を省く: GHE Cloud と GHES もホスト名で種類が分かり（`*.ghe.com` は GHE Cloud）、見出しの幅は 3 つ目のボタンでさらに狭くなるので、どのホストでも省く
- 設定ウィンドウからも省く: settings spec が求めていて、幅にも余裕がある。ポップオーバーの見出しの問題（幅と、同じ名前が続く見え方）は設定ウィンドウには無い

### D8. アカウントの見出しのボタンは、リポジトリの見出しと同じ部品でホバーの間だけ重ねる（A9・A16）

`HoverActionButtons` を、ボタンの並びを `@ViewBuilder` で受け取る形に変える（今は「既読にする」のボタンを中に持ち、「Done にする」だけを受け取る）。アカウントの見出しの「すべて既読」は確認のボタンで、すぐ既読にする行・リポジトリの「既読にする」と形が違い、先頭に Web の通知一覧も並ぶため。行とリポジトリの見出しの「既読にする」は、`HoverActionButtons.markReadButton(_:action:)` で作る（2 か所で同じボタンを書かないため）。ボタンの間と左右のすき間を押しても下の見出しに届かないようにする処理は、今のまま `HoverActionButtons` に残す。

見出しにボタンを重ねる処理（`overlay(alignment: .trailing)`、出さないときに見えず・押せず・読まれないようにする、`onGeometryChange` でボタンの並びの幅を測る）を、`View.headingActions(isShown:width:buttons:)` にして `HoverActionButtons.swift` に置き、リポジトリとアカウントの見出しで使う。spec の「リポジトリの見出しの操作のボタンの配置」と「アカウントの見出しの操作のボタンの配置」が同じ振る舞いを求め、2 か所に書くと片方だけ直す不具合の種になるため（A9）。

アカウントの見出しは、`AccountSectionView` が `isHovering` と `actionsWidth` の `@State` を持ち、`DisclosureButton` に `isHovering` と `trailingInset`（ボタンを出している間はボタンの並びの幅）を渡す。ボタンを出すのは、マウスを載せている間か、確認の表示の間（`confirming != nil`）。見出しの `HStack` と `Spacer` はやめ、`DisclosureButton` を行の幅いっぱいにして、塗りと折りたたみの範囲をリポジトリの見出しと同じにする。折りたたみの操作を出さない見出し（止まっている、トークンを取れないなど）でも Web の通知一覧を出すので、`DisclosureButton` の畳めないときの表示にも `trailingInset` を効かせる。

コンテキストメニューと VoiceOver の操作は、リポジトリの見出しと同じく見出しに付ける。Web の通知一覧はすぐ開き、すべて既読とすべて Done は `confirming` を設定して確認の表示にするだけにする。VoiceOver で確認の表示にしたときは `AccessibilityNotification.Announcement` で知らせる。すべて既読とすべて Done は、押せないときはメニューの項目を `disabled` にし、VoiceOver の操作には出さない（`accessibilityActions` の `@ViewBuilder` で条件を付ける）。

採らなかった案:

- アカウントの見出しにだけ、別のホバーの仕組みを書く: リポジトリの見出しと同じ振る舞いが 2 か所に分かれる
- `HoverActionButtons` に Web の通知一覧の枠（`leading`）を足し、「既読にする」は中に残す: アカウントの「すべて既読」は確認のボタンなので、どのみち中の「既読にする」を使えない

## actor と @MainActor の境界

- View（`AccountSectionView`、各ボタン）と `NotificationStore` は `@MainActor`。確認の状態、一覧から外す処理、`threadChanges.threadRemoved` はメインスレッドで動く
- `AccountPoller` は actor。`NotificationStore.perform` が `Task { await poller.perform(actions) }` で渡し、リクエストはポーラーの上で 1 件ずつ送る（今のリポジトリのグループと同じ）

## テスト

- `MarkAllDoneLabelsTests`: 文言（`Mark N as done?`、確認中かどうかで変わるツールチップと読み上げ）
- `NotificationStoreActionTests`: `markAllDone(in:)` が一覧のスレッドをすべて外し、ポーラーに Done の配列を 1 回渡すこと、一覧が空なら何もしないこと、ほかのアカウントの一覧に触れないこと
- ポーラーの振る舞い（順、打ち切り、止まったとき、失敗のまとめ）は `GroupActionPollingTests` が `perform(_:)` を確かめているので、足さない（A12。入口が変わるだけで、削ったら見逃す不具合が無い）
- 記号の大きさ・塗りの範囲・見出しの高さは、ユニットテストの `NSHostingView` では確かめにくい（`ImageRenderer` はボタンを描かない）。手元のアプリで、リポジトリの見出しのボタンと並べて見比べる項目として tasks に置く
- ネットワークは今までどおり `FakeHTTPTransport` で差し替える（A5）

## セキュリティ

- トークンの流れは変えない。トークンは `AccountPoller` が 1 件ごとに `TokenProviding`（メモリ上の actor）から読み、`GitHubAPIClient` の Done のメソッドでそのアカウントの API ベースへの `DELETE` に付けて送る。永続化はしない。アカウントの削除・無効化・終了でトークンを捨てたら、残りのスレッドへは送らない（`perform` の `isDiscarded` の確認。spec「リポジトリのグループの既読化と Done の途中で止まったとき」）
- `.claude/rules/security.md` との対応:
  - トークンの扱い: 新しい保持先を作らない。確認の状態とボタンの文言にトークンは入らない
  - gh サブプロセス: 触れない（`perform` のトークンの読み直しはメモリを読むだけで、gh を起動しない）
  - ネットワーク: 新しい送り先を作らない。既存の `DELETE /notifications/threads/{id}` を、オリジン検査・リダイレクトの拒否・キャッシュなしの `GitHubAPIClient` から送る
  - URL を開く処理: Web の通知一覧のボタンは記号と大きさだけを変え、開く URL（`ThreadWebURL.notificationsPage`）と検証は変えない。すべて Done はブラウザを開かない
  - 送る数: 1 回の操作で最大 500 件の `DELETE` を 1 件ずつ順に送る。認証エラーとレート制限で打ち切るので、制限を越えて送り続けない

## Risks / Trade-offs

- [500 件の一覧をすべて Done にすると、送り終えるまで数十秒〜数分かかる] → 一覧からはすぐに外すので、待たせる表示は要らない。途中で止まったスレッドは次の取得で一覧に戻る。確認の文に件数を出すので、多いことは押す前に分かる
- [すべて既読と違い、一覧に出ていない未読は Done にならない] → spec のとおり。確認の文は一覧の件数（`Mark N as done?`）を出すので、対象が一覧のスレッドであることが分かる
- [見出しのボタンが 3 つになり、ユーザー名とホスト名に使える幅が減る] → 22pt × 3 と間隔で約 70pt。今の 2 つ（約 40pt と間隔 6）より約 30pt 減るが、「ポップオーバーの文字の読みやすさの幅と省略」の省略の順（ホスト名から、次にユーザー名の末尾）はそのまま効く
- [記号を替えるので、今の使い方に慣れたユーザーが戸惑う] → ツールチップと読み上げの文は今のまま（すべて既読）で、記号が行とリポジトリの「既読にする」と同じになるので、意味は取りやすくなる
