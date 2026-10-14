# Proposal

## Why

`docs/architecture.md` の A1 は「型や値は、それを使う層のうち最も下の層に置く」と決めている。しかし、スレッドの `reason` とイベントの表示名を決める `ThreadReason`・`ThreadEventText` は上の層の `UI/` にあり、中間の層の `Notifications/ThreadNotificationContent.swift` から使われている。中間の層が上の層の型を使っていて、A1 の「既知の逸脱」に載っている。fix-lower-layer-dependencies で A1 のほかの逸脱は直したので、残るこの 1 件を直して A1 とコードを一致させる。

## What Changes

- `ThreadReason`（`UI/ThreadReason.swift`）と `ThreadEventText` を、使う層（`UI/` と `Notifications/`）のうち最も下の `Notifications/` へ移す。中身は変えない。
- `UI/ThreadEventText.swift` に同居している `ThreadIcon` は SwiftUI の `Color` を使い、使うのも `UI/` だけなので、`UI/ThreadIcon.swift` に分けて `UI/` に残す。
- `docs/architecture.md` の「既知の逸脱」から A1 の行を消し、A1 の置き場所の例に `ThreadReason`・`ThreadEventText` を足す。

アプリの振る舞いは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。型の置き場所を変えるだけで、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。add-architecture-principles で「既知の逸脱」に載せた A1 の最後の 1 件を直す。
- 変更するもの:
  - コード: `Mewbell/UI/ThreadReason.swift`（`Mewbell/Notifications/ThreadReason.swift` へ移す）、`Mewbell/UI/ThreadEventText.swift`（`ThreadEventText` を `Mewbell/Notifications/ThreadEventText.swift` へ移し、`ThreadIcon` を `Mewbell/UI/ThreadIcon.swift` に残す）
  - 文書: `docs/architecture.md`（A1・既知の逸脱）
  - テスト: 型の場所が変わるだけで中身は変えない（`MewbellTests/ThreadPresentationTests.swift`、`MewbellTests/IconColumnTests.swift`）
- プロジェクト: `project.xcproj` はフォルダの同期でソースを取り込んでいるので、編集は要らない想定。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: どれにも触れない。移す 2 つの型は、決まった表示名と検証済みのログイン名から文字列を作るだけで、トークンや URL を扱わない。トークンは今までどおり actor のメモリにだけ持ち、永続化しない。
