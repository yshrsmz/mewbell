# Proposal

## Why

M0〜M4 の change を重ねるうちに、MewbellTests は 50 ファイル・約 560 件・約 8,500 行に増えた。精査すると、次のようなテストが多数あった。

- 他のテストと同じ分岐を確かめ直しているもの
- 実装の表や式を写しているもの
- 型やライブラリが保証していることを確かめ直しているもの
- 実装が壊れても落ちない `#expect`

実時間で待つテストや `Thread.sleep` を使うテスト（CLAUDE.md が禁じている）も残っている。こうしたテストは保証を足さずに、実行時間と、実装を変えるたびの修正の手間を増やしている。

## What Changes

- 削ったときに見逃す現実的な不具合が無いテストを削除する。たとえば、他のテストで拾えるもの、fake の自己検証、型で保証されるもの、空の確認。
- 同じ準備・同じ分岐を確かめているテストを 1 本にまとめるか、parameterized にする。
- 同じ分岐を通る入力の羅列を、代表のケースに減らす。実装の表の写しは、関係を確かめる形に書き換える。
- 必ず通る `#expect` を、実際に落ちうる確認に直すか、取り除く。テストの名前と実際に通る分岐が食い違っているものも直す。
- 実時間の待ちを減らす。具体的には `Thread.sleep` を使うテストと、500ms・100ms・50ms 待つテストを統合・縮小する。
- 不要になった fake のコードを消し、重複している helper を Support にまとめる。
- テストからしか呼ばれなくなる `AccountPoller.requestUnconditionalFetch()` を private にする。外から見た振る舞いは変えない。
- `scripts/tests/verify-app-test.sh` で、実装と同じ配列を回しているループを代表 1 件にする。

アプリの振る舞いは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。テストとテスト用のコードの整理だけで、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: M0〜M4 で入れたテストの整理。特定のマイルストーンには属さない保守の change。
- 変更するもの: `MewbellTests/` のテストと Support、`scripts/tests/verify-app-test.sh`。本体では `Mewbell/Polling/AccountPoller.swift` のアクセス修飾子を 1 か所だけ変える。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: 本体の処理には触れない。ただし、これらを確かめるテストを整理するので、`.claude/rules/security.md` の次の性質について、確かめる最後の 1 本は必ず残す。
  - 伏せ字
  - 環境変数の除去
  - オリジン検査
  - リダイレクト拒否
  - ホスト名・ユーザー名の検証
  - 開く URL の検査
- トークンの永続化に関わる変更は無い。
