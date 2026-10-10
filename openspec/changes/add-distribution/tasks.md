# Tasks

## 1. 署名と entitlement の検査

- [ ] 1.1 `scripts/lib/verify-app.sh` に `verify_app <path-to-.app>` を作る。`codesign --verify --deep --strict`、`codesign -dv` の `flags=` に `runtime`、`codesign -d --entitlements - --xml` に禁止の entitlement（`get-task-allow`、`disable-library-validation`、`allow-dyld-environment-variables`、`allow-unsigned-executable-memory`、`allow-jit`、`disable-executable-page-protection`）が無いこと、Info.plist に `NSAppTransportSecurity` の緩める設定と `NSExceptionDomains` が無いこと、`CFBundleIdentifier` が `com.codingfeline.mewbell`、`lipo -archs` に `arm64` と `x86_64` があることを確かめ、満たさない項目の名前を表示して 0 以外で返す。`spctl --assess` は使わない。確認: `bash scripts/build.sh Release` の `build/Release/Mewbell.app` に対して `verify_app` が通る（universal でなければ 1.3 で直す）
- [ ] 1.2 `scripts/tests/verify-app-test.sh` を作る。`clang` で小さな実行ファイル（`-arch arm64 -arch x86_64`）をビルドして偽の `.app` を一時ディレクトリに組み、Hardened Runtime 付きの ad-hoc 署名（`codesign -s - -o runtime`）で正常なものを作る。確認: スクリプトを実行して、(a) 正常なものが通る、(b) `get-task-allow` を付けて署名し直したもの、(c) `-o runtime` を外したもの、(d) Info.plist に `NSAllowsArbitraryLoads` を入れて署名し直したもの、(e) `arm64` だけのもの、(f) `CFBundleIdentifier` が違うもの、(g) 署名の後に中のファイルを書き換えたものが、それぞれ失敗し、失敗した項目の名前が出る
- [ ] 1.3 Release のビルドが universal で、`CURRENT_PROJECT_VERSION` / `MARKETING_VERSION` が 2 つのターゲットで揃っていることを確かめる。universal でなければ `project.xcproj` の Release に `ARCHS` を設定する。確認: `lipo -archs build/Release/Mewbell.app/Contents/MacOS/Mewbell` が `x86_64 arm64` を返し、`xcodebuild -project Mewbell.xcodeproj` でプロジェクトが開ける

## 2. リリーススクリプトと Cask の雛形

- [ ] 2.1 `packaging/homebrew/mewbell.rb.template` を作る（design の Cask の形。`@VERSION@` と `@SHA256@` を置き、`caveats` に Gatekeeper の「このまま開く」、更新のたびに同じ操作が要ること、gh CLI が要ることを書く）。`xattr` や `postflight` は入れない。確認: 仮の値で埋めたファイルを一時的な tap（`brew tap-new --no-git` などで作った手元の tap）に置き、`brew style` が通る
- [ ] 2.2 `scripts/release.sh X.Y.Z` の確認の部分を作る: 引数の形式、作業ツリーが clean、ブランチが `main`、`git fetch origin` の後に `HEAD == origin/main`、タグ `vX.Y.Z` がローカルにもリモートにも無い、`xcodebuild -showBuildSettings -configuration Release` の `MARKETING_VERSION` が引数と一致、`CURRENT_PROJECT_VERSION` が正の整数。確認: (a) `abc` や `1.2` を渡すと形式のエラー、(b) 未コミットのファイルがあると止まり `xcodebuild` を実行しない、(c) `main` 以外のブランチで止まる、(d) `0.2.0` を渡すと不一致で止まる、(e) 一時的にローカルのタグ `v0.1.0` を作ると止まる（確認後に消す）
- [ ] 2.3 `scripts/release.sh` に、push 前の確認（`xcodebuild test`、`bash scripts/lint.sh`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルド、`bash scripts/tests/verify-app-test.sh`）、`bash scripts/build.sh Release`、`verify_app`、一時ディレクトリでの zip（`ditto -c -k --sequesterRsrc --keepParent`）・`.sha256`・`mewbell.rb` の作成、展開した zip の `verify_app`、すべて通った後の `build/release/X.Y.Z/` への移動、公開のコマンド（タグの作成と push、`gh release create … --draft`、tap への Cask のコピーとコミット）の表示を足す。タグの作成・push とリリースの作成は実行しない。確認: `main` で `bash scripts/release.sh 0.1.0` を実行し、(a) `build/release/0.1.0/` に 3 つのファイルができる、(b) `unzip -l` の中身が `Mewbell.app/` の下だけ、(c) `shasum -a 256 -c` が通る、(d) `mewbell.rb` の `version` と `sha256` が合い、`brew style` が通る、(e) `git tag` と `git ls-remote --tags origin` にタグが増えていない、(f) 途中で失敗させる（Release ビルドの後に `verify_app` が失敗するよう一時的に細工する）と `build/release/0.1.0/` が作られない

## 3. ドキュメント

- [ ] 3.1 README に「インストール」の節を足す: Homebrew（`brew tap yshrsmz/tap`、`brew trust --tap yshrsmz/tap`、`brew install --cask yshrsmz/tap/mewbell`）、Releases の zip から `/Applications` に入れる方法、初回起動で Gatekeeper に止められたときのシステム設定の「プライバシーとセキュリティ」の「このまま開く」の手順、更新（`brew upgrade --cask mewbell`、更新のたびに同じ操作が要ること）、アンインストール（`brew uninstall --cask` と `--zap`）。冒頭の「開発中」の注記を M5 に合わせる。確認: 差分を読み、`spctl --master-disable` や quarantine を消す手順を勧めていない。`brew trust` のコマンドを手元の Homebrew 7 の `brew help trust` と照らし合わせる
- [ ] 3.2 README の「開発」に「リリース」の節を足す: バージョンの上げ方（2 つのターゲットの `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION`、PR でマージしてから実行）、`bash scripts/release.sh X.Y.Z`、表示されたコマンドでの公開、draft のリリースの添付ファイルの SHA-256 を手元と比べてから公開すること、`.claude/rules/security.md` を変えたら `verify-app.sh` を見直すこと。確認: 書いた手順のとおりに 2.3 を実行できた
- [ ] 3.3 CLAUDE.md の「署名・notarize は M5 まで扱わない」を今回の方針（ad-hoc 署名、notarize しない、自分の tap の Cask、自動更新なし、リリースは `scripts/release.sh` を手元で実行）に直し、ビルドとテストの節に `release.sh` を足す。SETUP.md の M5 の行から Sparkle を外す。確認: 差分を読み、`openspec/config.yaml` の context と食い違いが無い

## 4. 公開と実機での確認

- [x] 4.1 `yshrsmz/homebrew-tap` を用意し、`Casks/` と短い README（使い方、`brew trust`、Gatekeeper の「このまま開く」、quarantine を消さないこと）を置く。確認: `brew tap yshrsmz/tap` が通る。結果: リポジトリはユーザーが作った。CI は入れていない。Cask はまだ置いていない（4.3 で置く）
- [ ] 4.2 ad-hoc 署名の更新の影響を確かめる: `CURRENT_PROJECT_VERSION` だけを変えた 2 つの Release ビルドを作り、`codesign -dr -` の designated requirement が違うことを見たうえで、1 つ目を `/Applications` に入れて通知を許可しログイン項目に登録し、2 つ目で置き換えて起動する。確認: 通知の許可とログイン項目の登録が残るかを記録し、外れるなら README と Cask の `caveats` に設定し直す手順を書く（残るなら書かない）。handover の「ad-hoc 署名のローカルビルドで、再ビルドの後も通知の許可が残るか」もこれで閉じる
- [ ] 4.3 この change を main にマージした後、ユーザーに確かめてから `bash scripts/release.sh 0.1.0` を実行し、表示されたコマンドでタグ `v0.1.0` の push、draft のリリース、添付ファイルの SHA-256 の照合、公開、tap への `Casks/mewbell.rb` の push を行う。確認: `curl -sL` で取った zip の SHA-256 が Cask と一致する
- [ ] 4.4 別のユーザーアカウントか、`/Applications/Mewbell.app` を消した状態で `brew install --cask yshrsmz/tap/mewbell` を実行する。確認: (a) `caveats` が表示される、(b) 初回起動で Gatekeeper に止められ、システム設定の「このまま開く」で起動できる、(c) メニューバーに猫が出て通知を取得できる、(d) `brew uninstall --cask --zap mewbell` で `/Applications/Mewbell.app` と `~/Library/Preferences/com.codingfeline.mewbell.plist` が消える

## 5. 最終確認

- [ ] 5.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [ ] 5.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test`、`bash scripts/lint.sh`、`bash scripts/tests/verify-app-test.sh`、`npx openspec validate --all --strict` が成功する
- [ ] 5.3 手元で起動して確認した: `build/release/0.1.0/Mewbell-0.1.0.zip` を展開した `Mewbell.app` を `/Applications` に置いて起動し、メニューバーの猫、通知の取得、設定の Diagnostics にバージョン `0.1.0` が出ることを確かめる

## 6. 別コンテキストでのレビュー

- [ ] 6.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/tests/verify-app-test.sh` と `bash scripts/lint.sh` が引き続き通る
- [ ] 6.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 6.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認（Hardened Runtime、entitlement、ATS、Cask が Gatekeeper を迂回しないこと）を PR 本文に書いた
