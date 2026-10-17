## ADDED Requirements

### Requirement: Debug ビルドの表示用のアプリ名とバージョン

Mewbell は、ユーザーに見せるアプリ名とバージョン（表示用のアプリ名とバージョン）を、ビルドの構成で次のように決めなければならない（MUST）。Debug 構成では、アプリ名を `Mewbell (dev)`、バージョンを `X.Y.Z` の後ろに `-dev` を付けた形（例: `0.5.0-dev`）にする。Release 構成では、アプリ名を `Mewbell`、バージョンを `X.Y.Z` にし、`(dev)` も `-dev` も付けてはならない（MUST NOT）。どちらの構成でも、Info.plist の `CFBundleDisplayName`、`CFBundleShortVersionString`、`CFBundleVersion` は変えてはならない（MUST NOT。配布物の検査とリリースのバージョンの管理を変えないため）。どこに出すかは、それぞれの画面と通信の要件が定める。

#### Scenario: Debug ビルド

- **GIVEN** バージョンが `0.5.0`
- **WHEN** Debug 構成でビルドする
- **THEN** 表示用のアプリ名は `Mewbell (dev)`、表示用のバージョンは `0.5.0-dev` になる
- **AND** アプリの Info.plist の `CFBundleDisplayName` は `Mewbell`、`CFBundleShortVersionString` と `CFBundleVersion` は `0.5.0` のまま

#### Scenario: Release ビルド

- **GIVEN** バージョンが `0.5.0`
- **WHEN** Release 構成でビルドする
- **THEN** 表示用のアプリ名は `Mewbell`、表示用のバージョンは `0.5.0` になる
