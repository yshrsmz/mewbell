# Proposal

## Why

github-api の「ワークフローの実行の検索の承認できる run」のシナリオ「後から待ち始めた run は選ばない」は、承認を待っている run が通知（12:00）の 20 分後に待ち始めた `103` の 1 件だけ、という前提で、run は「無い」になるとしている。ところが同じ spec の「ワークフローの実行の検索の通知より前に作られた run」により、承認を待っている run をすべて見られて、どれも通知の前後 10 分以内に待ち始めていなければ、`pending_deployments` は取らずに通知より前に作られた run の一覧へ進む。このシナリオの前提では「承認できる run」の手順に入らないので、シナリオは確かめたい振る舞い（承認できても通知から 10 分より離れた run は選ばない）を確かめていない。テスト `takesTheApprovableRunClosestToTheNotification` の後半も同じ形で、結果が「無い」になるのは、通知より前に作られた run の一覧で何も選ばれないからにすぎない。

## What Changes

- シナリオ「後から待ち始めた run は選ばない」の GIVEN を、承認を待っている run が、通知の 1 分前に待ち始めた `102`（`current_user_can_approve: false` の待ちだけ）と、通知の 20 分後に待ち始めた `103`（`current_user_can_approve: true` の待ちがある）の 2 件、に改める。`102` が通知の前後 10 分以内にあるので、「承認できる run」の手順に入る。
- THEN に、通知より前に作られた run の一覧のリクエストを送らないことを足す。
- Requirement の本文と、ほかのシナリオは変えない。コードの振る舞いも変えない（今のコードはすでに改めたシナリオのとおりに動く）。
- テストの後半を、改めたシナリオと同じ形に改める。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

- `github-api`: 「ワークフローの実行の検索の承認できる run」のシナリオ「後から待ち始めた run は選ばない」の前提と結果を、今の手順に合うように改める。要件の本文は変えない。

## Impact

- マイルストーン: M4（設定と操作）以降の保守の change。fix-workflow-run-after-approval で入った手順と、それより前からあるシナリオの食い違いを直す。
- 変更するもの: `openspec/specs/github-api/spec.md`（archive で反映）、`MewbellTests/ThreadDetailsRequestTests+Actions.swift` の `takesTheApprovableRunClosestToTheNotification`。アプリのコードは変えない。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: どれの振る舞いも変えない。テストの入力を改めるだけなので、`.claude/rules/security.md` の項目に新しく当たるものは無い。トークンの扱い（メモリにだけ持ち、永続化しない）も変わらない。
