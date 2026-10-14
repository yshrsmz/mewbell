# Design

## Context

動機は proposal.md の Why を参照。今の形は次のとおり。

- `ThreadReason`（`UI/ThreadReason.swift`）は Foundation だけを使う。`ThreadEventText` は `UI/ThreadEventText.swift` にあり、`GitHubAPI/` の `ThreadEvent` だけを使う。どちらも状態を持たない enum で、A4 のとおり View の外で文言を決める。
- 使っているのは `UI/ThreadRow.swift`（一覧の行の補足）と `Notifications/ThreadNotificationContent.swift`（macOS の通知の本文）の 2 か所。
- `UI/ThreadEventText.swift` は、同じファイルに `ThreadIcon` を持ち、そのために `import SwiftUI` している。`ThreadIcon` は `Color` を持ち、使うのは `UI/ThreadRow.swift` だけ。
- テストは `MewbellTests/ThreadPresentationTests.swift`（`ThreadReasonTests`・`ThreadEventTextTests`・`ThreadIcon` のテスト）と `MewbellTests/IconColumnTests.swift` にある。
- `.swiftlint.yml` の `ui_frameworks_outside_ui` は、`UI/` と `App/` の外で SwiftUI を import すると止める。

## Goals / Non-Goals

**Goals:**

- A1 の「既知の逸脱」の最後の 1 件を解消する。

**Non-Goals:**

- 文言や関数の形を変えること。
- テストのファイルの分け方を、型の新しい置き場所に合わせて組み替えること（fix-lower-layer-dependencies と同じ）。
- 「既知の逸脱」のうち A4・A10・A11 を直すこと。それぞれ別の change で直す。

## Decisions

### D1. `ThreadReason` と `ThreadEventText` を `Notifications/` へ移す（A1）

`git mv` で `UI/ThreadReason.swift` を `Notifications/ThreadReason.swift` へ移し、`ThreadEventText` を `Notifications/ThreadEventText.swift` へ移す。使う層は上の `UI/` と中間の `Notifications/` で、A1 の「使う層のうち最も下の層」は `Notifications/` になる。`UI/` は中間の層の型を使ってよいので、`ThreadRow` はそのまま使える。`ThreadEventText.swift` は `import SwiftUI` を `import Foundation` に替える。コメントの「一覧と macOS の通知で使う」はそのまま正しい。

採らなかった案:

- `GitHubAPI/` に置く（`ThreadEvent`・`NotificationThread` の隣）: 使う層ではない層に、表示用の文字列が入る。fix-lower-layer-dependencies D1 で `HostKind.displayName` を `GitHubAPI/` に置かなかったのと同じ理由で、A1 に合わない。
- `Polling/` に置く: 一覧のデータを持つ層だが、この 2 つの型を使っていない。使わない層に置くと A1 の置き場所の軸から外れる。
- `Shared/` に置く: A1 は `Shared/` に置いてよいものを「アプリの領域の型を知らない道具」に限っていて、`ThreadEventText` は `ThreadEvent` を知っている。
- `ThreadNotificationContent` が自分で文言を決め、`UI/` と別々に持つ: 一覧と通知で同じ `reason` の表示名が食い違いうる。

### D2. `ThreadIcon` は `UI/ThreadIcon.swift` に分けて `UI/` に残す（A1）

`ThreadIcon` は SwiftUI の `Color` を持ち、使うのは `UI/` だけなので、A1 のとおり `UI/` に残す。`ThreadEventText` を移すと同じファイルに置けなくなるので、型の名前のファイル `UI/ThreadIcon.swift` に分ける。中身は変えない。

### D3. 文書を直す（A1）

スキル `update-architecture-doc` の手順で、`docs/architecture.md` を次のように直す。

- 「既知の逸脱」から A1 の行を消す。ほかの行が残るので、表と見出しは消さない。
- A1 の置き場所の例に、複数の層が使う例として「一覧と通知の両方が使う `ThreadReason`・`ThreadEventText` は `Notifications/`」を足す。根拠に `fix-shared-thread-text-placement D1` を足す。
- A4 の文言の型の一覧（`ThreadReason`、`ThreadEventText`、`ThreadIcon` など）は名前だけで置き場所を書いていないので、変えない。

消す・改める名前は無い（型の名前は変えない）。移すファイルのパス（`UI/ThreadReason.swift`、`UI/ThreadEventText.swift`）がほかの文書に書かれていないことは `git grep` で確かめた（`openspec/changes/archive/` の記録は当時のものなので直さない）。

## Risks / Trade-offs

- [`ThreadEventText` が使う `ThreadEvent.Kind` が増えたとき、`Notifications/` のファイルを直すことになる] → 今も `UI/` のファイルを直していて、手間は変わらない。表示名の抜けは `ThreadEventTextTests` の全種類の検査で止まる。
- [`project.xcproj` が移したファイルを取り込まない] → フォルダの同期で取り込む前提だが、移した後に Debug のビルドで確かめる。

## セキュリティ

トークンの流れは変えない（取得は `CredentialStore` が `gh auth token`、保持は actor のメモリ、送信は `GitHubAPIClient.send`、破棄はアカウントの削除・無効化・終了時）。この change は表示用の文字列を作る 2 つの型の置き場所を変えるだけで、`.claude/rules/security.md` のどの項目にも触れない。

- トークンの扱い: 触れない。移す型はトークンを受け取らない。
- gh サブプロセス: 触れない。
- ネットワーク: 触れない。
- URL を開く処理: 触れない。通知の `userInfo` の URL は今までどおり `ThreadWebURL` で作る。通知の本文に入れるのは、今までどおり決まった表示名と検証済みのログイン名だけ。
- アプリとビルドの設定・依存: 触れない。
