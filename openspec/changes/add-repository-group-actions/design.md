# Design

## Context

スレッドへの操作は、次の経路で流れている。

- View: `ThreadRow` が行にマウスを載せている間だけ `ThreadActionButtons`（`ThreadRow.swift` の private な型。22pt 四方のボタン 2 つ）を `overlay` で重ね、行の `Button` のラベルに `.mask` を掛けて、ボタンの範囲と手前の 16pt（`titleFade`）の件名を消している。行の塗りは、行全体のホバーの状態を `HoverHighlightButtonStyle(isHovering:)` に渡して、ボタンに載せている間も出し続ける
- 操作の受け渡し: `ThreadListActions` のクロージャ（`markRead`、`markDone`）→ `MenuBarContentView` → `NotificationStore.markRead/markDone` → `perform(_:in:)` が `feeds` からすぐ外し、`threadChanges.threadRemoved` で macOS の通知を取り下げ、`AccountPoller.perform(_:)` を呼ぶ
- ポーラー: `AccountPoller.perform(_ action: ThreadAction)`（`AccountPoller+ThreadActions.swift`）が `HiddenThreads.beginRequest` で隠し、状態から外し、トークンを待ち、止まっていなければ `GitHubAPIClient.markThreadRead/markThreadDone` を送り、`HiddenThreads.endRequest` と `unconditionalRequested = true` の後に、失敗を `FeedRecorder.recordActionFailure` で記録する。知らせる失敗は、後の失敗で置き換わる

リポジトリの見出しは `RepositoryGroupView` が `DisclosureButton` で描いている。`DisclosureButton` は `HoverHighlightButtonStyle()` を引数なしで使うので、上に別のボタンを重ねると、そのボタンに載せたときに見出しの塗りが消える。

アカウントの見出しの「すべて既読」は `MarkAllReadButton`（`ThreadRow.swift`）で、`@State confirming` を持ち、5 秒の待ち、`isEnabled`・`count`・`newest` の変化、`onDisappear` で確認を解く。文言は `MarkAllReadLabels` で決め、単体テストしている。

## Goals / Non-Goals

**Goals:**

- spec の ui「リポジトリの見出しの操作」と polling「リポジトリのグループの既読化と Done」を、既存のスレッドの操作の経路（一覧からの外し方、隠し方、通知の取り下げ、失敗の記録）に載せて満たす
- 確認の表示（5 秒、変化で解く）の仕組みを、すべて既読とリポジトリの Done で 1 つにする
- 行と見出しのホバーのボタンの重ね方（ボタンの下の文字を消す、ボタンに載せても塗りを出し続ける）を 1 つにする

**Non-Goals:**

- リポジトリ単位の既読のエンドポイント（`PUT /repos/{owner}/{repo}/notifications`）は足さない（spec で使わないと決めた）
- アカウント単位の Done は足さない
- アカウントの見出しの「すべて既読」の振る舞いは変えない（確認の仕組みを共有するだけ）
- 見出しの山形とアイコンの縦の揃え方は変えない

## Decisions

### D1. ポーラーの `perform` を複数のスレッドを受け取る形に広げ、1 件の操作もそれを通す（A3・A7・A9）

`AccountPoller.perform(_ action: ThreadAction)` を `perform(_ actions: [ThreadAction])` に変え、1 件の操作は要素 1 つの配列で呼ぶ。中では次の順に行う。

1. すべての対象を `HiddenThreads.beginRequest` で隠し、状態から外して 1 回だけ `publish` する
2. 対象を配列の順に 1 本のループで回す。送っている間は、1 件ごとにトークンをメモリから読み直し、止まっていないか（`state.phase.isStopped`）と `stop()` の後でないか（`isDiscarded`）を確かめ直す。止まっていれば残りを送らず、それまでの失敗も記録しない（2 回目の code-review の指摘で、止まる前の失敗を知らせていたのを改めた）。トークンが無ければ `.noToken` を失敗として残りを送らない。結果が `.unauthorized` か `.rateLimited` でも残りを送らない
3. 送ったスレッドも送らなかったスレッドも、そのたびに `HiddenThreads.endRequest` を呼び、同じ同期の区間で `unconditionalRequested = true` にする
4. 失敗が 1 つでもあれば、最後の失敗だけを `recordActionFailure` で 1 回記録する（知らせる失敗を 1 つにする。spec の「知らせる失敗は 1 つ」）

トークンと停止を 1 件ごとに確かめ直すのは、送るのに数秒〜十数秒かかる間に、アカウントが止まったり、無効化・削除・終了でトークンを捨てたりしても、手元に取ったトークンで残りを送り続けないため（security.md の「トークンを破棄する」。code-review の指摘で、最初は 1 回だけ待っていた）。`AccountPoller.stop()` は取得のループの Task だけを取り消すので、操作の Task は `isDiscarded`（`loop` の `discarded` を読むだけのプロパティ。A10 の「extension に分けた型の中に閉じるメンバー」として `private` を外す）で見る。トークンの読み直しはメモリの actor を読むだけで、gh は起動しない。

`unconditionalRequested` は取得を始めるときに読んで消すので、最後に 1 回立てるだけでは、送っている途中に始まった取得が条件付きのまま走り、先に結果が出たスレッドの「次の取得は条件なし」（polling「スレッドの既読化」）が守れない。1 件の結果が出るたびに `endRequest` と一緒に立てる。`endRequest` を記録の前に済ませるのは、今の 1 件の操作と同じ理由（知らせている間に始まった取得でスレッドが戻らないまま知らせが消えないように）。

順に送ることと、認証エラー・レート制限で打ち切ることは、振る舞いとして polling の spec に書いたので、`docs/architecture.md` には足さない。既読と Done が混ざった配列は作らないが、型では禁じない（1 件ずつの結果の扱いは操作の種類によらず同じで、禁じるための型を足す要件が無い。A9）。記録する操作の種類は、最後に失敗したスレッドの操作から決める。

採らなかった案:

- グループ用のメソッドを別に足し、1 件の `perform` を残す: 隠し方・外し方・トークンの扱い・`unconditionalRequested` の順序が 2 か所に分かれ、片方だけ直す不具合の種になる
- 並行して送る（`TaskGroup`）: GitHub は変更のリクエストを並行して送ると二次レート制限になりやすいと案内している。グループの件数は多くても数十件で、順に送っても待ち時間は数秒に収まる
- リポジトリ名をポーラーに渡し、ポーラーが対象を決める: spec の「押したときにそのグループに表示していたスレッド」は View が持っている一覧なので、対象のスレッド ID を渡す方が、押した後に届いたスレッドを含めない約束が素直に守れる

### D2. `NotificationStore` と `ThreadListActions` は、スレッドの配列を受け取る入口を足す（A4・A14）

`ThreadListActions` に `markGroupRead: (RepositoryGroup, AccountID) -> Void` と `markGroupDone: (RepositoryGroup, AccountID) -> Void` を足し、`MenuBarContentView` で `NotificationStore.markRead(_ group: RepositoryGroup, in:)`・`markDone(_ group: RepositoryGroup, in:)` につなぐ。`NotificationStore` の `perform(_:in:)` も配列を受け取る形に変え、対象をすべて `feeds` から外し、それぞれ `threadChanges.threadRemoved` を呼び、ポーラーの `perform` を 1 回呼ぶ。対象が 0 件なら何もしない。ポーラーがまだ無いときの扱い（既読は `pendingReads` に取っておき、Done は何もしない）は今のまま、スレッドごとに当てはめる。

View が渡すのは押したときの `RepositoryGroup`（値）なので、押した後に届いたスレッドは対象に入らない。

### D3. 確認の表示は、`MarkAllReadButton` から確認の部分を `ConfirmingButton` に切り出して共有する（A3・A4・A9・A16）

5 秒の待ち、`isEnabled` が false になったとき・対象が変わったとき・`onDisappear` で解く処理を、新しいファイル `UI/ConfirmingButton.swift` の `ConfirmingButton` に移す。確認の状態は `@Binding var confirming: Bool` で受け取る。コンテキストメニューと VoiceOver の操作から確認の表示にするため、状態を持つのは見出しの View（`RepositoryGroupView` の `@State`）にする必要がある。`MarkAllReadButton` は `@State confirming` を持って `ConfirmingButton` に渡す薄い型にする（`init(confirming:)` のプレビュー用の引数は残す）。

`ConfirmingButton` の引数は、元の表示のアイコン、確認の文、ツールチップとアクセシビリティのラベル（確認中かどうかで変わる）、`isEnabled`、確認を解く値（`target`。`Equatable` な値をジェネリックで受け取る）、`outset`、実行のクロージャ。すべて既読は時刻で区切るので、件数と最新の更新日時の組（`MarkAllReadButton` の private な `Target`）を渡す。リポジトリの Done はスレッドごとに効くので、グループのスレッド ID の並びを渡し、件数と最新が同じでもスレッドが入れ替わったら確認を解く（code-review の指摘で、最初は件数と最新だけで解いていた）。VoiceOver の操作で確認の表示にしたときは、表示が変わるだけでは何も読まれないので、`AccessibilityNotification.Announcement` で確認を待っていることを知らせる。見た目（確認の文を `.subheadline.weight(.semibold)`・アクセントカラー・`fixedSize` で出す）は今の `MarkAllReadButton` のまま。

確認の状態は、ポップオーバーを閉じれば消えてよいので View の `@State` に置く（A3）。新しい型を足すのは、spec の 2 つの要件（すべて既読とリポジトリの Done）が同じ確認の振る舞いを求め、2 か所に書くと片方だけ直す不具合の種になるため（A9）。

採らなかった案:

- `MarkAllReadButton` を複写してリポジトリ用のボタンを作る: 5 秒の待ちと解く条件が 2 か所に分かれる
- `ViewModifier` にする: ボタンのアクション（1 回目は確認、2 回目は実行）とラベルの切り替えを包むので、ボタンの型にする方が読みやすい
- 確認の代わりに `confirmationDialog` を出す: ユーザーと決めたとおり、見出しの確認の表示にそろえる。メニューバーのポップオーバーでのダイアログの挙動を確かめる手間も要らない

### D4. ホバーで重ねるボタンの並びは `HoverActionButtons` として行と見出しで共有する（A9・A16）

`ThreadRow.swift` の private な `ThreadActionButtons` を、新しいファイル `UI/HoverActionButtons.swift` の `HoverActionButtons` に移す。「既読にする」のボタンは今のまま 22pt 四方で、「Done にする」の位置にはビューを受け取る（行は今のボタン、見出しは `ConfirmingButton`）。

文字との重なりの避け方は、行と見出しで分ける。

- 行: 今のまま、件名をボタンの下でマスク（`titleFade`）で消す。件名は 2 行まで折り返すので、ボタンの幅だけ件名を狭めると折り返しが変わり、行の高さが動く（spec の「件名の折り返しを変えない」）。行のボタンの幅は固定なので、マスクの幅も今の固定のままにする
- 見出し: マスクで消さず、ボタンを出している間だけ、見出しの中身の右にボタンの並びの幅の余白を空ける。ボタンの並びの幅は `onGeometryChange` で測り（確認の表示はボタンより幅が広い）、`RepositoryGroupView` が `@State` で持つ。見出しは 1 行で中央を省略するので、余白を空けてもリポジトリ名が省略されるだけで高さは変わらず、折りたたんだときの件数は消えない（ui「ポップオーバーの文字の読みやすさ」が件数とリポジトリ名の省略のしかたを決めているので、件数をボタンの下に隠すことはできない）
- 見出しのボタンは常に並べておき、出さないときは透明・押せない・読まれないようにする（`opacity`・`allowsHitTesting`・`accessibilityHidden`）。出してから幅を測ると、最初のホバーの 1 フレームだけリポジトリ名と件数がボタンに重なるため（2 回目の code-review の指摘）。確認の表示に広がる瞬間の 1 フレームは残る（ユーザーと決めた）
- ボタンの間と左右のすき間は、押しても何も起きない背景（`contentShape` と空の `onTapGesture`）で塞ぎ、下の行や見出しに押したことが届かないようにする（行と見出しの両方。行の振る舞いも main から変わる。2 回目の code-review の指摘に対し、ユーザーと決めた）

ボタンの並びを共有するのは、spec の「ボタンに載せても塗りを出し続ける」と、ボタンの大きさ・ツールチップ・読み上げのラベルが、行と見出しの両方に掛かるため。

### D5. `DisclosureButton` にホバーの状態を渡せるようにし、見出しの操作は見出しの外側に重ねる（A16）

`DisclosureButton` に `isHovering: Bool?`（既定 nil）を足し、`HoverHighlightButtonStyle(isHovering:)` に渡す。`RepositoryGroupView` は見出しの全体（`DisclosureButton` と重ねたボタン）の `onHover` で `@State isHovering` を持ち、`DisclosureButton` に渡す（スレッドの行と同じ形）。ボタンは `DisclosureButton` の中に入れず、`overlay(alignment: .trailing)` で重ねる（見出しのクリックと奪い合わないように。行と同じ）。ボタンは見出しの高さ（`ListLayout.headingHeight`、24pt）に収まるので、見出しの高さは変わらない。

重ねたボタンを出す条件は「マウスを載せている、または Done の確認中」にする（確認の表示はマウスを外しても出し続ける）。見出しには、山形のある `DisclosureButton` の外側に `contextMenu`（「Mark All as Read」「Mark All as Done」）と `accessibilityAction(named:)` を付け、どちらの「Done にする」も `confirming = true` にするだけにする。

### D6. 見出しのボタンの文言は `RepositoryActionLabels` で決める（A4）

ツールチップ・アクセシビリティのラベル・確認の文（`Mark N as done?`）を、`MarkAllReadLabels` と同じく View の外の値型 `RepositoryActionLabels`（リポジトリの `owner/name` と件数を持つ）で決め、単体テストする。置き場所は `MarkAllReadLabels` と同じ UI の層にする（A1）。ラベルにはリポジトリ名を入れる（`Mark all in octo/app as read` など）。

### D7. テストでの差し替え（A5・A12）

- ポーラー: 今の `ThreadActionPollingTests` と同じく `FakeHTTPTransport` を使う。順に送ることは、`pausedMethod` で最初の `DELETE` を止めている間に 2 つ目が送られていないことで確かめる（同期的には待たない。A12）。`401`・レート制限で残りを送らないこと、`500` で続けること、知らせる失敗が 1 つで最後の失敗になること、トークンが無いときに送らないこと、送らなかったスレッドが次の取得で戻ることを確かめる
- `NotificationStore`: 今の `NotificationStoreActionTests` の偽のポーラーで、グループの操作がすべての対象を `feeds` からすぐ外し、ポーラーに 1 回だけ配列で渡すことを確かめる
- `RepositoryActionLabels`: 文言の単体テスト
- ホバー・確認の表示の 5 秒・読み上げ: A12 のとおり単体テストせず、手元で確かめる項目として tasks に置く

### D8. actor と `@MainActor` の境界（A2）

View・`NotificationStore`・`ConfirmingButton` の状態は `@MainActor`。ポーラーの `perform` は `AccountPoller` の actor の中で動き、リクエストは actor の上で 1 件ずつ `await` する。順に送る間も actor は再入できるので、取得や別の操作は並行して進む（隠すスレッドは `HiddenThreads` がスレッドごとに数えるので、同じスレッドへの操作が重なっても崩れない）。同じアカウントでグループの操作を続けて押すと、2 つの操作は互いに並行して送られる。spec の「1 件ずつ」は 1 回の操作の中の約束で、人が押す速さなら並行は 2〜3 本に収まるので、アカウントごとの待ち行列は足さない（code-review の指摘に対し、ユーザーと決めた）。

## セキュリティ

- トークンの流れ: トークンは `AccountPoller` が `tokens.currentToken(for:)` でメモリから受け取り、リクエストを 1 件送るたびに読み直して、各リクエストに `GitHubAPIClient` が付ける。ディスク・ログ・View に出さない。アカウントの削除・無効化・終了でトークンを捨てたり、ポーラーを止めたりしたら、残りのリクエストは送らない（D1）
- 送り先: 新しいリクエストの種類は無く、既存の `markThreadRead`・`markThreadDone` を通すので、スレッド ID の検査（1〜20 桁の数字）、API ベースとのオリジン検査、リダイレクトの拒否、キャッシュなしがそのまま掛かる（A6。新しい経路を作らない）
- ログ: 失敗のログは今の `recordActionFailure` の 1 か所（アカウント ID と失敗の種類だけ。スレッドの件名やレスポンスは出さない）
- gh サブプロセス・URL を開く処理: 触れない
- security.md の各項目のテストは今のまま（新しいリクエストの経路が無いので足さない）。トークンの破棄については、送っている途中でトークンを捨てたときと `stop()` したときに残りを送らないテストを `GroupActionPollingTests` に足す

## Risks / Trade-offs

- [件数の多いグループの Done に時間がかかる] → 順に送るので、50 件なら数秒〜十数秒かかる。一覧からはすぐ外すので、ユーザーは待たない。その間の取得で戻らないことは `HiddenThreads` が守る
- [途中でポップオーバーを閉じたりアプリを終了したりする] → 送らなかったスレッドは GitHub の側で未読のまま残り、次の起動の取得で一覧に戻る。取り消せない操作が半端に残ることはあるが、既読・Done とも冪等なので、もう一度行えば済む
- [VoiceOver で Done を選んだ後、確認のボタンを探す必要がある] → 確認の表示はマウスに関係なく見出しに出るので、読み上げの順で見出しの次に来る。手元の VoiceOver で確かめる項目として tasks に置く
- [`ThreadRow` の重ねるボタンを共有の型に移すと、行の見た目が変わるおそれ] → 行のボタンの大きさと位置は変えない。手元で行のホバーの見た目が前と同じことを確かめる
