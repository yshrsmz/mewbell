## 1. 開く URL の組み立て（ThreadWebURL）

- [x] 1.1 `ThreadWebURL.target` を、`subject.url` を検証してから種類と組み合わせて決める形にし、Discussion の `discussions/<番号>` から `.discussion(番号)` を作る（design D1）。番号は Pull request と Issue だけのままにする。確認: `ThreadPresentationTests` に、Discussion の番号付きの URL（github.com・`*.ghe.com`・GHES）、`subject.url` が無い・別のホスト・別のリポジトリ・番号が数字でない・21 桁のときに `/discussions` になること、Discussion に番号が付かないことのテストを足して通す
- [x] 1.2 デコードで `subject.url` からリリースの ID を求める処理と `ThreadWebURL.releaseTagComponents(_:)` を足し、`NotificationThread` にリリースの ID を（5.4 で `detailsSubject` にまとめた）、`ThreadDetails` に `releaseTag` を足す（design D2・D3）。確認: リリースの ID が種類 Release で検証を通ったときだけ求まること、タグの検証（空・UTF-8 で 256 バイト以上・空白・制御文字・`..`・`.`・空の要素・先頭や末尾の `/` を拒み、`v1.0.0`・`rust-v0.163.0-alpha.10.1`・`cli/v1.2.0` を受け付ける）のテストを足して通す
- [x] 1.3 `ThreadWebURL.make` で、Release のスレッドがタグを持てば `releases/tag/<要素…>` を、持たなければ `releases` を組み立てる（design D3）。確認: タグを持つ・持たない・`/` を含む・`?`・`#`・`%` を含むタグの URL が spec どおりで、どれも `https` でアカウントのホストを指し、`?`・`#` がクエリやフラグメントにならないテストを足して通す。エスケープが想定と違えば `URLComponents` で組み立てる（design の Risks）

## 2. リリースのタグの取得（GitHubAPI・Polling）

- [x] 2.1 `ReleaseSummary` を足し、`GitHubAPIClient.fetchDetails` でリリースの ID があれば `GET repos/<owner>/<name>/releases/<ID>` を 1 回送ってタグを付けた `ThreadDetails` を返す（design D2・D4）。確認: `ThreadDetailsRequestTests` に、送り先の URL（github.com と GHES）とトークン、`200` でタグが付くこと、`html_url` が別のホストでも使わないこと、検証を通らないタグ・`404`・`410`・`422`・二次レート制限でない `403` が「無い」、`401` が認証の失敗、`403`（`X-RateLimit-Remaining: 0`・二次レート制限の本文）と `429` がレート制限、形の崩れたボディ・`tag_name` が無い・リダイレクト・`500` が一時的な失敗になるテストを足して通す
- [x] 2.2 `ThreadDetailsCache.pending` の対象にリリースの ID を持つスレッドを加える（design D2）。確認: `ThreadDetailsCacheTests` に、Release のスレッドが選ばれること、リリースの ID を持たない Release・Discussion・Commit が選ばれないこと、同じ `updated_at` で「無い」だった Release を取り直さないことのテストを足して通す
- [x] 2.3 確認: `ThreadDetailsPollingTests` に、新着の Release のスレッドがタグを付けた状態で初めて知らされること、最初の一覧の Release は知らせた後に取ってタグを付けて知らせ直すことのテストを足して通す。`SystemNotificationTests` か `ThreadDetailsPollingTests` に、タグを付けた新着の Release の通知の `userInfo` の URL が `releases/tag/<タグ>` になることのテストを足して通す

## 3. 手元での確認

- [ ] 3.1 `bash scripts/run.sh` で起動し、ポップオーバーで Discussion のスレッドをクリックすると個別のディスカッションが開くことを確かめる（手元に無ければ、通知の一覧にある Discussion を `gh api` で確かめ、一覧に出るまで待つか確認を見送ったことを PR に書く）
- [ ] 3.2 ポップオーバーで Release のスレッドをクリックすると `releases/tag/<タグ>` の個別のリリースが開き、タグが件名と違うリリースでも正しいページが開くことを確かめる
- [x] 3.3 Console.app などで、リリースの取得でボディやタグ、トークンがログに出ていないことを確かめる

## 4. 仕上げ

- [ ] 4.1 `bash scripts/lint.sh` が通ることを確かめる
- [ ] 4.2 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build` と同じ Release のビルドが通り、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通り、手元で起動して 3 の確認を終えたことを確かめる

## 5. レビュー（.claude/rules/review-process.md）

- [x] 5.1 別コンテキストの opus サブエージェント（`general-purpose`）で `simplify` を実行し、入った変更を確かめる
- [x] 5.2 別の opus サブエージェントで `code-review` を effort `medium` で実行し、指摘ごとに直す・直さない（理由）を決めて対応する。ロジックの変更を含む修正が多いときは、もう一度 `code-review` を新しいサブエージェントで回す
- [x] 5.4 レビューの指摘が集まった `NotificationThread` の `subjectNumber` と `releaseID` を、経緯を渡さないサブエージェントの評価とユーザーの確認を経て `detailsSubject: DetailsSubject?` にまとめる（design D2 の今の形）。確認: `ThreadDetailsSubjectTests` ほか全テスト、lint、警告をエラー扱いにした Debug と Release のビルドが通る
- [ ] 5.5 ロジックの変更を含むので、新しいサブエージェントでもう一度 `code-review`（effort `medium`）を回し、指摘に対応する
- [ ] 5.3 PR 本文の Test plan に、simplify と code-review をサブエージェントで実行したこと、指摘の件数と対応を書く。トークン・ネットワーク・URL を開く処理に触れるので、「セキュリティ上の確認」の節を設ける
