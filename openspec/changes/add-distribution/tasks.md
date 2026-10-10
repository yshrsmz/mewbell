# Tasks

## 1. バージョンと署名・entitlement の検査（mewbell）

- [ ] 1.1 `project.xcproj` の `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を 2 つのターゲットから消し、プロジェクトの設定に `0.1.0` で 1 回だけ書き、`// x-release-please-start-version` と `// x-release-please-end` の行で囲む（D2）。確認: `xcodebuild -showBuildSettings -configuration Release` で両ターゲットの 2 つの値が `0.1.0`、`bash scripts/build.sh Release` の Info.plist の `CFBundleShortVersionString` と `CFBundleVersion` が `0.1.0`、`lipo -archs` が `x86_64 arm64`（universal でなければ Release に `ARCHS` を設定する）。Diagnostics のコピーと `User-Agent` のバージョンが変わらず `0.1.0` であることをテストで確かめる（既存のテストが通る）
- [ ] 1.2 `scripts/lib/verify-app.sh` に `verify_app <path-to-.app> <version>` を作る（D4。spec の「署名と entitlement の検査」の項目をすべて確かめ、満たさない項目の名前を表示して 0 以外で返す。`spctl --assess` は使わない）。確認: `build/Release/Mewbell.app` と `0.1.0` で通り、`0.2.0` では失敗する
- [ ] 1.3 `scripts/tests/verify-app-test.sh` を作る（D4）。確認: スクリプトを実行して、(a) 正常な偽の .app が通る、(b) `get-task-allow` 付き、(c) `-o runtime` 無し、(d) `NSAllowsArbitraryLoads` 付き、(e) `arm64` だけ、(f) `CFBundleIdentifier` 違い、(g) バージョン違い、(h) 署名後に中のファイルを書き換えたもの、がそれぞれ失敗し、失敗した項目の名前が出る
- [ ] 1.4 `scripts/package-release.sh X.Y.Z` を作る（D4。形式の確認、Release ビルド、`verify_app`、一時ディレクトリでの zip と `.sha256`、展開した zip の `verify_app`、すべて通った後の `build/release/X.Y.Z/` への移動。添付・公開・dispatch はしない）。確認: `bash scripts/package-release.sh 0.1.0` で (a) 2 つのファイルができる、(b) `unzip -l` の中身が `Mewbell.app/` の下だけ、(c) `shasum -a 256 -c` が通る、(d) `abc` を渡すと形式のエラー、(e) `0.2.0` を渡すと検査で失敗し `build/release/0.2.0/` が作られない

## 2. Cask の雛形（mewbell と homebrew-tap）

- [x] 2.1 `yshrsmz/homebrew-tap` を用意し、`Casks/` と短い README（使い方、`brew trust`、Gatekeeper の「このまま開く」、quarantine を消さないこと）を置く。確認: `brew tap yshrsmz/tap` が通る。結果: リポジトリはユーザーが作った
- [ ] 2.2 `packaging/homebrew/mewbell.rb.template` を作る（spec の「Homebrew Cask の中身」。`@VERSION@` と `@SHA256@`。`xattr` や `postflight` は入れない）。確認: 1.4 の zip の値で埋めたものを手元の tap の clone に置き、`brew style` と `brew audit --cask --strict` が通る（Linux で `brew audit --cask` が動くかもここで確かめ、D5 の Open Question を閉じる）

## 3. GitHub App と Environment（ユーザーの作業を含む）

- [ ] 3.1 2 つの GitHub App の作り方（D6 の表の権限、Webhook 無効、自分のアカウントだけ）、インストール先、Environment `release`（`main` だけ）、変数 `RELEASE_APP_CLIENT_ID` とシークレット `RELEASE_APP_PRIVATE_KEY` の置き場所を手順にまとめてユーザーに渡し、ユーザーが作る。確認: `gh api repos/yshrsmz/mewbell/environments/release` と `gh api repos/yshrsmz/homebrew-tap/environments/release` で Environment とブランチの制限が見え、`gh variable list --env release` に Client ID がある（シークレットの値は読まない）
- [ ] 3.2 homebrew-tap で auto-merge を有効にし、`main` に `ci` のチェックを必須にする ruleset を作ってよいかを AskUserQuestion で確かめてから設定する。確認: `gh api repos/yshrsmz/homebrew-tap --jq .allow_auto_merge` が `true`、`gh api repos/yshrsmz/homebrew-tap/rulesets` に ruleset がある

## 4. ワークフロー

- [ ] 4.1 `release-please-config.json` と `.release-please-manifest.json` を置く（D1）。確認: release-please の CLI（`npx` で一時的に固定版を実行するか、Action の dry-run）で、`project.xcproj` の印の中の 2 つの値と `version.txt`・`CHANGELOG.md` が更新対象になることを確かめる。最初の Release PR を `0.1.0` にする方法（`Release-As` かマニフェスト `0.0.0`）を決めて design の Open Question を閉じる
- [ ] 4.2 `.github/workflows/release.yml` を作る（D3）。Action は公開から 7 日以上経った版のコミット SHA で固定し、`gh api repos/<owner>/<repo>/releases` で公開日を確かめる。`${{ }}` の値は `env:` を通して使う。確認: `actionlint`（mise で固定して入れる場合はバージョンを固定する。入れない場合は差分を読む）で問題が無く、ワークフローの既定が `contents: read`、`build` ジョブだけが `contents: write`、App のトークンの範囲が D3 のとおりであることを差分で確かめる
- [ ] 4.3 `xcode-27` のラベルと `/Applications/Xcode_27.2_beta_2.app` のビルド番号を、本番の前に確かめる。`workflow_dispatch` だけで動く一時的なワークフローを作業ブランチに置き、`xcodebuild -version` と `bash scripts/tests/verify-app-test.sh` と `bash scripts/package-release.sh 0.1.0` を実行する（添付・公開はしない）。確認: ジョブが 60 分以内に走り切り、ビルド番号が `27B5028f`、検査のテストと配布物の作成が通る。確かめたら一時的なワークフローを消す
- [ ] 4.4 homebrew-tap に `.github/templates/mewbell.rb.template`（2.2 のコピー）、`.github/workflows/update-cask.yml`、`.github/workflows/ci.yml` を作る（D5）。Action は SHA で固定し、既定の `permissions: contents: read`。確認: (a) `gh workflow run` が使えないので、`gh api repos/yshrsmz/homebrew-tap/dispatches` で `version: 0.0.0-bad` を送ると形式のエラーで失敗し PR ができない、(b) 存在しないバージョン `9.9.9` を送るとダウンロードで失敗する、(c) 手で作った Cask の PR で `ci` が走って通る。(a)(b) の dispatch は自分の gh の認証で送る（ユーザーに確かめてから）

## 5. ドキュメントと規則

- [ ] 5.1 README に「インストール」の節を足す: Homebrew（`brew tap yshrsmz/tap`、`brew trust`、`brew install --cask yshrsmz/tap/mewbell`）、Releases の zip から `/Applications` に入れる方法、初回起動で Gatekeeper に止められたときの「このまま開く」、更新（更新のたびに同じ操作が要ること）、アンインストール（`--zap` を含む）。冒頭の「開発中」の注記を M5 に合わせる。確認: 差分を読み、`spctl --master-disable` や quarantine を消す手順を勧めていない
- [ ] 5.2 README の「開発」に「リリース」の節を足す: release-please の流れ、Release PR のマージ、失敗したときの `gh run rerun --failed` と、コードを直すときの draft とタグの消し方、Xcode のイメージが変わったときに `XCODE_BUILD` とパスを上げること、App の鍵が漏れたときの失効と作り直し、手元での `package-release.sh` の使い方。確認: 差分を読み、design の D3 と D6 と食い違いが無い
- [ ] 5.3 CLAUDE.md と `.claude/rules/security.md` を D7 のとおりに改め、SETUP.md の M5 の行から Sparkle を外す。確認: 差分を読み、`openspec/config.yaml` の context と、`.github/workflows/ci.yml` の冒頭のコメント（macOS ランナーを使わない理由）と食い違いが無い（必要ならコメントも直す）

## 6. 最初のリリースと実機での確認

- [ ] 6.1 ad-hoc 署名の更新の影響を確かめる: バージョンだけを変えた 2 つの Release ビルドを作り、`codesign -dr -` の designated requirement が違うことを見たうえで、1 つ目を `/Applications` に入れて通知を許可しログイン項目に登録し、2 つ目で置き換えて起動する。確認: 通知の許可とログイン項目の登録が残るかを記録し、外れるなら README と Cask の `caveats` に設定し直す手順を書く。handover の「ad-hoc 署名のローカルビルドで、再ビルドの後も通知の許可が残るか」もこれで閉じる
- [ ] 6.2 この change を main にマージした後、最初の Release PR を `0.1.0` にしてマージしてよいかをユーザーに確かめてからマージする。確認: (a) タグ `v0.1.0` と draft ができ、(b) `build` ジョブが通って zip と `.sha256` が添付されてから公開され、(c) tap に Cask の PR ができ、`ci` が通って自動でマージされ、(d) `curl -sL` で取った zip の SHA-256 が Cask と一致する。失敗したら draft のまま残っていることを確かめ、README の手順で直す
- [ ] 6.3 `/Applications/Mewbell.app` を消した状態で `brew install --cask yshrsmz/tap/mewbell` を実行する。確認: (a) `caveats` が表示される、(b) 初回起動で Gatekeeper に止められ、システム設定の「このまま開く」で起動できる、(c) メニューバーに猫が出て通知を取得でき、Diagnostics にバージョン `0.1.0` が出る、(d) `brew uninstall --cask --zap mewbell` で `/Applications/Mewbell.app` と `~/Library/Preferences/com.codingfeline.mewbell.plist` が消える

## 7. 最終確認

- [ ] 7.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [ ] 7.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test`、`bash scripts/lint.sh`、`bash scripts/tests/verify-app-test.sh`、`npx openspec validate --all --strict` が成功する
- [ ] 7.3 手元で起動して確認した: `bash scripts/package-release.sh 0.1.0` の zip を展開した `Mewbell.app` を起動し、メニューバーの猫、通知の取得、Diagnostics のバージョン `0.1.0` を確かめる

## 8. 別コンテキストでのレビュー

- [ ] 8.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/tests/verify-app-test.sh` と `bash scripts/lint.sh` が引き続き通る
- [ ] 8.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ワークフローやスクリプトのロジックに手を入れたら 8.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認（Hardened Runtime、entitlement、ATS、CI の資格情報の範囲、tap の payload の検証、Cask が Gatekeeper を迂回しないこと）を PR 本文に書いた
