## ADDED Requirements

### Requirement: Debug ビルドのバージョンの表示

Debug 構成でビルドした Mewbell は、ユーザーに見せる・外へ送るバージョン（About パネル、Diagnostics タブの Version の行とコピーするテキスト、API の `User-Agent`）を、`X.Y.Z` の後ろに `-dev` を付けた形（例: `0.5.0-dev`）にしなければならない（MUST）。Release 構成のビルドは `-dev` を付けてはならない（MUST NOT）。どちらの構成でも、Info.plist の `CFBundleShortVersionString` と `CFBundleVersion` は `X.Y.Z` のままでなければならない（MUST。配布物の検査とリリースのバージョンの管理を変えないため）。

#### Scenario: Debug ビルドで確かめる

- **GIVEN** バージョンが `0.5.0` で、Debug 構成でビルドした Mewbell が起動している
- **WHEN** ユーザーが About パネルと Diagnostics タブを開き、Diagnostics をコピーする
- **THEN** About パネル、Diagnostics の Version の行、コピーしたテキストに `0.5.0-dev` が出る
- **AND** API へのリクエストの `User-Agent` は `Mewbell/0.5.0-dev` になる
- **AND** アプリの Info.plist の `CFBundleShortVersionString` は `0.5.0` のまま

#### Scenario: Release ビルドで確かめる

- **GIVEN** バージョンが `0.5.0` で、Release 構成でビルドした Mewbell が起動している
- **WHEN** ユーザーが About パネルと Diagnostics タブを開く
- **THEN** バージョンは `0.5.0` と出て、`-dev` は付かない
- **AND** API へのリクエストの `User-Agent` は `Mewbell/0.5.0` になる
