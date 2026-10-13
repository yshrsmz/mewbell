# Tasks

## 1. 設計方針の文書

- [ ] 1.1 `docs/architecture.md` に、文書の位置づけ、方針が割れたときの優先順位、指摘の仕分けとの関係（design D3 の表）、方針を足す・改める手順（D5）を書く。確認: D2 の構成の見出しがそろっていて、優先順位の 4 段と仕分けの 4 行が design と一致する
- [ ] 1.2 12 のテーマを原則 `A1` 〜 `A12` に起こす。各原則に、原則・理由・採らなかった案・適用外・根拠の change と D 番号を書く。依存の向きの原則には置き場所の軸を、View の組み立ての原則には store を受け取る範囲を、関所の原則には可視性を含める（D7）。確認: 各原則の根拠に挙げた change の design.md を開き、原則と食い違わないことを確かめる。型名がコードに実在することを `grep` で確かめる（`ThreadDetailsCache` など、文書とコードで名前が違うものに注意）
- [ ] 1.3 「既知の逸脱」に、D7 の 3 件を、直す予定の change の名前（仮の名前でよい）とともに書く。確認: 各逸脱の場所（ファイルと型）が今のコードと合う

## 2. 渡し方

- [ ] 2.1 `CLAUDE.md` に、`docs/architecture.md` の場所と読む場面を書く。「実装上の約束」のうち構造の約束（strict concurrency と actor の境界、外部依存）を文書の原則への参照に置き換える（D4）。確認: CLAUDE.md と文書の両方に同じ約束の本文が無い
- [ ] 2.2 `openspec/config.yaml` の `rules.design` に、各 Decision が従う原則の ID を書くこと、原則から外れる判断はその旨と理由を書くこと、change をまたいで効く新しい判断は同じ change で文書に足すことを足す。`rules.tasks` に、文書を変える change は update-architecture-doc スキルでの更新と `bash scripts/check-architecture.sh` の実行をタスクに含めることを足す（D4・D5）。確認: `pnpm exec openspec instructions design --change add-architecture-principles --json` と `instructions tasks` の `rules` に足した規則が出る
- [ ] 2.3 `.claude/rules/review-process.md` の「サブエージェントへの渡し方」に、simplify・code-review・目標の形の検証のサブエージェントに `docs/architecture.md` を読ませることを足す。「指摘の直し方」に、仕分けは文書の「指摘の仕分けとの関係」に照らすことを足す（D3・D4）。確認: 「経緯を渡さない」の規則と食い違う書き方になっていない

## 3. lint

- [ ] 3.1 `.swiftlint.yml` に D6 の 6 つの `custom_rules` を足す。`message` に原則の ID を入れる。確認: `bash scripts/lint.sh` が通る。各規則に引っかかる 1 行を一時的に足すと lint が落ち、外すと通る（`print(`、`Thread.sleep`、`URLSession.shared`、`Polling/` の `import SwiftUI`、`Accounts/` の `"Authorization"`、`UI/` の `.system(size:`）。試した行は消す
- [ ] 3.2 CI と同じ swiftlint の Docker イメージ（`.github/workflows/ci.yml` の `SWIFTLINT_IMAGE`）で、足した規則が動くことを確かめる。Docker が手元で使えなければ、PR の CI の lint の結果で確かめる

## 4. 検査とスキル

- [ ] 4.1 `scripts/check-architecture.sh` に D8 の 5 つの検査を書く。検査するルートを引数で受け取る（既定はリポジトリのルート）。bash と grep / awk だけを使い、macOS の bash 3.2 と BSD の grep / awk でも動かす。確認: 1 章の文書に対して通る
- [ ] 4.2 `scripts/tests/check-architecture-test.sh` を書く。一時ディレクトリに偽のリポジトリ（文書・CLAUDE.md・rules・config・`.swiftlint.yml`・design.md・Swift のファイル）を組み、次のことを確かめる。正しい形で通る。5 つの検査それぞれに、引っかかる 1 か所を入れると落ち、出力に検査の名前とファイルが出る。廃止した原則は 5 項目が無くても通り、archive の design.md からの参照は許され、archive でない文書からの参照は落ちる。確認: `bash scripts/tests/check-architecture-test.sh` が通る。検査の 1 つを一時的に外すと、テストが落ちる
- [ ] 4.3 `scripts/lint.sh` の最後と、`.github/workflows/ci.yml` の lint のジョブに、検査と検査のテストの実行を足す。CI の権限・シークレット・使う Action は変えない。確認: `bash scripts/lint.sh` が通る。PR の CI の lint が通る
- [ ] 4.4 `.claude/skills/update-architecture-doc/SKILL.md` を書く（D9）。description に使う場面を、本文に受け持ちの表と種類ごとの手順を書く。確認: 1 章の文書に、架空の原則を 1 つ足す・改める・廃止する手順をスキルどおりにたどり、検査が漏れを見つけることを試す（試した変更は戻す）
- [ ] 4.5 `docs/architecture.md` の冒頭に、更新は update-architecture-doc スキルで行うことを書く。CLAUDE.md の参照（2.1）にも、文書を変えるときはスキルを使うことを書く

## 5. 確認

- [ ] 5.1 確認: `pnpm exec openspec validate add-architecture-principles --strict` と `bash scripts/lint.sh` が通る。アプリのコードは変えないので、`xcodebuild` のビルドとテスト、手元での起動の確認は要らない（`git diff --stat main` に `Mewbell/`・`MewbellTests/` が無いことを確かめる）

## 6. レビュー

- [ ] 6.1 別コンテキストの opus サブエージェントで `simplify` を実行する（`.claude/rules/review-process.md`）。変更を確かめてから取り込む
- [ ] 6.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く
- [ ] 6.3 文書の中身の修正が多ければ、6.2 を新しいサブエージェントでもう一度実行する
- [ ] 6.4 PR 本文に、原則の中身を人の目で確かめてほしいことを書く（この change の文書を、この change のレビューが根拠にするため）
