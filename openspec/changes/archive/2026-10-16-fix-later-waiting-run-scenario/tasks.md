# Tasks

## 1. テスト

- [x] 1.1 `MewbellTests/ThreadDetailsRequestTests+Actions.swift` の `takesTheApprovableRunClosestToTheNotification` の後半（`later`）を、delta spec のシナリオ「後から待ち始めた run は選ばない」の形に改める: 承認を待っている run を `102`（`updated_at` 2026-10-08T11:59:00Z、`current_user_can_approve: false`）と `103`（12:20:00Z、`true`）の 2 件にし、結果が `.unavailable` であることに加えて、送ったリクエストが承認を待っている run の一覧と 2 件の `pending_deployments` の 3 回だけで、`created=` のリクエストが無いことを確かめる。doc コメントも改めた形に合わせる。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/<スイートの型名>` で通し、結果のスイート数を確かめる。アプリのコードは変えない。（code-review の後に、後半を `rejectsAnApprovableRunThatStartedWaitingLater` に分けた）

## 2. 確認

- [x] 2.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [x] 2.2 `bash scripts/run.sh` で起動し、ポーリングが始まり、ログにエラーが無いことを確かめる（アプリのコードは変えないので、起動できることの確認だけ）。（ポーリングが始まり、エラーのログが無いことを確かめた）

## 3. レビュー

- [x] 3.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。（変更なし。入れなかった候補 3 件: リクエストの比較を `pending_deployments` だけにする、テストを 2 つに分ける、doc コメントを短くする。意図を表せる・change の範囲を超えるなどの理由で見送り）
- [x] 3.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。（不具合の指摘は無し。軽微な 3 件のうち 1 件を直した: テスト名が中身に合わないので後半を別のテストに分けた。2 件は直さない。理由は PR 本文）
- [x] 3.3 ロジックの変更を含む修正が多ければ、3.2 を新しいサブエージェントでもう一度実行する。（テストを分けただけでロジックの変更は無いので、もう一度は回さない）

## Workflow follow-up

- `/opsx:archive fix-later-waiting-run-scenario` で delta spec を `openspec/specs/github-api/spec.md` に反映し、PR を ready にする。
- archive の後に、`handover.local.md` の該当の ToDo を消す。
