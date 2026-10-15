# Tasks

## 1. 重ねる処理

- [x] 1.1 `Mewbell/Polling/ThreadListMerge.swift` に `enum ThreadListMerge` と `static func merge(_ fetched: [NotificationThread], into current: [NotificationThread]) -> [NotificationThread]` を置く（design.md D1）。受け取ったスレッドを受け取った順に、その後に `current` のうち ID が重ならないものを `current` の順に並べる。`project.xcproj` にファイルが入ることを `xcodebuild` で確かめる。
- [x] 1.2 `MewbellTests/ThreadListMergeTests.swift` に、同じ ID は受け取ったもので差し替わる（`updated_at` とタイトルが新しくなる）、無い ID は足される、受け取らなかったスレッドは残る、どちらかが空のとき、のテストを置く。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/ThreadListMergeTests` を通し、結果のスイート数を確かめる。

## 2. ポーラー

- [x] 2.1 `Mewbell/Polling/AccountPoller.swift` の `fetch(with:)` で、`ifModifiedSince != nil` の `200` のとき、状態とイベントを取った後、2 回目の `HiddenThreads.revealOrHide` の前に `ThreadListMerge.merge(fetched, into: state.threads)` で重ね、2 回目の `revealOrHide` と `details.listed` の両方に渡す（条件なしのときは今までどおり `fetched`）。`.updated` の `truncated` を「受け取った打ち切り または `state.isTruncated`」にする（D2・D3・D5）。
- [x] 2.2 `lastFullFetch` を `lastUnconditionalFetch` に改め、条件なしの取得の `200` のときだけ更新する。`PollSchedule.unconditionalFetchIsDue` の引数名と、両方の doc コメント、`unconditionalFetchInterval` の doc コメントを、条件付きの `200` は差分であることに合わせて直す（D4）。
- [x] 2.3 ポーラーのテストを足し、直す（`PollerFixture` を使う）。
  - 条件なしの `200` で 3 件、条件付きの `200` で 1 件（うち 1 件は既存の ID で `updated_at` が進んだもの、または新しい ID）を返すと、一覧が重なった件数になり、差し替えたスレッドの `updated_at` が新しくなること。
  - 既読化のリクエストが終わっていない間の条件付きの `200` で、既読にしたスレッドが戻らないこと（受け取ったスレッドに入っているときも）。すべて既読の範囲も同じ。
  - `UnconditionalFetchTests.countsAConditional200AsAFullFetch` を、条件付きの `200` では 5 分の起点が動かない（最初の取得から 5 分で条件なしになる）テストに改める。
  - 条件なしの取得が打ち切られた後の、打ち切られなかった条件付きの `200` で、`isTruncated` が true のままであること。
  - 条件付きの `200` で一覧に残ったスレッドの状態とイベント（`details`）が外れないこと。
  - ほかのテストのうち、条件付きの `200` で一覧が置き換わることを前提にしていたものを、新しい振る舞いに合わせて直す（全テストを回して見つける）。
  - `xcodebuild ... test -only-testing:` で該当のスイートを通し、結果のスイート数を確かめる。
- [x] 2.4 store を通したテストを足す: 条件なしの `200` の後の条件付きの `200` で、受け取らなかったスレッドの macOS の通知が取り下げられないこと（偽の notifier の取り下げの記録で確かめる）。その後の条件なしの `200` で消えたスレッドは取り下げられること。

## 3. 確認

- [ ] 3.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [ ] 3.2 `bash scripts/run.sh` で起動し、手元のアカウントで確かめる: 条件なしの取得の後に新しい通知が届いたとき（条件付きの `200`）、それより古い一覧のスレッドが消えず、新しいスレッドが足されること。ログ（`Polling` のカテゴリ）で、`If-Modified-Since` を付けた取得の後も一覧の件数が減らないことを見る。

## 4. レビュー

- [x] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。（1 件を取り込んだ: 条件付きの 200 で 2 回呼んでいた `ThreadListMerge.merge` を 1 回にし、同じ一覧を 2 回目の `revealOrHide` と `details.listed` に渡す）
- [ ] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する。
