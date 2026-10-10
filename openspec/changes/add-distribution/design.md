# Design

## Context

- 今のビルドは `scripts/build.sh` で `build/<Configuration>/Mewbell.app` を作るだけ。署名は `CODE_SIGN_IDENTITY: "-"`（ad-hoc）、`CODE_SIGN_STYLE: Manual`。Hardened Runtime は有効で、Release では `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` にして `get-task-allow` を入れていない。entitlements のファイルは無い
- `ONLY_ACTIVE_ARCH` は Debug だけ `YES`。Release は既定のアーキテクチャ（`arm64 x86_64`）で universal になる見込み（実装で `lipo -archs` で確かめる）
- バージョンは `MARKETING_VERSION: 0.1.0`、`CURRENT_PROJECT_VERSION: 1` を Mewbell と MewbellTests の 2 つのターゲットに書いている。タグとリリースはまだ無い。`CFBundleShortVersionString` は API の `User-Agent` と Diagnostics のコピーに使っている
- CI は ubuntu で lint と `openspec validate` だけ。macOS ランナーは使わない方針なので、ビルドと配布物の作成は手元で行う
- 手元の Homebrew は 7.0.9。サードパーティの tap を読むには `brew trust` が要る。`--no-quarantine` は無い。Gatekeeper の確認（`audit_signing`）は `brew audit` の中にあり、インストールは止めない。macOS 26 の symbol は `:tahoe`
- `yshrsmz/homebrew-tap` はまだ無い

## Goals / Non-Goals

**Goals:**

- 1 つのコマンドで、確認 → Release ビルド → 検査 → zip・SHA-256・Cask の作成までを行い、途中で失敗したら何も残さない
- 署名と entitlement の約束（`.claude/rules/security.md` の「アプリとビルドの設定」）を、配布物を作るたびに機械的に確かめる
- Gatekeeper の手順と、ad-hoc 署名による更新時の影響を、利用者に正直に案内する

**Non-Goals:**

- Developer ID の署名、notarize、staple（ad-hoc のまま）
- 自動更新（Sparkle、アプリ内の新版チェック）
- CI でのリリース（macOS ランナーを使わない）
- 公式の homebrew-cask への登録
- dmg の作成（Cask と手動のインストールのどちらも zip で足りる）
- アプリのコードの変更（実行中の振る舞いは変えない）

## Decisions

### リリーススクリプトは bash 1 本で、段階ごとに止める

`scripts/release.sh X.Y.Z` が次の順に進め、どこかで失敗したら 0 以外で終わる（`set -euo pipefail`）。既存の `build.sh` と同じく bash で書き、`bash scripts/release.sh` で実行する（`chmod` しない）。

1. 引数の形式（`X.Y.Z`）の確認
2. git の確認: 作業ツリーが clean、ブランチが `main`、`git fetch origin` の後に `HEAD == origin/main`、タグ `vX.Y.Z` がローカルにもリモート（`git ls-remote --tags origin`）にも無い
3. バージョンの確認: `xcodebuild -showBuildSettings -configuration Release` の `MARKETING_VERSION` が引数と一致し、`CURRENT_PROJECT_VERSION` が正の整数
4. push 前の確認: `xcodebuild test`、`bash scripts/lint.sh`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルド
5. Release ビルド: `bash scripts/build.sh Release` で作った `build/Release/Mewbell.app` を使う
6. 検査（後述の `verify_app`）
7. 配布物の作成: `build/release/X.Y.Z/` を作り直し、`ditto -c -k --sequesterRsrc --keepParent` で zip、`shasum -a 256` で SHA-256、雛形から `mewbell.rb`
8. 展開した zip の再検査: 一時ディレクトリに `ditto -x -k` で展開し、同じ `verify_app` を通す
9. 公開のコマンドを表示して終わる

途中で失敗したときに半端な配布物が残らないよう、配布物は一時ディレクトリに作ってから、すべて通った後に `build/release/X.Y.Z/` へ移す。

代替案: Makefile や Swift のスクリプトにする。既存のスクリプトが bash で揃っており、使うのが `xcodebuild`・`codesign`・`plutil`・`ditto`・`shasum`・`git` だけなので、bash で足りる。

### 検査は関数にまとめ、偽の .app でテストする

検査は `verify_app <path-to-.app>` にまとめ、`scripts/lib/verify-app.sh` に置いて `release.sh` から `source` する。`codesign --verify --deep --strict`、`codesign -dv` の `flags=` に `runtime` があること、`codesign -d --entitlements - --xml` を `plutil` で読んで禁止の entitlement が無いこと、Info.plist（`plutil -extract`）に `NSAppTransportSecurity` の緩める設定が無いことと `CFBundleIdentifier`、`lipo -archs` に `arm64` と `x86_64` があることを確かめる。

検査が実際に失敗を見つけられることを確かめるため、`scripts/tests/verify-app-test.sh` を作る。小さな C の実行ファイルを `clang` でビルドして偽の `.app` を作り、正常なもの（Hardened Runtime 付きの ad-hoc 署名）が通ること、`get-task-allow` 付き・`runtime` 無し・`NSAllowsArbitraryLoads` 付き・単一アーキテクチャがそれぞれ失敗することを確かめる。Xcode のユニットテストではなくシェルのテストにするのは、検査の対象がビルドの成果物で、アプリのコードではないため。CI（ubuntu）では `codesign` が無いので動かさず、リリースの前の確認の 1 つとして `release.sh` からも実行する。

代替案: 検査を書かずに目で確かめる。リリースのたびに忘れずに確かめるのは難しく、security.md の約束を守れているかの根拠にならないので採らない。

### バージョンの正本は MARKETING_VERSION

タグ・zip の名前・Cask の `version` は、すべて `MARKETING_VERSION` から決める。リリースの前に `project.xcproj` の 2 つのターゲットの `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を上げる PR を出し、マージしてから `release.sh` を実行する。`CURRENT_PROJECT_VERSION` はリリースごとに 1 ずつ増やす。

代替案: `agvtool` やスクリプトで書き換える。`project.xcproj` は JSON 形式で、`agvtool` が対応しているか確かめていない。2 行の書き換えなので手で行い、README のリリース手順に書く。最初のリリースは今の `0.1.0` / `1` のままにする。

### Cask の雛形はこのリポジトリに置く

`packaging/homebrew/mewbell.rb.template` に `@VERSION@` と `@SHA256@` を置き、`release.sh` が `sed` で埋める。Cask の中身のレビューをこのリポジトリの PR でできるようにするためで、tap のリポジトリには生成した `mewbell.rb` をコピーしてコミットするだけにする。

```ruby
cask "mewbell" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/yshrsmz/mewbell/releases/download/v#{version}/Mewbell-#{version}.zip"
  name "Mewbell"
  desc "Menu bar app for GitHub notifications across gh CLI accounts"
  homepage "https://github.com/yshrsmz/mewbell"

  depends_on macos: ">= :tahoe"

  app "Mewbell.app"

  uninstall quit: "com.codingfeline.mewbell"

  zap trash: "~/Library/Preferences/com.codingfeline.mewbell.plist"

  caveats <<~EOS
    （Gatekeeper の「このまま開く」、更新のたびに必要なこと、gh CLI が要ること）
  EOS
end
```

gh は `depends_on formula: "gh"` にしない。Homebrew 以外で入れた gh を使う人もいて、Mewbell は gh の場所を設定で上書きできるため、`caveats` での案内にとどめる。ログイン項目（`SMAppService`）はアプリの削除で macOS が外すので、`uninstall` には入れない。

`brew style` と `brew audit --cask --strict` を、tap に置いた後に手元で実行する（`audit_signing` は notarize していないので失敗する見込みで、それは許容する）。

### 公開は表示したコマンドを手で実行する

タグの push、`gh release create vX.Y.Z build/release/X.Y.Z/Mewbell-X.Y.Z.zip --draft --title … --notes …`、tap への `mewbell.rb` のコピーとコミット・push は、どれも外に出て取り消しにくい操作なので、`release.sh` は実行せずにコマンドを表示する。draft のリリースの添付ファイルの SHA-256 が手元の値と一致することを確かめてから公開する手順を README に書く。

代替案: `--publish` の引数で自動化する。年に数回のリリースで、失敗したときの後始末（タグの削除など）のほうが手間なので、v1 では採らない。

### tap は `yshrsmz/homebrew-tap`

`brew tap yshrsmz/tap` で使える名前にする。リポジトリの作成は外部に出る操作なので、実装のときにユーザーに確かめてから `gh repo create` する。tap のリポジトリには `Casks/mewbell.rb` と短い README だけを置き、CI は入れない。

### ad-hoc 署名と更新の影響は確かめてから書く

ad-hoc 署名の designated requirement は cdhash に結び付くため、ビルドし直すと別のコードとして扱われる。通知の許可（`UNUserNotificationCenter`、バンドル ID で管理される見込み）とログイン項目（`SMAppService`）が更新の後に残るかは、実際に 2 つのリリースビルドを入れ替えて確かめる（tasks の手動確認）。結果に応じて README と `caveats` の文を決める。外れる場合でも、アプリのコードで回避する（Developer ID を使う以外の方法で要件を固定する）ことはしない。

## Risks / Trade-offs

- [初回起動と更新のたびに Gatekeeper に止められる] → `caveats` と README で手順を案内する。quarantine を消す自動化はしない（ユーザーの判断で選んだ方針）。不便が大きければ、後で Developer ID と notarize を別の change で入れる
- [ad-hoc 署名のため、更新の後に通知の許可やログイン項目が外れるかもしれない] → 実機で確かめ、外れるなら設定し直す手順を案内する
- [Homebrew の仕様の変化（`brew trust`、`postflight_steps` など）が速い] → Cask は最小限の stanza だけにし、リリースのたびに `brew style` と `brew audit` を実行する
- [バージョンの上げ忘れ] → `release.sh` がタグの重複と `MARKETING_VERSION` の不一致で止まる
- [検査の抜け（禁止の entitlement の一覧が古くなる）] → 一覧は security.md の項目に合わせ、security.md を変えたときは `verify-app.sh` も見直すことを README のリリース手順に書く
- [universal にするとビルドの時間と zip が大きくなる] → 許容する。macOS 26 は Intel の Mac でも動くため

## セキュリティ

- トークンの流れ: この change はアプリのコードを変えないため、トークンの取得・保持・送信・破棄は変わらない。配布物にトークンを含むファイルは入らない（zip の中身は `Mewbell.app` だけで、設定や gh の出力はビルドに含まれない）
- `.claude/rules/security.md` への対応:
  - トークンの扱い・gh サブプロセス・ネットワーク: 該当しない（アプリのコードに触れない）。spec のルールにある API のエンドポイントとステータスコードも、この capability は API を使わないので該当しない
  - アプリとビルドの設定: Release の Hardened Runtime、緩める entitlement が無いこと、`get-task-allow` が無いこと、ATS の例外が無いことを `verify_app` で配布物ごとに確かめ、偽の .app のテストで検査そのものを確かめる
  - 依存とサプライチェーン: 依存を追加しない。CI のワークフローは変えず、シークレットを渡さない。Cask の `url` は `https` の GitHub Releases だけを指し、`sha256` を必ず入れる（`:no_check` にしない）
  - 公開: `gh release create` は開発者の gh の認証で実行するコマンドを表示するだけで、スクリプトはトークンを読まず、ログにも出さない
- Gatekeeper: quarantine を消す処理を Cask に入れず、Gatekeeper をシステム全体で無効にする手順も案内しない

## Migration Plan

1. この change をマージする
2. `yshrsmz/homebrew-tap` を作る（ユーザーに確かめてから）
3. `bash scripts/release.sh 0.1.0` で配布物を作り、表示されたコマンドでタグ・draft のリリース・tap の Cask を公開する
4. 別の場所（`/Applications`）に入れて、Gatekeeper の手順と起動を確かめる

戻すとき: GitHub Releases のリリースとタグを消し、tap の Cask を消す。アプリのコードは変えていないので、手元のビルドには影響しない。
