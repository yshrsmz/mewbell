# Spec Delta

## Purpose

Mewbell のリリース用の配布物（zip、SHA-256、Homebrew Cask）を手元で作るときの約束を定める。作る前に確かめること（バージョン、テストとビルド、署名と entitlement、ATS）、配布物の中身、Cask とインストール手順に含めるものと含めてはならないもの、公開を自動で行わないことを対象とする。

## ADDED Requirements

### Requirement: リリースのバージョン

リリースのバージョンは `X.Y.Z`（それぞれ 0 以上の整数）の形式でなければならず（MUST）、リリーススクリプトに渡したバージョンが Mewbell の `CFBundleShortVersionString`（`MARKETING_VERSION`）と一致しないときは、配布物を作らずに失敗しなければならない（MUST）。リリースのタグは `vX.Y.Z` とし、同じ名前のタグがローカルにもリモート（`origin`）にもすでにあるときは、配布物を作らずに失敗しなければならない（MUST）。Mewbell の `CFBundleVersion`（`CURRENT_PROJECT_VERSION`）は正の整数でなければならない（MUST）。

#### Scenario: バージョンが一致する

- **GIVEN** `MARKETING_VERSION` が `0.1.0` で、タグ `v0.1.0` はまだ無い
- **WHEN** 開発者が `0.1.0` を指定してリリーススクリプトを実行する
- **THEN** バージョンの確認を通り、次の確認に進む

#### Scenario: バージョンが一致しない

- **GIVEN** `MARKETING_VERSION` が `0.1.0`
- **WHEN** 開発者が `0.2.0` を指定してリリーススクリプトを実行する
- **THEN** 一致しないことを表示して、0 以外の終了コードで終わる
- **AND** 配布物は作られない

#### Scenario: タグがすでにある

- **GIVEN** リモートにタグ `v0.1.0` がすでにある
- **WHEN** 開発者が `0.1.0` を指定してリリーススクリプトを実行する
- **THEN** タグがあることを表示して、0 以外の終了コードで終わる

### Requirement: リリースの前の確認

リリーススクリプトは、配布物を作る前に次をすべて確かめ、1 つでも満たさないときは配布物を作らずに失敗しなければならない（MUST）。

- 作業ツリーに未コミットの変更が無く、`main` ブランチにいて、`HEAD` が `origin/main` と同じコミットである
- ユニットテストが通る
- lint（`swift-format lint` と `swiftlint`）が通る
- 警告をエラー扱いにした Debug と Release のビルドが通る

配布物は、確認に使ったのと同じコミットからビルドしなければならない（MUST）。

#### Scenario: すべて通る

- **GIVEN** `main` が `origin/main` と同じで、作業ツリーに変更が無く、テスト・lint・ビルドがすべて通る
- **WHEN** 開発者がリリーススクリプトを実行する
- **THEN** 配布物のビルドに進む

#### Scenario: 未コミットの変更がある

- **GIVEN** 作業ツリーに未コミットの変更がある
- **WHEN** 開発者がリリーススクリプトを実行する
- **THEN** 未コミットの変更があることを表示して、0 以外の終了コードで終わる
- **AND** テストもビルドも実行しない

#### Scenario: テストが失敗する

- **GIVEN** ユニットテストの 1 つが失敗する
- **WHEN** 開発者がリリーススクリプトを実行する
- **THEN** 0 以外の終了コードで終わり、配布物は作られない

### Requirement: 署名と entitlement の検査

リリーススクリプトは、Release でビルドした `Mewbell.app` について次をすべて確かめ、1 つでも満たさないときは配布物を作らずに失敗しなければならない（MUST）。

- `codesign --verify --deep --strict` が通る（ad-hoc 署名でよい）
- コード署名のフラグに Hardened Runtime（`runtime`）が含まれる
- entitlement に `com.apple.security.get-task-allow`、`com.apple.security.cs.disable-library-validation`、`com.apple.security.cs.allow-dyld-environment-variables`、`com.apple.security.cs.allow-unsigned-executable-memory`、`com.apple.security.cs.allow-jit`、`com.apple.security.cs.disable-executable-page-protection` のいずれも含まれない
- Info.plist に `NSAppTransportSecurity` の例外（`NSAllowsArbitraryLoads` などの緩める設定と `NSExceptionDomains`）が無い
- Info.plist の `CFBundleIdentifier` が `com.codingfeline.mewbell` である
- 実行ファイルが `arm64` と `x86_64` の両方を含む

Gatekeeper の評価（`spctl --assess`）は ad-hoc 署名では通らないため、検査の条件にしてはならない（MUST NOT）。

#### Scenario: 検査を通る

- **GIVEN** Release ビルドが Hardened Runtime 付きで ad-hoc 署名され、緩める entitlement と ATS の例外が無く、universal である
- **WHEN** リリーススクリプトが検査する
- **THEN** 検査を通り、配布物の作成に進む

#### Scenario: get-task-allow が付いている

- **GIVEN** Release ビルドの entitlement に `com.apple.security.get-task-allow` が入っている
- **WHEN** リリーススクリプトが検査する
- **THEN** その entitlement の名前を表示して、0 以外の終了コードで終わる
- **AND** 配布物は作られない

#### Scenario: Hardened Runtime が無効

- **GIVEN** Release ビルドのコード署名のフラグに `runtime` が無い
- **WHEN** リリーススクリプトが検査する
- **THEN** Hardened Runtime が無効なことを表示して、0 以外の終了コードで終わる

#### Scenario: ATS の例外がある

- **GIVEN** Release ビルドの Info.plist に `NSAppTransportSecurity` の `NSAllowsArbitraryLoads` が入っている
- **WHEN** リリーススクリプトが検査する
- **THEN** ATS の例外があることを表示して、0 以外の終了コードで終わる

### Requirement: 配布物

リリーススクリプトは、検査を通った `Mewbell.app` から次の配布物を `build/release/X.Y.Z/` に作らなければならない（SHALL）。

- `Mewbell-X.Y.Z.zip`: `Mewbell.app` だけを、コード署名と拡張属性を壊さない方法で圧縮したもの。dSYM やビルドの中間ファイルを含めてはならない（MUST NOT）
- `Mewbell-X.Y.Z.zip.sha256`: zip の SHA-256（16 進数小文字）とファイル名
- `mewbell.rb`: バージョンと SHA-256 を入れた Homebrew Cask

作った zip を展開した `Mewbell.app` が、同じ署名と entitlement の検査を通ることを確かめなければならない（MUST）。配布物には、トークン、gh の出力、開発者の環境のパス（ユーザーのホームディレクトリなど）を含む設定ファイルを入れてはならない（MUST NOT）。

#### Scenario: 配布物を作る

- **GIVEN** バージョン `0.1.0` で、確認と検査をすべて通った
- **WHEN** リリーススクリプトが配布物を作る
- **THEN** `build/release/0.1.0/` に `Mewbell-0.1.0.zip`、`Mewbell-0.1.0.zip.sha256`、`mewbell.rb` ができる
- **AND** zip の中身は `Mewbell.app` だけである
- **AND** zip を展開した `Mewbell.app` は署名と entitlement の検査を通る

### Requirement: Homebrew Cask

Homebrew Cask（`mewbell.rb`）は次を満たさなければならない（SHALL）。

- `version` がリリースのバージョン、`sha256` が zip の SHA-256 と一致する
- `url` が `https://github.com/yshrsmz/mewbell/releases/download/vX.Y.Z/Mewbell-X.Y.Z.zip` である（`https` だけを使う）
- `depends_on macos: ">= :tahoe"`（macOS 26 以上）を持つ
- `app "Mewbell.app"` で `/Applications` に入れる
- アンインストールのときに `com.codingfeline.mewbell` を終了させる
- `zap` で `~/Library/Preferences/com.codingfeline.mewbell.plist` を消す
- `caveats` で、Mewbell が notarize されておらず初回起動で Gatekeeper に止められること、システム設定の「プライバシーとセキュリティ」の「このまま開く」で開けること、更新のたびに同じ操作が要ること、gh CLI が要ることを案内する

Cask は quarantine 属性を消してはならず（MUST NOT）、`postflight` や `postflight_steps` などで `xattr` を実行したり Gatekeeper を迂回したりする処理を入れてはならない（MUST NOT）。

#### Scenario: Cask の中身

- **GIVEN** バージョン `0.1.0` の zip の SHA-256 が `abc…`（64 桁）
- **WHEN** リリーススクリプトが `mewbell.rb` を作る
- **THEN** `version "0.1.0"`、`sha256 "abc…"`、`v0.1.0` のリリースの zip を指す `https` の `url` が入っている
- **AND** `depends_on macos: ">= :tahoe"`、`app "Mewbell.app"`、`caveats` がある
- **AND** `xattr` を実行する処理は無い

#### Scenario: Cask でインストールする

- **GIVEN** `yshrsmz/tap` を tap して `brew trust` 済みの macOS 26 の Mac
- **WHEN** ユーザーが `brew install --cask yshrsmz/tap/mewbell` を実行する
- **THEN** `/Applications/Mewbell.app` が入り、`caveats` が表示される
- **AND** 初回起動で Gatekeeper に止められ、システム設定の「このまま開く」で起動できる

### Requirement: 公開を自動で行わない

リリーススクリプトは配布物を作るところまでで止まり、タグの push、GitHub Releases の作成、tap のリポジトリへの push を自動で行ってはならない（MUST NOT）。公開に使うコマンド（タグの作成と push、`gh release create`、tap の更新）は、配布物を作った後に表示しなければならない（SHALL）。GitHub Releases は draft で作り、開発者が中身を確かめてから公開する手順でなければならない（SHALL）。

#### Scenario: 配布物を作った後

- **GIVEN** リリーススクリプトが配布物を作り終えた
- **WHEN** スクリプトが終わる
- **THEN** タグはローカルにもリモートにも作られていない
- **AND** タグの作成と push、draft のリリースを作る `gh release create … --draft`、tap の更新のコマンドが表示される

### Requirement: インストールと更新の案内

README には、Homebrew（`yshrsmz/tap` の tap、`brew trust`、`brew install --cask`）と GitHub Releases の zip からのインストール、更新、アンインストールの手順を書かなければならない（SHALL）。Gatekeeper に止められたときの手順は、システム設定の「プライバシーとセキュリティ」の「このまま開く」を案内しなければならない（SHALL）。Gatekeeper をシステム全体で無効にする手順（`spctl --master-disable` など）を案内してはならない（MUST NOT）。ad-hoc 署名のため更新の後に通知の許可やログイン項目の登録が外れる場合は、そのことと設定し直す手順を README と Cask の `caveats` に書かなければならない（SHALL）。

#### Scenario: Gatekeeper に止められた

- **GIVEN** ユーザーが README を見ながら Releases の zip から Mewbell を入れ、初回起動で止められた
- **WHEN** README の手順を読む
- **THEN** システム設定の「プライバシーとセキュリティ」の「このまま開く」で開く手順が書かれている
- **AND** Gatekeeper をシステム全体で無効にする手順は書かれていない
