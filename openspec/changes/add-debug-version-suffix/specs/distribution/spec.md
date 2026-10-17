## ADDED Requirements

### Requirement: Debug ビルドの名前とバージョンの表示

Debug 構成でビルドした Mewbell は、ユーザーに見せる・外へ送るバージョン（About パネル、Diagnostics タブの Version の行とコピーするテキスト、API の `User-Agent`）を `X.Y.Z-dev`（例: `0.5.0-dev`）にし、アプリの画面に出すアプリ名（ポップオーバーの見出し、Diagnostics タブの Mewbell の節の見出しとコピーするテキスト）を `Mewbell (dev)` にしなければならない（MUST）。Release 構成のビルドはどちらも付けてはならない（MUST NOT）。どちらの構成でも、Info.plist の `CFBundleDisplayName`、`CFBundleShortVersionString`、`CFBundleVersion` は変えてはならない（MUST NOT）。

#### Scenario: Debug ビルドで確かめる

- **GIVEN** バージョンが `0.5.0` で、Debug 構成でビルドした Mewbell が起動している
- **WHEN** ユーザーがポップオーバー、About パネル、Diagnostics タブを開き、Diagnostics をコピーする
- **THEN** ポップオーバーの見出しと Diagnostics の節の見出しに `Mewbell (dev)` が出る
- **AND** About パネル、Diagnostics の Version の行、コピーしたテキストに `0.5.0-dev` が出る
- **AND** API へのリクエストの `User-Agent` は `Mewbell/0.5.0-dev` になる
- **AND** アプリの Info.plist の `CFBundleDisplayName` は `Mewbell`、`CFBundleShortVersionString` は `0.5.0` のまま

#### Scenario: Release ビルドで確かめる

- **GIVEN** バージョンが `0.5.0` で、Release 構成でビルドした Mewbell が起動している
- **WHEN** ユーザーがポップオーバー、About パネル、Diagnostics タブを開く
- **THEN** 見出しは `Mewbell`、バージョンは `0.5.0` と出て、`(dev)` も `-dev` も付かない
- **AND** API へのリクエストの `User-Agent` は `Mewbell/0.5.0` になる
