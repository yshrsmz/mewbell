# Tasks

## 1. 送る間隔を空ける

- [ ] 1.1 `AccountPoller.init` に間隔の待ち `actionSpacing: Sleep`（既定は `Task.sleep`）を足し、間隔の値（1 秒）を `AccountPoller` の `static let` に置く（design.md D1）。`PollerFixture`（`MewbellTests/Support/PollingFakes.swift`）は、すぐ返して長さを記録するだけの待ちを既定で渡す。`AccountPoller` を直接作っているテスト（`NotificationStoreActionTests`、`NotificationStoreNewThreadsTests`、`NotificationStoreRepositoriesTests` など。`git grep -n "AccountPoller(" MewbellTests` で洗い出す）のうち、複数のスレッドをまとめて操作するものにも、実時間を待たない待ちを渡す。既存のテストがそのまま通ることを確かめる。
- [ ] 1.2 `perform(_:)` で、2 件目以降の送信の前に `actionSpacing` で 1 秒待ち、その後にトークンの読み直しと止まっていないかの確かめ直しを通す。待ちが投げたら残りを送らない。送らないスレッドの前では待たない（design.md D2・D3）。`GroupActionPollingTests` に、3 件のグループで待ちが 2 回・それぞれ 1 秒で、1 件目の前には待たないこと、1 件だけのグループと行の操作では待たないこと、`500` の後も待つこと、レート制限で打ち切った後は待たないことのテストを足す。待ちの途中で `stop()` とトークンの破棄をしたとき、待ちを進めても残りが送られないこと（別の `ManualSleeper` を渡して止める）のテストを足す。すべて Done（`NotificationStore.markAllDone(in:)`）で 2 件目の前に 1 秒待つテストを、すべて Done のテストがあるスイートに足す。`xcodebuild ... test -only-testing:MewbellTests/GroupActionPollingTests` などで通し、結果のスイート数を確かめる。
- [ ] 1.3 `perform(_:)` のドキュメントコメントと、`// 二次レート制限を避けるため、並行させずに 1 件ずつ送る` のコメントを、間隔を空けることに合わせて直す。

## 2. 確認

- [ ] 2.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [ ] 2.2 `bash scripts/run.sh` で起動し、手元で確かめる。スレッドが 3 件以上あるリポジトリのグループを Done にすると、すぐに一覧から消え、数秒のうちに Web の受信箱からも 1 件ずつ消えること。Console.app でポーラーのログに失敗が出ないこと。行の Done は押してすぐに Web の受信箱から消えること。
- [ ] 2.3 （任意・取り消せない）通知が 180 件より多いアカウントがあれば、すべて Done を押し、途中でレート制限の知らせが出ずに、数分のうちに Web の受信箱が空になることを確かめる。

## 3. レビュー

- [ ] 3.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 3.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 3.3 ロジックの変更を含む修正が多ければ、3.2 を新しいサブエージェントでもう一度実行する。
