# Tasks

## 1. テストの方針の文書

- [ ] 1.1 `docs/testing.md` を新設し、design.md の D2・D3 の T1〜T8 を書く。security.md の性質は参照するだけにして、本文を写さない。書いた型名・ファイル名が実在することを `git grep -w` で確かめる。

## 2. 参照の付け替え

- [ ] 2.1 スキル `update-architecture-doc` の手順に従い、`docs/architecture.md` の A12 を design.md の D1 の形に改め、冒頭と「指摘の仕分けとの関係」から `docs/testing.md` を引く。同じスキルの表で、テストの方針の置き場所を `docs/testing.md` にする。`bash scripts/check-architecture.sh` が通ることを確かめる。
- [ ] 2.2 CLAUDE.md、`.claude/rules/review-process.md`、`.swiftlint.yml` の `message` を design.md の D4 のとおりに直す。`grep -rnw A12` で残った参照が A12 の新しい形と食い違わないことを確かめる。

## 3. 確認

- [ ] 3.1 `bash scripts/lint.sh`、`bash scripts/tests/check-architecture-test.sh`、`pnpm exec openspec validate --all --strict` が通ることを確かめる。
- [ ] 3.2 アプリのコードは変えていないので、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug・Release のビルドが通ることだけを確かめる（手元での起動の確認は、振る舞いが変わらないので省く）。

## 4. レビュー

- [ ] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込む。
- [ ] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
