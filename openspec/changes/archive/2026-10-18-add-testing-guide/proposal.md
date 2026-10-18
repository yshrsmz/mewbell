# Proposal

## Why

テストの方針は今、`docs/architecture.md` の A12 の 1 段落に収めている。要点は次の 3 つ。

- 削ったら見逃す不具合で残すかを決める
- 型の保証はテストしない
- 偽物の中で同期的に待たない

2026-10-12 の remove-redundant-tests の後もテストを足し続けた結果、もう一度精査すると、同じ種類の余分なテストが約 1,100 行見つかった（全体の約 11%）。主なものは次のとおり。

- 同じ関数を入口ごとに確かめ直している
- 下の層の確認を上の層で繰り返している
- 実装の式・表・文言を期待値に写している
- 本物と違う振る舞いをする fake に頼っている

A12 は「何を残すか」の基準しか言っておらず、「どこで確かめるか」「期待値をどう書くか」「fake をどう作るか」を決めていない。書く時点でこれらを判断できる文書が要る。この文書は、続く 2 つのテストの整理の change で、削る・残すの根拠にもなる。

## What Changes

- テストの方針の文書 `docs/testing.md` を新設する。項目ごとに ID（`T1` など）を振り、レビューの指摘や design.md から ID で引けるようにする。扱う項目は次のとおり。
  - 残すかどうかの基準
  - 確かめる場所（層ごとの正本）
  - 期待値の書き方
  - 引数の絞り方とセキュリティの検証の例外
  - fake の作り方
  - 実時間に頼らないこと
  - 単体テストで確かめないもの
  - テストを足す・削るときの手順
- `docs/architecture.md` の A12 を、テストの方針は `docs/testing.md` に置くという原則に改める。冒頭の文書の分担の段落と「指摘の仕分けとの関係」からも `docs/testing.md` を引く。
- スキル `update-architecture-doc` の「どの約束をどこに書くか」の表で、テストの方針の置き場所を `docs/testing.md` にする。
- CLAUDE.md と `.swiftlint.yml` の、A12 を引いている箇所の参照を見直す。`.claude/rules/review-process.md` の指摘の仕分けからも `docs/testing.md` を引く。

アプリの振る舞いとテストのコードは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。文書の追加と参照の付け替えだけで、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。続く 2 つのテストの整理の change（GitHubAPI・gh・アカウント・App の側と、Polling・store・通知・UI の側）の前に入れる。
- 変更するもの: `docs/testing.md`（新設）、`docs/architecture.md`、`.claude/skills/update-architecture-doc/SKILL.md`、`.claude/rules/review-process.md`、`CLAUDE.md`、`.swiftlint.yml` の `message`、`scripts/check-architecture.sh`（ID の参照と重複を探す先に `docs/testing.md` を足す）。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: 触れない。ただし `docs/testing.md` には、security.md の「ユニットテストで確かめる」性質ごとに最後の 1 本を残すことと、その検証の引数は削らないことを書く。
- トークンの永続化に関わる変更は無い。
