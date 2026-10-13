# Tasks

## 1. 設計方針の文書

- [ ] 1.1 `docs/architecture.md` に、文書の位置づけ、方針が割れたときの優先順位、指摘の仕分けとの関係（design D3 の表）、方針を足す・改める手順（D5）を書く。確認: D2 の構成の見出しがそろっていて、優先順位の 4 段と仕分けの 4 行が design と一致する
- [ ] 1.2 12 のテーマを原則 `A1` 〜 `A12` に起こす。各原則に、原則・理由・採らなかった案・適用外・根拠の change と D 番号を書く。依存の向きの原則には置き場所の軸を、View の組み立ての原則には store を受け取る範囲を、関所の原則には可視性を含める（D7）。確認: 各原則の根拠に挙げた change の design.md を開き、原則と食い違わないことを確かめる。型名がコードに実在することを `grep` で確かめる（`ThreadDetailsCache` など、文書とコードで名前が違うものに注意）
- [ ] 1.3 「既知の逸脱」に、D7 の 3 件を、直す予定の change の名前（仮の名前でよい）とともに書く。確認: 各逸脱の場所（ファイルと型）が今のコードと合う

## 2. 渡し方

- [ ] 2.1 `CLAUDE.md` に、`docs/architecture.md` の場所と読む場面を書く。「実装上の約束」のうち構造の約束（strict concurrency と actor の境界、外部依存）を文書の原則への参照に置き換える（D4）。確認: CLAUDE.md と文書の両方に同じ約束の本文が無い
- [ ] 2.2 `openspec/config.yaml` の `rules.design` に、各 Decision が従う原則の ID を書くこと、原則から外れる判断はその旨と理由を書くこと、change をまたいで効く新しい判断は同じ change で文書に足すことを足す（D4・D5）。確認: `pnpm exec openspec instructions design --change add-architecture-principles --json` の `rules` に足した規則が出る
- [ ] 2.3 `.claude/rules/review-process.md` の「サブエージェントへの渡し方」に、simplify・code-review・目標の形の検証のサブエージェントに `docs/architecture.md` を読ませることを足す。「指摘の直し方」に、仕分けは文書の「指摘の仕分けとの関係」に照らすことを足す（D3・D4）。確認: 「経緯を渡さない」の規則と食い違う書き方になっていない

## 3. lint

- [ ] 3.1 `.swiftlint.yml` に D6 の 6 つの `custom_rules` を足す。`message` に原則の ID を入れる。確認: `bash scripts/lint.sh` が通る。各規則に引っかかる 1 行を一時的に足すと lint が落ち、外すと通る（`print(`、`Thread.sleep`、`URLSession.shared`、`Polling/` の `import SwiftUI`、`Accounts/` の `"Authorization"`、`UI/` の `.system(size:`）。試した行は消す
- [ ] 3.2 CI と同じ swiftlint の Docker イメージ（`.github/workflows/ci.yml` の `SWIFTLINT_IMAGE`）で、足した規則が動くことを確かめる。Docker が手元で使えなければ、PR の CI の lint の結果で確かめる

## 4. 確認

- [ ] 4.1 確認: `pnpm exec openspec validate add-architecture-principles --strict` と `bash scripts/lint.sh` が通る。アプリのコードは変えないので、`xcodebuild` のビルドとテスト、手元での起動の確認は要らない（`git diff --stat main` に `Mewbell/`・`MewbellTests/` が無いことを確かめる）

## 5. レビュー

- [ ] 5.1 別コンテキストの opus サブエージェントで `simplify` を実行する（`.claude/rules/review-process.md`）。変更を確かめてから取り込む
- [ ] 5.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く
- [ ] 5.3 文書の中身の修正が多ければ、5.2 を新しいサブエージェントでもう一度実行する
- [ ] 5.4 PR 本文に、原則の中身を人の目で確かめてほしいことを書く（この change の文書を、この change のレビューが根拠にするため）
