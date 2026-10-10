# Spec Delta

## Purpose

Mewbell のリリースの流れと配布物の約束を定める。release-please によるバージョンとタグの管理、macOS ランナーでのビルドと検査、配布物の中身、公開の順序、CI の資格情報の扱い、Homebrew tap の Cask の更新、インストールの案内を対象とする。

## ADDED Requirements

### Requirement: バージョンとリリースの起点

Mewbell のバージョンは `X.Y.Z`（それぞれ 0 以上の整数）の形式で、`project.xcproj` のプロジェクトの設定の 1 か所（`MARKETING_VERSION` と `CURRENT_PROJECT_VERSION`）にだけ書かなければならない（MUST）。バージョンの更新は release-please の Release PR だけで行い、Release PR は `main` に入った Conventional Commits から作らなければならない（SHALL）。Release PR をマージしたときに、タグ `vX.Y.Z` と draft の GitHub Release を作らなければならない（SHALL）。リリースのワークフローは `main` への push でだけ動き、`pull_request` や `pull_request_target` で動いてはならない（MUST NOT）。

#### Scenario: Release PR

- **GIVEN** 最新のリリースが `0.1.0` で、その後に `feat:` の PR が `main` にマージされた
- **WHEN** リリースのワークフローが動く
- **THEN** バージョンを `0.2.0` に上げて `CHANGELOG.md` を更新する Release PR ができる（または既存の Release PR が更新される）
- **AND** タグも Release も作られない

#### Scenario: Release PR をマージする

- **GIVEN** バージョンを `0.2.0` に上げる Release PR がある
- **WHEN** その PR が `main` にマージされる
- **THEN** タグ `v0.2.0` と draft の GitHub Release ができ、ビルドのジョブが始まる

### Requirement: ビルドと確認

ビルドのジョブは、タグのコミットを取り出し、決めたビルド番号の Xcode でビルドしなければならない（MUST）。その Xcode がランナーに無いときは、別の Xcode で代用せずに失敗しなければならない（MUST）。配布物を作る前に、ユニットテストと、警告をエラー扱いにした Debug と Release のビルドが通らなければならない（MUST）。1 つでも失敗したら配布物を作らずに失敗しなければならない（MUST）。

#### Scenario: すべて通る

- **GIVEN** タグ `v0.2.0` が作られ、ランナーに決めたビルド番号の Xcode がある
- **WHEN** ビルドのジョブが動く
- **THEN** テストと 2 つのビルドが通り、配布物の作成に進む

#### Scenario: Xcode が無い

- **GIVEN** ランナーのイメージが更新され、決めたビルド番号の Xcode が無くなった
- **WHEN** ビルドのジョブが動く
- **THEN** Xcode が見つからないことを表示して失敗し、Release は draft のまま残る

### Requirement: 署名と entitlement の検査

配布物を作る処理は、Release でビルドした `Mewbell.app` について次をすべて確かめ、1 つでも満たさないときは配布物を作らずに失敗しなければならない（MUST）。

- `codesign --verify --deep --strict` が通る（ad-hoc 署名でよい）
- コード署名のフラグに Hardened Runtime（`runtime`）が含まれる
- entitlement に `com.apple.security.get-task-allow`、`com.apple.security.cs.disable-library-validation`、`com.apple.security.cs.allow-dyld-environment-variables`、`com.apple.security.cs.allow-unsigned-executable-memory`、`com.apple.security.cs.allow-jit`、`com.apple.security.cs.disable-executable-page-protection` のいずれも含まれない
- Info.plist に `NSAppTransportSecurity` の例外（`NSAllowsArbitraryLoads` などの緩める設定と `NSExceptionDomains`）が無い
- Info.plist の `CFBundleIdentifier` が `com.codingfeline.mewbell`、`CFBundleShortVersionString` と `CFBundleVersion` がリリースのバージョンと一致する
- 実行ファイルが `arm64` と `x86_64` の両方を含む

Gatekeeper の評価（`spctl --assess`）は ad-hoc 署名では通らないため、検査の条件にしてはならない（MUST NOT）。

#### Scenario: 検査を通る

- **GIVEN** Release ビルドが Hardened Runtime 付きで ad-hoc 署名され、緩める entitlement と ATS の例外が無く、universal で、バージョンが `0.2.0`
- **WHEN** バージョン `0.2.0` として検査する
- **THEN** 検査を通る

#### Scenario: get-task-allow が付いている

- **GIVEN** Release ビルドの entitlement に `com.apple.security.get-task-allow` が入っている
- **WHEN** 検査する
- **THEN** その entitlement の名前を表示して失敗し、配布物は作られない

#### Scenario: Hardened Runtime が無効

- **GIVEN** Release ビルドのコード署名のフラグに `runtime` が無い
- **WHEN** 検査する
- **THEN** Hardened Runtime が無効なことを表示して失敗する

#### Scenario: バージョンがタグと違う

- **GIVEN** Release ビルドの `CFBundleShortVersionString` が `0.1.0`
- **WHEN** バージョン `0.2.0` として検査する
- **THEN** 一致しないことを表示して失敗する

### Requirement: 配布物

配布物を作る処理は、検査を通った `Mewbell.app` から次を作らなければならない（SHALL）。

- `Mewbell-X.Y.Z.zip`: `Mewbell.app` だけを、コード署名を壊さない方法で圧縮したもの。dSYM やビルドの中間ファイルを含めてはならない（MUST NOT）
- `Mewbell-X.Y.Z.zip.sha256`: zip の SHA-256（16 進数小文字）とファイル名
- `mewbell.rb`: Cask の雛形にバージョンと zip の SHA-256 を入れた Homebrew Cask（リリースのワークフローが作り、`brew style` と `brew audit --cask --strict` を通す）

作った zip を展開した `Mewbell.app` が同じ検査を通ることを確かめなければならない（MUST）。配布物には、トークン、gh の出力、ビルドした環境のパスを含む設定ファイルを入れてはならない（MUST NOT）。同じ処理を手元でも実行でき、手元では Release への添付も公開もしてはならない（MUST NOT）。

#### Scenario: 配布物を作る

- **GIVEN** バージョン `0.2.0` で、確認と検査をすべて通った
- **WHEN** 配布物を作る
- **THEN** `Mewbell-0.2.0.zip` と `Mewbell-0.2.0.zip.sha256` ができる（リリースのワークフローではさらに `mewbell.rb` ができる）
- **AND** zip の中身は `Mewbell.app` だけで、展開した `Mewbell.app` は検査を通る

### Requirement: 公開の順序

Release は、`mewbell.rb` が `brew style` と `brew audit` を通り、zip と `mewbell.rb` の build provenance attestation を作り、zip・SHA-256・`mewbell.rb` を添付し終えた後でだけ公開しなければならない（MUST）。Release を作った後のビルドは、後から来た `main` への push によって取り消されてはならない（MUST NOT）。ビルド・検査・添付のどこかで失敗したときは、Release を draft のまま残し、公開してはならない（MUST NOT）。公開済みの Release の添付ファイルを差し替えてはならない（MUST NOT）。tap への知らせは、Release を公開した後でだけ送らなければならない（MUST）。

#### Scenario: 添付してから公開する

- **GIVEN** `v0.2.0` の draft の Release があり、配布物ができた
- **WHEN** ビルドのジョブが続きを行う
- **THEN** zip・SHA-256・`mewbell.rb` が添付され、その後に Release が公開され、その後に tap へ知らせが送られる

#### Scenario: 検査で失敗する

- **GIVEN** `v0.2.0` の draft の Release がある
- **WHEN** 署名と entitlement の検査で失敗する
- **THEN** Release は draft のままで、添付ファイルは無く、tap へ知らせは送られない

### Requirement: CI の資格情報

リリースと tap の更新に使う資格情報は GitHub App のインストールトークンだけにし、個人のアクセストークン（PAT）を使ってはならない（MUST NOT）。App の秘密鍵は、`main` からの実行だけに限定した Environment のシークレットに置かなければならない（MUST）。トークンはジョブごとに発行し、対象のリポジトリと権限をそのジョブに要るものに絞らなければならない（MUST）。tap へ知らせるトークンは、`yshrsmz/homebrew-tap` だけを対象にし、Contents の書き込みだけを持たなければならない（MUST）。ワークフローの既定の `permissions` は `contents: read` にし、書き込みはそれが要るジョブにだけ与えなければならない（MUST）。テスト・ビルド・配布物の作成（リポジトリのコードと依存のコードを実行する処理）は、書き込み権限・OIDC トークン（`id-token: write`）・App の秘密鍵を持たないジョブで行わなければならない（MUST）。attestation・添付・公開・tap への知らせは、リポジトリのコードを実行しない別のジョブで行わなければならない（MUST）。トークンと秘密鍵をログに出してはならない（MUST NOT）。ワークフローで使う Action はコミット SHA で固定しなければならない（MUST）。

#### Scenario: tap へ知らせるトークン

- **GIVEN** `v0.2.0` の Release が公開された
- **WHEN** ビルドのジョブが tap へ知らせるトークンを発行する
- **THEN** そのトークンの対象は `yshrsmz/homebrew-tap` だけで、権限は Contents の書き込みだけである

#### Scenario: main 以外からの実行

- **GIVEN** `main` 以外のブランチからリリースのワークフローを動かそうとする
- **WHEN** Environment `release` のシークレットを読もうとする
- **THEN** Environment の制限で読めず、ジョブは失敗する

### Requirement: Homebrew tap の Cask の更新

Mewbell は、Release を公開した後に `yshrsmz/homebrew-tap` へ `repository_dispatch` を送り、payload にはバージョンだけを入れなければならない（SHALL）。tap 側のワークフローは payload を信用せず、次を満たさなければならない（MUST）。

- バージョンが `X.Y.Z` の形式でなければ何もせずに失敗する。payload の値をシェルのコマンドに直接埋め込まない
- 添付ファイルの URL をバージョンから `https://github.com/yshrsmz/mewbell/releases/download/vX.Y.Z/<file>` として組み立て、それ以外の URL を使わない
- zip と `mewbell.rb` の build provenance attestation を確かめ、`yshrsmz/mewbell` の `.github/workflows/release.yml` が `main` で作ったものでなければ失敗する
- zip を自分でダウンロードして SHA-256 を計算し、Release に添付された `.sha256` の値と一致しなければ失敗する（ダウンロードの破損を見つけるため）
- `mewbell.rb` の `version` が知らせのバージョンと、`sha256` が自分で計算した zip の SHA-256 と一致しなければ失敗する（attestation は Cask とバージョンを結び付けないため、別の版の Cask を差し込まれるのを防ぐ）
- Cask は確かめた `mewbell.rb` をそのまま使い、自分では作らない
- いまの Cask と同じか古いバージョンの知らせでは、何も変えずに終わる
- Cask を更新する PR を作り、tap の CI（`brew style` と `brew audit`）が通ったときだけ自動でマージする。この版の PR が開いているときはその PR を更新し、古い版の PR が開いているときは閉じる

#### Scenario: Cask を更新する

- **GIVEN** `v0.2.0` の Release が公開され、tap に `version: 0.2.0` の知らせが届いた
- **WHEN** tap のワークフローが動く
- **THEN** attestation と `version`・`sha256` を確かめた `mewbell.rb` で `Casks/mewbell.rb` を更新する PR ができ、CI が通った後にマージされる

#### Scenario: 不正なバージョン

- **GIVEN** tap に `version: 0.2.0; rm -rf /` の知らせが届いた
- **WHEN** tap のワークフローが動く
- **THEN** 形式が違うことを表示して失敗し、ダウンロードも PR も行わない

#### Scenario: 古い版の知らせ

- **GIVEN** tap の Cask が `0.2.0` で、`version: 0.1.0` の知らせが届いた
- **WHEN** tap のワークフローが動く
- **THEN** 更新しないことを表示して終わり、ダウンロードも PR も行わない

#### Scenario: 差し替えられた zip

- **GIVEN** 誰かが Release の zip・`.sha256`・`mewbell.rb` を、互いに一致する別のものに差し替えた
- **WHEN** tap のワークフローが確かめる
- **THEN** attestation を確かめられずに失敗し、PR を作らない

#### Scenario: 別の版の Cask

- **GIVEN** 誰かが `v0.3.0` の Release に、`v0.2.0` の正しい zip・`.sha256`・`mewbell.rb` を添付した
- **WHEN** tap に `version: 0.3.0` の知らせが届く
- **THEN** `mewbell.rb` の `version` が `0.3.0` ではないので失敗し、PR を作らない

#### Scenario: SHA-256 が合わない

- **GIVEN** ダウンロードした zip の SHA-256 が、Release に添付された `.sha256` の値と違う
- **WHEN** tap のワークフローが比べる
- **THEN** 失敗し、PR を作らない

### Requirement: Homebrew Cask の中身

Homebrew Cask（`Casks/mewbell.rb`）は次を満たさなければならない（SHALL）。

- `version` がリリースのバージョン、`sha256` が zip の SHA-256 と一致する
- `url` が `https://github.com/yshrsmz/mewbell/releases/download/v#{version}/Mewbell-#{version}.zip` である
- `depends_on macos: :tahoe`（macOS 26 以上。今の Homebrew では `">= :tahoe"` ではなくこの書き方）を持つ
- `app "Mewbell.app"` で `/Applications` に入れる
- アンインストールのときに `com.codingfeline.mewbell` を終了させる
- `zap` で `~/Library/Application Support/com.codingfeline.mewbell`（二重起動防止のロックファイル）と `~/Library/Preferences/com.codingfeline.mewbell.plist` を消す
- `caveats` で、Mewbell が notarize されておらず初回起動で Gatekeeper に止められること、システム設定の「プライバシーとセキュリティ」の「このまま開く」で開けること、更新のたびに同じ操作が要ること、gh CLI が要ることを案内する

Cask は quarantine 属性を消してはならず（MUST NOT）、`postflight` や `postflight_steps` などで `xattr` を実行したり Gatekeeper を迂回したりする処理を入れてはならない（MUST NOT）。

#### Scenario: Cask でインストールする

- **GIVEN** `yshrsmz/tap` を tap して `brew trust` 済みの macOS 26 の Mac
- **WHEN** ユーザーが `brew install --cask yshrsmz/tap/mewbell` を実行する
- **THEN** `/Applications/Mewbell.app` が入り、`caveats` が表示される
- **AND** 初回起動で Gatekeeper に止められ、システム設定の「このまま開く」で起動できる

### Requirement: インストールと更新の案内

README には、Homebrew（`yshrsmz/tap` の tap、`brew trust`、`brew install --cask`）と GitHub Releases の zip からのインストール、更新、アンインストールの手順を書かなければならない（SHALL）。Gatekeeper に止められたときの手順は、システム設定の「プライバシーとセキュリティ」の「このまま開く」を案内しなければならない（SHALL）。Gatekeeper をシステム全体で無効にする手順（`spctl --master-disable` など）を案内してはならない（MUST NOT）。ad-hoc 署名のため更新の後に通知の許可やログイン項目の登録が外れる場合は、そのことと設定し直す手順を README と Cask の `caveats` に書かなければならない（SHALL）。

#### Scenario: Gatekeeper に止められた

- **GIVEN** ユーザーが README を見ながら Releases の zip から Mewbell を入れ、初回起動で止められた
- **WHEN** README の手順を読む
- **THEN** システム設定の「プライバシーとセキュリティ」の「このまま開く」で開く手順が書かれている
- **AND** Gatekeeper をシステム全体で無効にする手順は書かれていない
