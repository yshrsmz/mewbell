# Tasks

## 1. 分け方の確認

- [x] 1.1 `git show 2d64cb0:openspec/specs/<capability>/spec.md` で分ける前の main spec を作業用のディレクトリに取り出し、`python3 -I work/specsplit.py check <分ける前> work/target`（design D4）で、分ける前と分けた後の main spec を比べ、規範の文とシナリオが 1 つも落ちていないこと、すべての要件の本文が 500 文字以内で SHALL か MUST を含み、シナリオを 1 つ以上持つことを確かめる
- [x] 1.2 確認スクリプトが一覧にした、形を変えた文・補った句・置き換えた指示語・足したシナリオを 1 件ずつ目で確かめ（中身を変えたシナリオは一覧に出さず、問題に数える）、規範の意味が変わっていないことを確かめる。450 文字を超えて残る要件（gh-cli「gh のバージョン確認」467、github-api「スレッドの状態の決定」484、github-api「スレッドのイベントの決定の選び方」455、github-api「ワークフローの実行の検索の承認できる run」487、github-api「ワークフローの実行の検索の通知より前に作られた run」475、github-api「ワークフローの実行の検索のレスポンス」469、polling「待ち時間が分からないレート制限の待ち方」471、polling「スレッドのイベントの取得の順」458、settings「Accounts タブ」453、ui「通知のスレッドを開く URL の Commit とそのほか」476）は、後で書き足すと上限を超えやすいことを PR 本文に書く
- [x] 1.3 分けた要件の名前への参照（`capability「要件名」` と `「要件名」`）を `openspec/specs/`・`docs/`・`Mewbell/`・`MewbellTests/`・`scripts/`・`.github/` で grep し、参照している中身が別の要件へ移ったものだけを直す（design D2）。`openspec/specs/` の中の参照は delta spec で直してある（polling「スレッドの Done」、ui「スレッドの行のイベント」「見出しの押せる範囲の高さ」など）ので、delta の外の参照（`MewbellTests/ThreadIconTests.swift` と `MewbellTests/ActionsThreadWebURLTests.swift` のコメント）を直す。`docs/architecture.md` を直すときはスキル `update-architecture-doc` に従い、`bash scripts/check-architecture.sh` を回す
- [x] 1.4 `python3 -I work/specsplit.py refs <分ける前> work/target` をリポジトリのルートで回し、名前が元の名前から始まらない要件へ中身が移った元の要件への参照（work/target と `Mewbell/`・`MewbellTests/`・`docs/`・`scripts/`・`.claude/`）を 1 件ずつ確かめる。移った中身を指すものは移った先の名前を足すか参照を直し、元の要件に残った中身を指すものは理由を付けて `work/refs-reviewed.txt` に入れ、[REF TO REVIEW] が 0 件であることを確かめる（design D2・D4）

## 2. 再発の防止

- [x] 2.1 `openspec/config.yaml` の `rules.specs` に、Requirement の本文を 500 文字以内にし、超えるときは振る舞いごとに Requirement を分けることを足す（design D5）

## 3. アーカイブと並べ直し

- [ ] 3.1 main に追いついた後、`python3 -I work/specsplit.py same <分ける前> openspec/specs` の差が 0 件であることを確かめる（`MODIFIED` は要件を丸ごと置き換えるので、2d64cb0 の後に main specs を変えた PR があると、アーカイブで黙って上書きする。差があれば目標の spec にその変更を入れて delta を作り直す）。`pnpm exec openspec validate update-split-long-requirements --strict` が通ることを確かめる
- [ ] 3.2 アーカイブした後、main spec を目標の spec に置き換える（design D3）。`ADDED` で末尾に足された要件を分けた元の要件のすぐ後ろへ並べ直し、元の要件に重ねて残したシナリオを消す。置き換える前に `python3 -I <archive の work>/specsplit.py verify-archive <分ける前> <archive の work>/target openspec/specs` の差が 0 件であることを確かめ、`work/target/*/spec.md` を `openspec/specs/` へ写す。アーカイブとは別のコミットにし、同じコミットでアーカイブした change の `work/` を消す
- [ ] 3.3 PR #56 の worktree の 1.14.1 の実行ファイルで、`openspec validate --all --strict` がこのブランチで通ることを確かめる。1.13.2 の `pnpm exec openspec validate --all --strict` も通ることを確かめる

## 4. 仕上げ

- [ ] 4.1 `bash scripts/lint.sh` が通ることを確かめる。1.3 でコードとテストのコメントを直したので、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と、警告をエラー扱いにした Debug と Release のビルドを回す。手元での起動は、`git diff main -- Mewbell Mewbell.xcodeproj` がコメントの行だけであること（アプリの振る舞いに差分が無いこと）で代える

## 5. レビュー（.claude/rules/review-process.md）

- [ ] 5.1 別コンテキストの opus サブエージェント（`general-purpose`）で `simplify` を実行し、入った変更を確かめる
- [ ] 5.2 別の opus サブエージェントで `code-review` を effort `medium` で実行し、指摘ごとに直す・直さない（理由）を決めて対応する。規範の文の変更を含む修正が多いときは、もう一度 `code-review` を新しいサブエージェントで回す
- [ ] 5.3 PR 本文の Test plan に、simplify と code-review をサブエージェントで実行したこと、指摘の件数と対応を書く
- [ ] 5.4 この PR を merge した後、PR #56 を rebase させ（Renovate の rebase のチェックボックス）、CI の `lint` が通ってから merge する
