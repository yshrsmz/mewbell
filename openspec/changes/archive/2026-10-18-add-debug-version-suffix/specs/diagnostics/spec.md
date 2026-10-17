## MODIFIED Requirements

### Requirement: Diagnostics のコピー

Diagnostics タブには、表示している内容をプレーンテキストでクリップボードにコピーするボタンがなければならない（SHALL）。コピーするテキストには、Mewbell の表示用のアプリ名とバージョン（distribution「Debug ビルドの表示用のアプリ名とバージョン」）、macOS のバージョン、タブに表示している項目だけを入れなければならない（MUST）。コピーするテキストは、クリップボードに入れる前に、トークンらしい文字列を、gh-cli「トークンと gh の出力を漏らさない」と同じ規則（`gh` に英小文字 1 文字と `_` が続く文字列、`github_pat_` で始まる文字列、40 桁の 16 進数）で伏せ字にしなければならない（MUST）。

#### Scenario: コピーする

- **GIVEN** `github.com/alice` と `acme.ghe.com/dave` があり、Diagnostics タブを開いている
- **WHEN** ユーザーがコピーのボタンを押す
- **THEN** クリップボードに、Mewbell と macOS のバージョン、gh の項目、`alice` と `dave` の項目がテキストで入る

#### Scenario: Debug ビルドでコピーする

- **GIVEN** バージョンが `0.5.0` で、Debug 構成でビルドした Mewbell の Diagnostics タブを開いている
- **WHEN** ユーザーがコピーのボタンを押す
- **THEN** クリップボードのテキストに、`Mewbell (dev)` と `0.5.0-dev` が入る

#### Scenario: 上書きしたパスにトークンらしい文字列がある

- **GIVEN** gh の設定ディレクトリの上書きのパスに `ghp_` で始まる文字列が含まれている
- **WHEN** ユーザーがコピーのボタンを押す
- **THEN** クリップボードのテキストでは、その文字列が伏せ字になっている
