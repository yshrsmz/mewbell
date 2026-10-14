# Tasks

## 1. 型を移す

- [ ] 1.1 `ThreadIcon` を `Mewbell/UI/ThreadEventText.swift` から `Mewbell/UI/ThreadIcon.swift` に中身を変えずに分ける（design.md D2）。続けて `git mv` で `Mewbell/UI/ThreadEventText.swift` を `Mewbell/Notifications/ThreadEventText.swift` へ、`Mewbell/UI/ThreadReason.swift` を `Mewbell/Notifications/ThreadReason.swift` へ移し、`ThreadEventText.swift` の `import SwiftUI` を `import Foundation` に替える（design.md D1）。確認: Debug のビルドが通ること、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/ThreadReasonTests -only-testing:MewbellTests/ThreadEventTextTests -only-testing:MewbellTests/ThreadNotificationContentTests` がテストを変えずに通ること（「N tests in 3 suites」になることを確かめる）、`ls Mewbell/UI` に `ThreadReason.swift`・`ThreadEventText.swift` が無いこと、`bash scripts/lint.sh` が通ること（`Notifications/` で SwiftUI を import していないこと）。

## 2. 文書を直す

- [ ] 2.1 スキル `update-architecture-doc` の手順で `docs/architecture.md` を直す（design.md D3）。
  - A1: 置き場所の例に「一覧と通知の両方が使う `ThreadReason`・`ThreadEventText` は `Notifications/`」を足し、根拠に `fix-shared-thread-text-placement D1` を足す。
  - 「既知の逸脱」から A1 の行を消す。
  - 確認: `bash scripts/check-architecture.sh` と `bash scripts/tests/check-architecture-test.sh` が通ること、`git grep -n "UI/ThreadReason\|UI/ThreadEventText" -- ':!openspec/changes/archive'` が何も返さないこと。

## 3. 確認

- [ ] 3.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh`、`bash scripts/tests/check-architecture-test.sh`、`pnpm exec openspec validate --all --strict` を通す。
- [ ] 3.2 `bash scripts/run.sh` で起動し、手元で今までどおり動くことを確かめる。
  - 一覧の行の補足に、イベント（`Closed by alice` など）と `reason` の表示名が出ること。
  - 行のアイコンが今までどおり出ること。
  - 新着の macOS の通知の本文に、イベント・`reason` の表示名・アカウントが出ること（新着が無ければ、起動と取得の成功をログ（`/usr/bin/log show --info --predicate 'subsystem == "com.codingfeline.mewbell"'`）で確かめ、通知は手で確かめる項目として残す）。

## 4. レビュー

- [ ] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する。
