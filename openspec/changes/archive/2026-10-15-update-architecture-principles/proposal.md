# Proposal

## Why

add-architecture-principles で書いた `docs/architecture.md` の原則は、その PR のレビュー自身が同じ文書を根拠にしていて、中身が意図と合っているかを人が確かめていなかった。原則 A1〜A16 を人の目で読み合わせたところ、意図と食い違う点が 3 つ見つかった。

- A1 は、中間の層（`Accounts/`・`Polling/`・`Notifications/`・`Settings/`・`Diagnostics/`）どうしが互いの型を使うことを許していて、ディレクトリの間で依存が輪になることも禁じていない。今のコードには、Accounts↔Polling と Accounts↔Settings の 2 つの輪がある。輪になった 2 つのディレクトリは、片方だけを読んでもテストしても閉じない。
- A4 は「View に ViewModel を置かない」原則だが、それと関係の無い「書体の大きさはテキストスタイルで指定する」という約束も同じ原則に入っている。
- A6 は、関所のファイルが行数の上限に当たったときに `swiftlint:disable file_length` で上限を緩めることを認めている。上限を緩めると、関所のファイルが際限なく大きくなれる。関所は、上限を緩めて守るのではなく、小さい型に切り出して守りたい。

## What Changes

- A1 に「同じ高さの層どうし（中間の層どうし、下の層どうし）は互いの型を使ってよいが、ディレクトリの間で依存を輪にしない」を足す。同じ高さの 2 つの層の両方が使う型は、もう一方に依存している側の層ではなく、依存されている側の層に置く。中間の層に順序を決める案は、引き続き採らない。
- 同じ change で、今ある 2 つの輪を解く。
  - Accounts↔Polling: `TokenProviding` を `Polling/` から `Accounts/` に移す。`Accounts/` の `AccountDiscovery` がこれに準拠していて、`Polling/` はもともと `Accounts/` の `Account`・`AccountID`・`DiscoveryState` を使っているため。
  - Accounts↔Settings: `AccountStore` が `AppSettings` を持つのをやめ、読み直しの設定（`DiscoveryOptions`）を返すクロージャを受け取る。`AppDelegate` が `AppSettings` から作った値を渡すクロージャをつなぐ。
- A4 から書体の約束を抜き出し、新しい原則 A17 にする。lint の `fixed_font_size` の `message` も A17 に引き直す。
- A6 の「行数の上限はそのファイルだけ緩める」を改める。新しい形は「関所（`Authorization` を付けて送る部分）を小さな型に切り出して、その型だけのファイルに置き、上限は緩めない」。今の `GitHubAPIClient.swift`（`swiftlint:disable file_length`）は「既知の逸脱」に書く。切り出す作業は、別の change（`fix-api-client-gateway`）で行う。

アプリの振る舞いは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。設計方針の文書と、型の置き場所・初期化の引数を変えるだけで、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。add-architecture-principles で書いた原則を意図に合わせ、M1（gh 連携）と M4（設定）で入れた型の置き場所を、新しい A1 に合わせる。
- 変更するもの: `docs/architecture.md`、`.swiftlint.yml`（`fixed_font_size` の `message`）、`Mewbell/Polling/TokenProviding.swift`（`Mewbell/Accounts/` へ移す）、`Mewbell/Accounts/AccountStore.swift`、`Mewbell/Settings/AppSettings.swift`、`Mewbell/App/AppDelegate.swift`、`AccountStore` を作るテスト（`MewbellTests/AccountStoreTests.swift`、`MewbellTests/GhDiagnosticsTests.swift`）。プロジェクトはフォルダ単位でファイルを取り込んでいるので、`project.xcproj` は変えない。
- トークン: `TokenProviding`（ポーラーがトークンを受け取る口）を移すが、置き場所が変わるだけで中身は変えない。トークンは今までどおり `CredentialStore` の中のメモリにだけ持ち、永続化しない。
- gh サブプロセス: 読み直しに渡す gh の上書き（`GhOverrides`）の受け取り方は変わる。中身と、gh を実行する処理は変えない。
- ネットワーク、URL を開く処理: 触れない。
