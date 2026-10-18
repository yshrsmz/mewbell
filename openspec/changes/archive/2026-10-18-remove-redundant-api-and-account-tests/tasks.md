# Tasks

各グループでは `docs/testing.md` の T8 の手順に従う。

- 消すテストの `#expect` が、design.md の D2 の「代わりに残るもの」で拾えるか、移し先に移したかを確かめる。
- 移した `#expect` は、実装を一時的に壊して落ちることを確かめてから戻す。
- グループの終わりに `xcodebuild test -only-testing:MewbellTests/<スイートの型名>` で触ったスイートを流し、結果のスイート数が渡した数と合うことを確かめる。

## 1. GitHubAPI: 共有の取得の分岐（security.md のオリジン検査・ID の検証・リダイレクトの拒否を含む）

- [x] 1.1 `ThreadDetailsRequestTests`（本体・`+Release`・`+Actions`）を D2 のとおりに削除・統合・縮小する。`Authorization` の確認 3 か所も削る。次のものは残す。
  - `fetchesTheTag`
  - `takesTheOnlyWaitingRunTheUserCanApprove`
  - `findsNoWaitingRun` の `[true, true]` の行

  固定データ `release()` の `htmlURL` の既定値を攻撃者のホストにする。`treatsAMissingIssueAsUnavailable` に 403 を足す。
- [x] 1.2 `URLQueryValueTests.swift` は残す（simplify の指摘で、エスケープの正本と判断した。design.md の D3）。
- [x] 1.3 `MarkThreadReadTests`（`classifiesTheStatus`、`ThreadIDTests`）を縮小し、`Retry-After: soon` の行を `GitHubAPIClientTests.classifiesStatusCodes` に移す。

## 2. GitHubAPI: モデルと文言

- [x] 2.1 `CheckSuiteTitleTests`、`GitHubAPIModelTests`（`NotificationThreadTests`、`LinkHeaderTests`）、`ThreadEventResolverTests` を D2 のとおりに縮小・削除する。
- [x] 2.2 `APIEndpointsTests.derivesBaseURLs` に `ghe.com` の行を足してから、`AccountTests.classifiesHosts` を消す。

## 3. gh・アカウント・設定・App

- [x] 3.1 `AccountDiscoveryTests.reportsMissingGh` を消す。`GhClientTests.tokenIsNilWhenGhDoesNotGiveOne` の `second-line` の行を消す。`doesNotFallBackFromAnUnusableConfigDirectory` は残す（design.md の D3）。`publishesTheGhOfTheNewConfigDirectory` は残す（design.md の D3）。`doesNotPassGhConfigDirWithoutAnOverride` と `GhCommandTests` には触れない。
- [x] 3.2 `AccountStoreTests` の 2 か所（終了の統合、`reloadsWhenAnAccountIsEnabledAgain` の状態の確認の移動）を行う。
- [x] 3.3 `SingleInstanceLockTests`、`SettingsStorageTests`、`StatusItemMenuTests` を D2 のとおりに削除・統合する。

## 4. シェルのテスト

- [x] 4.1 `scripts/tests/verify-app-test.sh` から署名の後の書き換えのケースを消し、`bash scripts/tests/verify-app-test.sh` が通ることを確かめる。
- [x] 4.2 `scripts/tests/check-architecture-test.sh` の unknown-id を消し、重複の 2 本を 1 本に統合する（廃止した ID の 2 本は残す。design.md の D3）。`bash scripts/tests/check-architecture-test.sh` が通ることを確かめる。統合したケースは、`scripts/check-architecture.sh` の該当の検査を一時的に外して落ちることを確かめる。

## 5. 確認

- [x] 5.1 `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通り、テストの件数が減った分だけ減っていることを確かめる。`bash scripts/lint.sh`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルド、`pnpm exec openspec validate --all --strict` が通ることを確かめる。本体のコードは変えないので、手元での起動の確認は省く。

## 6. レビュー

- [x] 6.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込む。
- [x] 6.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
