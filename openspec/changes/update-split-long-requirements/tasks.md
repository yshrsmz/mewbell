# Tasks

## 1. 分け方の確認

- [ ] 1.1 作業用の確認スクリプト（design D4）で、分ける前と分けた後の main spec を比べ、規範の文とシナリオが 1 つも落ちていないこと、すべての要件の本文が 500 文字以内で SHALL か MUST を含み、シナリオを 1 つ以上持つことを確かめる
- [ ] 1.2 確認スクリプトが一覧にした、形を変えた文・補った句・置き換えた指示語・足したシナリオ・行を足したシナリオを 1 件ずつ目で確かめ、規範の意味が変わっていないことを確かめる
- [ ] 1.3 分けた要件の名前への参照（`capability「要件名」` と `「要件名」`）を `openspec/specs/`・`docs/`・`Mewbell/`・`MewbellTests/`・`scripts/`・`.github/` で grep し、参照している中身が別の要件へ移ったものだけを直す（design D2）。`openspec/specs/` の中の参照は delta spec で直してある（polling「スレッドの Done」、ui「スレッドの行のイベント」「見出しの押せる範囲の高さ」など）ので、delta の外の参照（`MewbellTests/ThreadIconTests.swift` と `MewbellTests/ActionsThreadWebURLTests.swift` のコメント）を直す。`docs/architecture.md` を直すときはスキル `update-architecture-doc` に従い、`bash scripts/check-architecture.sh` を回す

## 2. 再発の防止

- [ ] 2.1 `openspec/config.yaml` の `rules.specs` に、Requirement の本文を 500 文字以内にし、超えるときは振る舞いごとに Requirement を分けることを足す（design D5）

## 3. アーカイブと並べ直し

- [ ] 3.1 `pnpm exec openspec validate update-split-long-requirements --strict` が通ることを確かめる
- [ ] 3.2 アーカイブした後、main spec を目標の spec に置き換える（design D3）。`ADDED` で末尾に足された要件を分けた元の要件のすぐ後ろへ並べ直し、元の要件に重ねて残したシナリオを消す。確認スクリプトで、アーカイブの結果と目標の spec の差がこの 2 つだけであることを確かめ、アーカイブとは別のコミットにする
- [ ] 3.3 PR #56 の worktree の 1.14.1 の実行ファイルで、`openspec validate --all --strict` がこのブランチで通ることを確かめる。1.13.2 の `pnpm exec openspec validate --all --strict` も通ることを確かめる

## 4. 仕上げ

- [ ] 4.1 `bash scripts/lint.sh` が通ることを確かめる。コードは変えないので、ビルド・テスト・手元での起動は、Swift のファイルに差分が無いこと（`git diff --stat main -- Mewbell MewbellTests Mewbell.xcodeproj` が空であること）で代える。コードのコメントの参照を 1.3 で直したときは、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と、警告をエラー扱いにした Debug と Release のビルドを回す

## 5. レビュー（.claude/rules/review-process.md）

- [ ] 5.1 別コンテキストの opus サブエージェント（`general-purpose`）で `simplify` を実行し、入った変更を確かめる
- [ ] 5.2 別の opus サブエージェントで `code-review` を effort `medium` で実行し、指摘ごとに直す・直さない（理由）を決めて対応する。規範の文の変更を含む修正が多いときは、もう一度 `code-review` を新しいサブエージェントで回す
- [ ] 5.3 PR 本文の Test plan に、simplify と code-review をサブエージェントで実行したこと、指摘の件数と対応を書く
- [ ] 5.4 この PR を merge した後、PR #56 を rebase させ（Renovate の rebase のチェックボックス）、CI の `lint` が通ってから merge する
