# Tasks

## 1. Accounts↔Polling の輪を解く

- [x] 1.1 `Mewbell/Polling/TokenProviding.swift` を、中身を変えずに `Mewbell/Accounts/TokenProviding.swift` に移す（design.md D2）。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell build` が通ることと、`Mewbell/Accounts/` の中で `Polling/` に宣言された型を使っている箇所が無いことを grep で確かめる（コメントの中の名前は除く）。

## 2. Accounts↔Settings の輪を解く

- [x] 2.1 `AppSettings` に、`ghOverrides` と `disabledAccounts` から作る `discoveryOptions: DiscoveryOptions` を足す。`DiscoveryOptions` のドキュメントコメントから `AppSettings` の名前を消し、同じ説明を `discoveryOptions` の側に書く（design.md D3）。`SettingsTests` に、無効にしたアカウントと gh の上書きが `discoveryOptions` に入ることを確かめるテストを 1 本足し、通ることを確かめる。（足さなかった。`AccountStoreSettingsTests.passesTheCurrentSettingsToEachReload` が `settings.discoveryOptions` を通して両方を確かめていて、同じことを確かめ直すだけになるため。A12）
- [x] 2.2 `AccountStore` の `settings: AppSettings?` を `options: () -> DiscoveryOptions`（既定値 `{ DiscoveryOptions() }`）に置き換える。読み直しの開始（待った後）と結果の反映（`applyingSettings(to:)`）で `options()` を使う。`AppDelegate` は `{ settings.discoveryOptions }` を渡す。`AccountStoreTests` と `GhDiagnosticsTests` の `settings: settings` を `options: { settings.discoveryOptions }` に置き換え、確かめる振る舞いを変えずに `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/AccountStoreTests -only-testing:MewbellTests/AccountStoreSettingsTests -only-testing:MewbellTests/AccountStoreDisableOrderTests -only-testing:MewbellTests/AccountStoreOptionsTimingTests -only-testing:MewbellTests/AccountStoreGhDiagnosticsTests -only-testing:MewbellTests/SettingsStorageTests -only-testing:MewbellTests/AppSettingsTests` が通ることを確かめる（結果のスイート数も確かめる）。
- [x] 2.3 `Mewbell/Accounts/` の中で `Settings/` に宣言された型を使っている箇所が無いことを grep で確かめる。中間の層のディレクトリの間で、型の参照が輪になっていないことを確かめる（Context の表と同じ手順で、コメントの中の名前は除く）。

## 3. 設計方針の文書

- [x] 3.1 スキル `update-architecture-doc` の「原則を改める」の手順で A1 を改める（design.md D1・D2・D5）。中間の層どうしの依存を輪にしないことと、両方が使う型は依存されている側の層に置くことを足し、例に `TokenProviding` は `Accounts/` を加える。輪を許す形を採らなかった案に足し、根拠に `update-architecture-principles D1・D2・D3・D5` を足す。`grep -rnw 'A1' CLAUDE.md .claude openspec .swiftlint.yml docs` で引いている箇所が新しい形と食い違わないことを確かめる。
- [x] 3.2 同じ手順で A4 から書体の約束を抜き出し、新しい原則 A17 にする（design.md D4）。`.swiftlint.yml` の `fixed_font_size` の `message` を A17 に引き直す。A4 と A17 の根拠を design.md D4 のとおりに分ける。
- [x] 3.3 同じ手順で A6 を改める（design.md D6）。「行数の上限はそのファイルだけ緩める」を「関所を小さな型に切り出し、その型だけのファイルに置く」に書き換え、前の形と fix-api-client-send-privacy で採らなかった案との違いを採らなかった案に書く。「既知の逸脱」に `A6 | GitHubAPIClient.swift（swiftlint:disable file_length） | fix-api-client-gateway` の行を足す。A10 の「関所の内側は A6 に従い、外さない」が新しい A6 と食い違わないことを確かめる。
- [x] 3.4 `bash scripts/check-architecture.sh` と `bash scripts/tests/check-architecture-test.sh` が通ることを確かめる。

## 4. 確認

- [x] 4.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [ ] 4.2 `bash scripts/run.sh` で起動し、手元で確かめる。アカウントの一覧が出ること。設定でアカウントを無効にすると見出しが無効の表示になり、有効に戻すと取り直すこと。gh の設定ディレクトリの上書きを変えると読み直すこと。

## 5. レビュー

- [ ] 5.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。
- [ ] 5.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。
- [ ] 5.3 ロジックの変更を含む修正が多ければ、5.2 を新しいサブエージェントでもう一度実行する。
