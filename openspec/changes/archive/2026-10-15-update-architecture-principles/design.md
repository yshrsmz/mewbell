# Design

## Context

- 中間の層どうしの、型の参照の向き（コメントの中の型名を除く）は次のとおり。輪になっているのは Accounts↔Polling と Accounts↔Settings の 2 つ。
  - Accounts → Polling: `AccountDiscovery` が `TokenProviding`（`Mewbell/Polling/TokenProviding.swift`）に準拠する
  - Accounts → Settings: `AccountStore` が `AppSettings?` を持ち、読み直しのたびに `ghOverrides` と `disabledAccounts` を読んで `DiscoveryOptions` を作る。読み直しの結果を反映するときにも、`disabledAccounts` で `.disabled` に置き換える（`applyingSettings(to:)`）
  - Polling → Accounts（`Account`・`AccountID`・`DiscoveryState`）、Polling → Notifications、Polling → Settings、Notifications → Accounts、Settings → Accounts（`AccountID`）、Diagnostics → Accounts・Polling・Settings
  - Notifications → Polling は、`SystemNotifier.swift` のコメントに `NotificationStore` と `NotificationTracker` の名前が出てくるだけで、型を使ってはいない
- `TokenProviding` は Polling（`AccountPoller`・`NotificationStore.live`）と Accounts（`AccountDiscovery`）の 2 つの層が使う。今の A1 の「複数の層が使う型は共通の依存先に置く」に照らすと、Polling が Accounts に依存しているので、置き場所は Accounts になる。今の置き場所は、この規則にも合っていない。
- `AccountStore` は `@MainActor` の `@Observable` で、`AppSettings` も `@MainActor` の `@Observable`。どちらも `AppDelegate` が作る。`AppSettings` から `AccountStore` へ変化を伝える経路（`setEnabled`、設定ディレクトリの変更）は、すでに `AppDelegate` のコールバックでつながっている（A14）。
- 書体の約束は A4 の本文の最後の 1 文で、採らなかった案の `ListTypography` と、根拠の update-list-readability D1 がこれに当たる（同じく根拠にある D7 は `GhCommand` の決定）。lint の `fixed_font_size` の `message` は A4 を引いている。
- A6 の行数の上限の例外を使っているのは `Mewbell/GitHubAPI/GitHubAPIClient.swift`（492 行、先頭に `// swiftlint:disable file_length`）だけ。fix-api-client-send-privacy D1 で、この形を選んだ。そのときに採らなかった案の 1 つは、「状態とイベントの取得を別の型にし、送る処理をクロージャで渡す」だった。

## Goals / Non-Goals

**Goals:**

- 中間の層のディレクトリの間に、依存の輪が 1 つも無い状態にする。
- 原則 1 つが 1 つの問いに答えるようにする（A4 から書体を分ける）。
- 関所のファイルの大きさを、行数の上限の例外ではなく型の切り出しで抑える方針にする。

**Non-Goals:**

- `GitHubAPIClient` から関所を切り出すこと。A6 を改めて既知の逸脱に書くまでを、この change で行う。切り出しは `fix-api-client-gateway` で行う。
- 輪を機械的に検査すること（D5）。
- 中間の層に順序を決めること。

## Decisions

### D1. A1 に「中間の層どうしの依存を輪にしない」を足す（A1 を改める）

中間の層どうしは、今までどおり互いの型を使ってよい。ただし、ディレクトリの間の依存を輪にしない。2 つの層の両方が使う型は、もう一方に依存している側の層ではなく、依存されている側の層に置く。今の「複数の層が使うなら共通の依存先に置く」と同じ考え方を、同じ高さの層にも当てはめたもの。

理由は A1 の「理由」に書く（輪になったディレクトリは片方だけでは読めず、テストもできない。輪が無ければ、読む順序が依存から決まる）。

採らなかった案:

- 輪を許したままにする（今の形）: 「同じ高さだから」でどちらに置いてもよくなり、置き場所の判断がレビューのたびに揺れる。A1 の理由（置き場所を決める軸を 1 つにする）に反する。
- 中間の層に順序を決める: 今の A1 の採らなかった案のまま。設定・アカウント・ポーリング・通知は互いの変化に応じて動くので、順序を決めても、参照を間接にする部品が増えるだけになる。輪を禁じるだけなら、今ある参照の大半はそのまま残せる。

### D2. `TokenProviding` を `Accounts/` に移す（A1）

`Mewbell/Polling/TokenProviding.swift` を `Mewbell/Accounts/TokenProviding.swift` に移す。中身とドキュメントコメントは変えない。Polling はすでに Accounts の `Account`・`AccountID`・`DiscoveryState` を使っているので、新しい向きの依存は増えない。

採らなかった案:

- `AccountDiscovery` の準拠を Polling の側の extension に移す: 準拠の宣言だけを動かしても、Polling の extension が Accounts の actor に手を入れる形になり、トークンの持ち主（`CredentialStore` を持つ `AccountDiscovery`）を読むのに 2 つのディレクトリを見ることになる。
- `Shared/` に置く: `Shared/` にはアプリの領域の型（アカウント・トークン）を置かない（A1）。

### D3. `AccountStore` は読み直しの設定をクロージャで受け取る（A1、A5、A14）

`AccountStore` の `settings: AppSettings?` を、`options: @escaping @MainActor () -> DiscoveryOptions` に置き換える。既定値は `{ DiscoveryOptions() }` で、今の `settings` が nil のときと同じ振る舞いになる。読み直しでは、待った後に `options()` を呼んで使う（今の「設定は待った後に読む」の位置を変えない）。`applyingSettings(to:)` は `options().disabled` で `.disabled` に置き換える。

`AppSettings` には、gh の上書き（`ghExecutableOverride`・`ghConfigDirectoryOverride`）と `disabledAccounts` から作る `discoveryOptions: DiscoveryOptions` を足す。`AppDelegate` は `AccountStore(discovery:options:)` に `{ settings.discoveryOptions }` を渡す。こうすると Settings → Accounts の向きだけが残る（`AppSettings` は、もともと `AccountID` を使っている）。

`AccountStore` と `AppSettings` は、どちらも `@MainActor` の型。クロージャは `@MainActor` にして、`@MainActor` の `AppSettings` を読むことを型で示す（`SystemNotifier` の `notifies`・`playsSound` と同じ）。`@Sendable` は要らない。actor の `AccountDiscovery` には、今までどおり呼んだ時点の `DiscoveryOptions` の値を渡す（A2）。`disabledAccounts` は `SettingsTests` が確かめている公開の経路なので、残す。`ghOverrides` は `discoveryOptions` のほかに使う箇所が無くなるので、`discoveryOptions` の中に畳んで消す（A9）。

`DiscoveryOptions` のドキュメントコメント「`AppSettings` から作る」は、`AppSettings.discoveryOptions` の側に書くことにし、`DiscoveryOptions` からは消す。Accounts の型が Settings の型の名前を書かないようにするため。

採らなかった案:

- Accounts に `DiscoveryOptionsProviding` のようなプロトコルを置き、`AppSettings` を準拠させる: 呼ぶ関数は 1 つだけなので、プロトコルにしてもクロージャと同じことしかできず、型が 1 つ増える（A9）。
- `AppDelegate` が読み直しのたびに `DiscoveryOptions` を引数で渡す: `reload` を呼ぶ場所が `AppDelegate` の外（ポップオーバーの `onAppear`、再読み込みのボタン）にもあり、どの場所でも設定を渡す必要が出る。

この「ほかの部品の状態はクロージャで受け取る」というつなぎ方は、型の置き場所ではなく部品のつなぎ方の約束なので、A1 ではなく A14 に書く。A14 を「変化はコールバックで伝え、状態はクロージャで読む」に広げ、A1 には輪を断つ手段として A14 を引く 1 文だけを置く（simplify の指摘を受けて決めた）。

同じ約束に合わせて、`NotificationStore.live` も `AppSettings` を受け取るのをやめ、`preferences` のクロージャを `AppDelegate` から受け取る（code-review の指摘）。Polling → Settings は輪ではないが、改めた A14 に合わせ、同じ用途に 2 つの形を並べないため。

### D7. 依存を輪にしない規則は、すべてのディレクトリに当てはめる（A1）

D1 の理由（輪になったディレクトリは片方だけでは読めず、テストもできない）は中間の層に限らないので、下の層どうし（`GhCLI/`・`GitHubAPI/`）にも当てはめる。今のコードは `GitHubAPI/` → `GhCLI/` の一方向だけで、輪は無い（code-review の指摘を受けて決めた）。

### D4. 書体の約束を新しい原則 A17 に分ける（A4 を改める）

A4 から「書体の大きさはテキストスタイルで指定し、ポイント数を書かない」と、その採らなかった案（`ListTypography`）、根拠のうち書体の分を A17 に移す。A17 の理由は update-list-readability D1 から取る（macOS のテキストスタイルの大きさや、文字の大きさの設定の変化に追従する）。根拠は update-list-readability D1 と、lint の `fixed_font_size`。A4 の根拠からは update-list-readability D1 と lint の `fixed_font_size` を外し、D7 は残す（`GhCommand` の根拠のため）。`.swiftlint.yml` の `fixed_font_size` の `message` の ID を A17 に引き直す。

採らなかった案:

- A16（押せる要素の見た目）に入れる: A16 はボタンのスタイルと押せる範囲の原則で、書体は押せない要素にも効く。

### D5. 輪はレビューで守り、機械的な検査はまだ足さない（A1、A9）

輪が無いことは、A1 の本文とレビューで守る。輪がまた入ることが続いたら、検査のスクリプトを足す。

採らなかった案:

- 型の宣言とその参照を grep で突き合わせるスクリプトを足す: コメントの中の型名で誤検知する（Context の Notifications → Polling）。誤検知を避けるには Swift のコメントを除く処理が要り、今の頻度では見合わない（A9）。

### D6. A6 を「関所を小さな型に切り出す」に改め、`GitHubAPIClient.swift` を既知の逸脱に書く（A6 を改める）

A6 の「行数の上限でファイルを分けるときも、関所の内側は分けずに、そのファイルだけ上限を緩める」を次の形に改める。関所のファイルが行数の上限に当たったら、関所（送り先の検査をして `Authorization` を付けて送る処理と、それが使う `HTTPTransport`）を小さな型に切り出して、その型だけのファイルに置く。その型が外に見せるのは、検査を通る入口だけにする。上限は緩めない。今の形（`swiftlint:disable file_length`）は、また提案されそうなので「採らなかった案」に移す。理由は「関所のファイルが際限なく大きくなれ、関所の範囲が読みにくくなる」。

fix-api-client-send-privacy D1 では、「取得の処理を別の型にして、送る処理をクロージャで渡す」案を採らなかった。新しい形はこれとは違い、関所そのものを型にする。その型を作れれば、検査を通る入口から送れる。ただ、入口の中で検査をするので、関所が 1 か所であることは変わらない。この違いを、A6 の採らなかった案に書き分ける。

`GitHubAPIClient.swift` の `// swiftlint:disable file_length` を「既知の逸脱」に書き、直す change を `fix-api-client-gateway` とする。lint の `authorization_header_outside_client` の `message`（「`GitHubAPIClient.send` だけ」）は今の形のまま正しいので、この change では変えない。切り出しの change で直す。

## Risks / Trade-offs

- [`AccountStore` の初期化の引数が変わり、テストの組み方を直す箇所が多い（`AccountStoreTests` と `GhDiagnosticsTests`）] → 引数は `options: { settings.discoveryOptions }` に置き換えるだけで、テストが確かめる振る舞い（無効なアカウントの扱い、設定ディレクトリの変更）は変えない。今のテストがそのまま通ることで確かめる。
- [クロージャにすると、`AccountStore` がいつ設定を読むかが型から読み取りにくくなる] → 読む位置は今と同じ 2 か所（読み直しの開始と結果の反映）で、プロパティのコメントにそのことを書く。
- [A6 を改めてから切り出しの change が終わるまで、既知の逸脱が残る] → 逸脱の表に直す change の名前を書き、`handover.local.md` の ToDo に置く。

## セキュリティ

トークンの流れは変えない。`AccountDiscovery`（actor）が `gh auth token` でトークンを取り、`CredentialStore` の中のメモリにだけ持つ。ポーラーは `TokenProviding` を通して、取得の間だけ受け取る。破棄はアカウントの無効化・アプリの終了時に、今までどおり行う。この change で変わるのは、`TokenProviding` の宣言のファイルの置き場所だけ。

`.claude/rules/security.md` の項目への対応:

- トークンの扱い: `TokenProviding` の中身、`AccessToken` の伏せ字、ログは変えない。
- gh サブプロセス: `GhOverrides`（gh のパスと設定ディレクトリの上書き）を、`AppSettings` から直接ではなくクロージャ経由で受け取るだけ。値の検証と、gh を起動する処理（`GhLocator`、`GhClient`、`GhEnvironment`）は変えない。
- ネットワーク、URL を開く処理、アプリとビルドの設定、依存: 触れない。
- 既存のテスト（`GhEnvironment` の環境変数の除去、`AccountDiscovery` のトークンの破棄など）は変えずに通す。
