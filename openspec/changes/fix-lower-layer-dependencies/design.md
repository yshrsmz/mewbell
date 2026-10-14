# Design

## Context

動機は proposal.md の Why を参照。直す 4 件の今の形は次のとおり。

- `HostKind`（`Accounts/Account.swift`）を使っているのは 4 か所ある。
  - `GitHubAPI/APIEndpoints.swift`: API ベース URL を導く
  - `Accounts/Account.swift`: `Account.hostKind` と、`github.com` を先頭にする並べ替え
  - `UI/Account+Display.swift`: `hostLabel`
  - `Diagnostics/DiagnosticsReport.swift`: Host kind の行
  - 分類のテストは `MewbellTests/AccountDiscoveryTests.swift` にある。
- `GitHubAPIClient.perform(_:endpoints:token:)` は `ThreadAction` を受け取り、`markThreadRead` と `markThreadDone` に振り分けるだけの関数である。呼んでいるのは `AccountPoller+ThreadActions.swift` の `perform(_:)` の 1 か所だけで、テストは呼んでいない（テストは `poller.perform` か、`markThreadRead`・`markThreadDone` を直接使う）。
- `Logger(category:)` は `App/Logging.swift` の `Logger` の拡張で、サブシステム名を 1 か所に持つ。使っているのは 13 ファイルで、`GhCLI/`・`GitHubAPI/`・中間の層・`App/` にまたがる。
- `NotificationStore` は、URL を開く関数 `openURL` を init で受け取る（テストは偽物を渡す）。`static func live(...)` だけが `{ NSWorkspace.shared.open($0) }` を作っていて、そのためにファイル全体が `import AppKit` している。
- `project.xcproj` は `Mewbell` フォルダを同期のフォルダとして取り込んでいる。そのため、ディレクトリを足してもプロジェクトの編集は要らない。
- `docs/architecture.md` は、A1 の層の一覧に `Diagnostics/` を載せていない。`DiagnosticsReport` は `Polling/` の型を使い、`UI/` から使われているので、働きは中間の層である。

## Goals / Non-Goals

**Goals:**

- A1 の「既知の逸脱」4 件を解消し、`.swiftlint.yml` の `ui_frameworks_outside_ui` の除外を無くす。
- どの層からも使う小さな道具の置き場所を、原則として 1 つに決める。

**Non-Goals:**

- 層の向きを lint やコンパイラで守ること。A1 の採らなかった案（SwiftPM のモジュール分け）は変えない。`Shared/` が上の層を使わないことも lint では守らず、A1 の文とレビューで守る。
- 「既知の逸脱」のうち A1 以外（`ThreadReason`・`ThreadEventText` の置き場所、A4、A10、A11）を直すこと。それぞれ別の change で直す。
- テストのファイルの分け方を、型の新しい置き場所に合わせて組み替えること。

## Decisions

### D1. `HostKind` を丸ごと `GitHubAPI/APIEndpoints.swift` へ移す（A1）

`HostKind` の enum を、`init(host:)` と `displayName` ごと `APIEndpoints.swift` の先頭に移す。ホスト種別は「どの API ベースへ送るか」の分類で、`APIEndpoints.init?(host:)` がその規則の本体である。`Account.hostKind` は `Accounts/` に残す。`Accounts/` は下の層の型を使ってよいので、そのままでよい。

採らなかった案:

- `HostKind` を独立したファイル（`GitHubAPI/HostKind.swift`）にする: 規則を使うのは `APIEndpoints` で、分類と URL の導出が同じファイルにあれば、ホストの種類を足すときに両方を一度に見られる。
- `displayName` を表示の側（`UI/` か `Accounts/` の extension）に残す: 使うのは `UI/` と `Diagnostics/` で、その共通の依存先は `Accounts/` になる。enum と表示名が 2 つのファイルに分かれ、種類を足したときに表示名の書き漏れを `switch` で気づけても、置き場所が増えるだけになる。表示名は 3 つの固定の文字列で、下の層に置いても表示の都合が下の層を変える心配はほぼない。
- `APIEndpoints` の中でホストの分類を書き直し、`HostKind` は `Accounts/` に残す: 同じ規則（`github.com`、`*.ghe.com`、それ以外）が 2 か所に分かれる。

### D2. `GitHubAPIClient.perform(_:)` を消し、`AccountPoller` が呼び分ける（A1）

`GitHubAPIClient.perform(_:endpoints:token:)` を消す。`AccountPoller+ThreadActions.swift` の `perform(_:)` では、`ThreadAction` の `switch` で `client.markThreadRead(...)` と `client.markThreadDone(...)` を呼び分ける。`ThreadAction` は `Polling/` に残る。`GitHubAPIClient` の公開メソッドは、`markAllRead` と同じくエンドポイントの単位にそろう。

actor の境界は変えない。呼び分けは `AccountPoller` の actor の上で動き、`GitHubAPIClient` は今までどおり `nonisolated` の値型として、呼び出し元の actor の上で動く（A2）。

採らなかった案:

- `ThreadAction` を `GitHubAPI/` へ下ろす: `ThreadAction` は一覧の操作を表す型で、`NotificationStore`・`AccountPoller`・`ThreadActionKind` が使う。下ろすと、操作の種類を足すたびに下の層を触ることになる。client の側の振り分けは 1 か所の `switch` で、ほかに使い道は無い。

### D3. どの層からも使ってよい最下段 `Shared/` を足し、`Logging.swift` を移す（A1・A11）

`Mewbell/Shared/` を作り、`App/Logging.swift` を `Shared/Logging.swift` に移す。中身は変えない。A1 には次のことを書き足す。

- `Shared/` は下の層よりさらに下の段で、どの層からも使ってよい。
- `Shared/` はほかのどのディレクトリの型も使わない。SwiftUI・AppKit も import しない（`ui_frameworks_outside_ui` が守る）。
- 置いてよいのは、アプリの領域の型（アカウント・スレッド・ホストなど）を知らず、下の層を含む 2 つ以上の層が使う、小さな道具だけにする。領域の型を知るもの、または 1 つの層だけが使うものは、今までどおり使う層のうち最も下の層に置く。

A11 の根拠に書いた `Mewbell/App/Logging.swift` を `Mewbell/Shared/Logging.swift` に直す（`scripts/check-architecture.sh` の「コードの名前」の検査が止めるので、漏れれば lint で分かる）。この判断は「どの層からも使う道具をどこに置くか」で、ほかの機能を足すときにも同じ問いが出る。そのため、design.md だけでなく A1 に書く（`openspec/config.yaml` の design の規則）。

採らなかった案:

- `GhCLI/` に置く: いちばん下の層なので依存の向きは合う。しかし、ログの拡張が gh の部品に住むことになり、次に似た道具が出たときも「`GhCLI/` に置く」と読めてしまう。
- `App/Logging.swift` を A1 の適用外にする: 動かさずに済むが、上の層のファイルを下の層が使う例外を、原則として残すことになる。
- 拡張をやめ、各所で `Logger(subsystem:category:)` と書く: サブシステムの文字列が 13 か所に散り、書き間違えると Console でそのログだけ絞れなくなる。
- 名前を `Support/` か `Common/` にする: A1 の「共通の依存先」という言い方に合う `Shared/` にした。`Common/` は何でも入れたくなる名前で、上の置いてよいものの条件と合わない。

### D4. `NotificationStore.live` は URL を開く関数を引数で受け取る（A1）

`NotificationStore.live(...)` に `openURL: @escaping @MainActor (URL) -> Void` を足し、`AppDelegate` が `{ NSWorkspace.shared.open($0) }` を渡す。`NotificationStore.swift` の `import AppKit` を消し、`.swiftlint.yml` の `ui_frameworks_outside_ui` の `excluded` から `Mewbell/Polling/NotificationStore\.swift` を消す。`openURL` に既定値は持たせない（init と同じく、テストで本物のブラウザを開かないため）。

引数が 6 個になり、swiftlint の `function_parameter_count`（5 個まで。init は対象外）にかかる。`.live` は init の引数を中継するだけの組み立て関数なので、`.live` にだけ `// swiftlint:disable:next function_parameter_count` を付ける。引数を減らすためだけに型を足す（コールバック 2 つを struct にまとめる）、`.live` を `convenience init` にしてほかの部品の `.live` とそろわなくする、プロジェクト全体の上限を上げる、はどれも採らない。

actor の境界とスレッド: `openURL` は今までどおり `@MainActor` の関数で、`NotificationStore`（`@MainActor`）が `ThreadWebURL` の検査を通した後にだけ呼ぶ。開く経路を `NotificationStore` の `openURL` の 1 つにすること（A6）は変えない。

採らなかった案:

- `.live` を `App/` の extension（`NotificationStore+Live.swift`）に移す: AppKit は消えるが、A1 の「長いものは `.live(...)` にまとめて型の隣に置き、`AppDelegate` から呼ぶ」の形から外れる。ほかの部品の `.live` と置き場所がそろわなくなる。
- `NotificationStore.swift` で `NSWorkspace` の代わりに Foundation だけで開く: macOS で URL を既定のブラウザで開く公開の手段は AppKit（`NSWorkspace`）か SwiftUI（`openURL`）で、どちらも上の層の framework になる。

### D5. A1 の中間の層に `Diagnostics/` を足す（A1）

A1 の中間の層の一覧に `Diagnostics/` を足す。働き（`Polling/` の型を使い、`UI/` から使われる）は中間の層で、コードは変えない。D3 と同じく A1 を改める作業の中で、スキル `update-architecture-doc` の手順で直す。

### D6. 文書の写しを直す（A1）

`docs/architecture.md` の「既知の逸脱」から A1 の 4 行を消す。消した後に表に行が残るので、表と見出しは消さない。CLAUDE.md のリポジトリ構成の図（「目標」の図）は、`Accounts/` の説明から `HostKind` を外し、`Shared/` の行を足す。消す名前（`GitHubAPIClient.perform`、`App/Logging.swift`）がほかの文書にバッククォートで書かれていないかは、`git grep` で確かめる。`openspec/changes/archive/` の記録は当時のものなので直さない。

## Risks / Trade-offs

- [`Shared/` が、何でも置く場所になる] → 置いてよいものの条件（領域の型を知らない、下の層を含む 2 つ以上の層が使う、小さな道具）を A1 に書き、レビューの判断の根拠にする。
- [`HostKind.displayName` という表示用の文字列が下の層に入る] → 文字列は 3 つの固定値で、トークンや API の振る舞いには関わらない。表示を変えたくなったら、そのときに表示の側へ分ける。
- [`project.xcproj` が新しいディレクトリを取り込まない] → フォルダの同期で取り込む前提だが、`Shared/` を足した後に `xcodebuild -list` と Debug のビルドで確かめる。取り込まれなければ `project.xcproj` を直す。
- [`perform` を消すと、既読と Done で送る先を取り違える] → 呼び分けは `switch` の 2 行で、`MarkReadPollingTests`（既読と Done で送ったメソッドを確かめる）と `DonePollingTests` がそのまま通ることで確かめる。

## セキュリティ

トークンの流れは変えない。

- 取得: `CredentialStore` が `gh auth token --hostname <host> --user <user>` で取得する。
- 保持: actor のメモリにだけ持つ。
- 送信: `AccountPoller` が取得や操作のたびに `GitHubAPIClient` に引数で渡し、`send` が `Authorization` を付ける。
- 破棄: アカウントの削除・無効化・終了時に、今までどおり捨てる。

D2 で変わるのは、`AccountPoller` が呼ぶ `GitHubAPIClient` の公開メソッドの選び方だけで、`send` を通ることは変わらない。

`.claude/rules/security.md` の項目への対応:

- トークンの扱い: 触れない。`AccessToken` 型と伏せ字は変えない。`Logger(category:)` の置き場所を変えるだけで、ログの可変値が `.private` であることは変えない。
- gh サブプロセス: 触れない。
- ネットワーク: `APIEndpoints` の API ベース URL の規則（D1 は `HostKind` の置き場所だけを変える）、オリジン検査、リダイレクトの拒否、キャッシュの扱いは変えない。既存のテスト（`APIEndpoints` のテスト、リダイレクトとオリジンのテスト）が、変えずに通ることで確かめる。
- URL を開く処理: D4 は開く関数を作る場所を `AppDelegate` に移すだけで、`ThreadWebURL` の検査を通した URL だけを開くことは変えない。`NotificationStoreActionTests` が、変えずに通ることで確かめる。
- アプリとビルドの設定・依存: 触れない（新しい依存は無い）。
