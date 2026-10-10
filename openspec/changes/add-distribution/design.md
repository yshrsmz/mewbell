# Design

## Context

- 今のビルドは `scripts/build.sh` で `build/<Configuration>/Mewbell.app` を作るだけ。署名は `CODE_SIGN_IDENTITY: "-"`（ad-hoc）、`CODE_SIGN_STYLE: Manual`。Hardened Runtime は有効で、Release では `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` にして `get-task-allow` を入れていない。entitlements のファイルは無い
- `ONLY_ACTIVE_ARCH` は Debug だけ `YES`。Release は既定のアーキテクチャ（`arm64 x86_64`）で universal になる見込み（実装で `lipo -archs` で確かめる）
- バージョンは `MARKETING_VERSION: 0.1.0`、`CURRENT_PROJECT_VERSION: 1` を Mewbell と MewbellTests の 2 つのターゲットに書いている。タグとリリースはまだ無い。`project.xcproj` は末尾にカンマがあるので厳密な JSON ではないが、`//` のコメント行を入れても `xcodebuild` は読める（手元で確かめた）
- CI は ubuntu で lint と `openspec validate` だけ。`main` にブランチ保護は無い。マージは squash で、PR のタイトル（`feat: … (#11)`）がそのままコミットになる。リポジトリの Actions の既定の権限は `read`、Actions による PR の作成は無効
- GitHub のホストランナーには Xcode 27 の public preview のイメージ（ラベル `xcode-27`、arm64）があり、2026-10-06 のイメージは macOS 27.0.1 に Xcode 27.2 beta（`27B5019j` と `27B5028f`）を入れている。手元の Xcode は `27.2 (27B5028f)`。preview なので不安定さとキューの待ちがあり、beta の更新でイメージが入れ替わる
- 手元の Homebrew は 7.0.9。サードパーティの tap を読むには `brew trust` が要る。macOS 26 の symbol は `:tahoe`
- `yshrsmz/homebrew-tap` は README と空の `Casks/` だけを置いた状態

## Goals / Non-Goals

**Goals:**

- `main` にマージするだけで、Release PR → タグ → ビルドと検査 → 添付 → 公開 → tap の Cask の更新までを自動で行い、途中で失敗したら外に何も出さない（draft のまま残す）
- 署名と entitlement の約束（security.md の「アプリとビルドの設定」）を、配布物を作るたびに機械的に確かめる
- CI に渡す資格情報を、短命で範囲を絞ったものだけにする

**Non-Goals:**

- Developer ID の署名、notarize、staple（ad-hoc のまま）
- 自動更新（Sparkle、アプリ内の新版チェック）
- 公式の homebrew-cask への登録、dmg の作成
- アプリのコードの変更（実行中の振る舞いは変えない）
- Release PR で lint の CI を走らせること（App のトークンで作った PR では走る見込みだが、要件にはしない）

## Decisions

### D1. release-please の設定

`release-please-config.json` と `.release-please-manifest.json`（`{".": "0.1.0"}`）を置く。

```json
{
  "packages": {
    ".": {
      "release-type": "simple",
      "include-component-in-tag": false,
      "bump-minor-pre-major": true,
      "draft": true,
      "force-tag-creation": true,
      "extra-files": [
        { "type": "generic", "path": "Mewbell.xcodeproj/project.xcproj" }
      ]
    }
  }
}
```

- `simple` は `CHANGELOG.md` と `version.txt` を更新する。`version.txt` は release-please の都合で作られるだけで、正本は `project.xcproj` とする（2 つは release-please が同時に書き換えるので食い違わない）
- `draft: true` だと GitHub は公開までタグを作らず、release-please が前のリリースを見つけられなくなるので、`force-tag-creation: true` でタグをすぐに作る
- `bump-minor-pre-major` で、1.0.0 より前の破壊的変更は minor を上げる。`feat:` は minor、`fix:` は patch
- 最初のリリースは今の `0.1.0` にする。マニフェストに `0.1.0` を書くと次の Release PR は `0.1.1` か `0.2.0` になるので、最初の Release PR は `Release-As: 0.1.0` を含む空のコミットで `0.1.0` にする（実装で確かめる）

代替案: 手元のスクリプトでタグを切る（最初の計画）。ユーザーが自動化を選んだため採らない。semantic-release は Node の依存とプラグインが多く、Release PR の形で変更を確かめられないため採らない。

### D2. バージョンを 1 か所にまとめる

`MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を 2 つのターゲットの設定から消し、プロジェクトの設定に 1 回だけ書く。release-please の generic updater の印をコメント行で付ける。

```
    // x-release-please-start-version
    "CURRENT_PROJECT_VERSION": "0.1.0",
    "MARKETING_VERSION": "0.1.0",
    // x-release-please-end
```

`CURRENT_PROJECT_VERSION`（`CFBundleVersion`）も同じ `X.Y.Z` にする。release-please は整数のビルド番号を上げられず、`CFBundleVersion` は 3 つまでの整数を `.` でつないだ形を許すため。Xcode の IDE で `project.xcproj` を保存し直すとコメントが消えるおそれがあるので、検査（D4）で `CFBundleShortVersionString` がタグと一致することを確かめ、印が消えたら最初のリリースで気づけるようにする。

代替案: xcconfig にバージョンを移す。JSON 形式の `project.xcproj` から xcconfig を参照する書き方を確かめられていないので採らない。`version.txt` を正本にして `xcodebuild` に引数で渡す。Xcode の IDE と `build.sh` のビルドでバージョンが変わるので採らない。

### D3. リリースのワークフロー（mewbell）

`.github/workflows/release.yml`。`on: push: branches: [main]`、ワークフローの既定は `permissions: contents: read`、`concurrency: { group: release, cancel-in-progress: false }`。

1. ジョブ `release-please`（`ubuntu-24.04`、`environment: release`）
   - `actions/create-github-app-token` で mewbell 用 App のトークンを発行する（`repositories: mewbell`、`permission-contents: write`、`permission-pull-requests: write`）
   - `googleapis/release-please-action` をそのトークンで実行し、`release_created`、`tag_name`、`version` を出力する
2. ジョブ `build`（`runs-on: xcode-27`、`needs: release-please`、`if: needs.release-please.outputs.release_created == 'true'`、`environment: release`、`timeout-minutes: 60`、`permissions: contents: write`）
   - タグを checkout する（`persist-credentials: false`）
   - `DEVELOPER_DIR=/Applications/Xcode_27.2_beta_2.app/Contents/Developer` にし、`xcodebuild -version` のビルド番号が `27B5028f` でなければ失敗する。ビルド番号はワークフローの先頭に `XCODE_BUILD` として置き、Xcode を上げるときに一緒に変える
   - `xcodebuild test`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルド、`bash scripts/tests/verify-app-test.sh`
   - `bash scripts/package-release.sh "$VERSION"`（D4）
   - `gh release upload "$TAG" … --clobber` で zip と `.sha256` を draft に添付し、`gh release edit "$TAG" --draft=false` で公開する。`GH_TOKEN` はジョブの `GITHUB_TOKEN`
   - mewbell 用 App のトークンを `owner: yshrsmz`、`repositories: homebrew-tap`、`permission-contents: write` だけで発行し、`gh api repos/yshrsmz/homebrew-tap/dispatches -f event_type=mewbell-released -F 'client_payload[version]=…'` を送る
3. lint は今の `ci.yml` のまま（Release PR にも走る）

`actions/checkout`、`actions/create-github-app-token`、`googleapis/release-please-action` はコミット SHA で固定し、公開から 7 日以上経った版を選ぶ。`${{ }}` の値はシェルに直接埋め込まず、`env:` を通して渡す。

失敗したとき: タグと draft の Release が残る。原因を直せる場合（ランナーの一時的な失敗など）は `gh run rerun --failed` でやり直す。コードを直す必要がある場合は、draft の Release とタグを消してから、修正の PR をマージし直す（release-please は次の Release PR を作る）。この手順を README に書く。

代替案: ビルドを手元で行う（最初の計画）。ユーザーがリリースに限って macOS ランナーを認めたため採らない。macOS のジョブだけで release-please も動かす。macOS ランナーは高く preview でもあるので、Release を作るときだけ動かす。

### D4. 配布物を作る処理は CI と手元で共通にする

- `scripts/lib/verify-app.sh` の `verify_app <path-to-.app> <version>`: `codesign --verify --deep --strict`、`codesign -dv` の `flags=` に `runtime`、`codesign -d --entitlements - --xml` に禁止の entitlement が無いこと、Info.plist（`plutil -extract`）に `NSAppTransportSecurity` の緩める設定が無いこと、`CFBundleIdentifier`、`CFBundleShortVersionString` と `CFBundleVersion` が `<version>` と一致すること、`lipo -archs` に `arm64` と `x86_64` があることを確かめ、満たさない項目の名前を表示して 0 以外で返す
- `scripts/package-release.sh X.Y.Z`: 形式の確認 → `bash scripts/build.sh Release` → `verify_app` → 一時ディレクトリで `ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent` で zip（拡張属性を入れない）、`zipinfo -1` で中身が `Mewbell.app/` の下だけであることを確かめる、`shasum -a 256` で `.sha256` → 展開した zip を `verify_app` → すべて通ったら `build/dist/X.Y.Z/` に移す（`build/release` は大文字と小文字を区別しない APFS で `build/Release` と重なるので使わない）。添付・公開・dispatch はしない（それはワークフローが行う）。手元では、リリースの前の試しや、検査が落ちたときの調べに使う
- `scripts/tests/verify-app-test.sh`: `clang` で小さな universal の実行ファイルを作って偽の `.app` を組み、正常なものが通り、`get-task-allow` 付き・`runtime` 無し・`NSAllowsArbitraryLoads` 付き・`arm64` だけ・`CFBundleIdentifier` 違い・バージョン違い・署名後の改変がそれぞれ失敗することを確かめる。ubuntu の CI には `codesign` が無いので、リリースのワークフローと手元で実行する

### D5. Cask の更新（homebrew-tap）

homebrew-tap は OpenSpec の外なので、ここで形を決め、tasks で作る。

- `.github/templates/mewbell.rb.template`（`@VERSION@` と `@SHA256@`）。中身は spec の「Homebrew Cask の中身」のとおり。mewbell の `packaging/homebrew/mewbell.rb.template` を正本にし、変えたときは tap にもコピーする（tap 側で生成に使うのは tap の雛形）
- `.github/workflows/update-cask.yml`: `on: repository_dispatch: types: [mewbell-released]`、既定の `permissions: contents: read`、`environment: release`
  - `env: VERSION: ${{ github.event.client_payload.version }}` で受け、`[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]` でなければ失敗する
  - `curl -fsSL --proto '=https'` で `https://github.com/yshrsmz/mewbell/releases/download/v$VERSION/Mewbell-$VERSION.zip` と `.sha256` を取り、`shasum -a 256` の値と `.sha256` の値が一致することを確かめる
  - 雛形から `Casks/mewbell.rb` を作り、tap 用 App のトークン（`repositories: homebrew-tap`、`permission-contents: write`、`permission-pull-requests: write`）でブランチ `mewbell-$VERSION` を push して PR を作り、`gh pr merge --auto --squash` を指定する
- `.github/workflows/ci.yml`: `pull_request` で `brew style Casks` と `brew audit --cask --strict`（`--online` は付けない）を `macos-latest` で動かす。`brew audit --cask` が Linux で動くかを確かめられなかったため、確実に動く macOS にする（リリースのためのワークフローなので macOS ランナーの例外に入り、Cask の PR のときだけ動く）
- ruleset: `main` へのマージに `ci` のチェックの成功を必須にする。リポジトリの設定で auto-merge を有効にする。App のトークンで作った PR は CI が走るので、auto-merge が働く

代替案: mewbell のワークフローから tap に直接 push する。tap に CI を通さない変更が入り、mewbell 側に tap の PR の権限まで持たせることになるので採らない。

### D6. GitHub App と Environment

| App | インストール先 | 権限 | 秘密鍵の置き場所 |
|---|---|---|---|
| mewbell 用（例: `mewbell-release`） | mewbell、homebrew-tap | Contents: Read and write、Pull requests: Read and write、Metadata: Read | mewbell の Environment `release` |
| tap 用（例: `yshrsmz-tap-bot`） | homebrew-tap | Contents: Read and write、Pull requests: Read and write、Metadata: Read | homebrew-tap の Environment `release` |

- App の Client ID は Environment の変数（`vars.RELEASE_APP_CLIENT_ID`）、秘密鍵はシークレット（`secrets.RELEASE_APP_PRIVATE_KEY`）にする
- Environment `release` は「Deployment branches and tags」を `main` だけにする。tap の `repository_dispatch` は既定のブランチ（`main`）で動くので、この制限を通る
- mewbell 用 App は homebrew-tap にもインストールするが、mewbell のワークフローが tap 向けに発行するトークンは `permission-contents: write` だけに絞る（dispatch には Contents の書き込みが要る）
- App は Webhook を無効にし、「Only on this account」でインストールを自分だけにする

代替案: PAT（有効期限と範囲の管理が人に依存し、漏れたときの影響が大きい）。1 つの App を両方に置く（鍵が両方のリポジトリに置かれ、どちらから漏れても両方に書ける）。どちらもユーザーと決めて採らなかった。

### D7. 開発の規則の変更

- CLAUDE.md: 「CI は ubuntu だけ」を、「lint と検証は ubuntu。リリースのワークフロー（mewbell の `release.yml` と homebrew-tap のワークフロー）に限り macOS ランナーを使う」に改める。`xcodebuild` のテストとビルドを push 前に手元で通す約束は変えない。「署名・notarize は M5 まで扱わない」を今回の方針に直す
- `.claude/rules/security.md` の「依存とサプライチェーン」: 「CI にシークレットを渡さない」を、「CI に渡してよいシークレットは、リリースのワークフローで使う GitHub App の秘密鍵だけ。`main` に限定した Environment に置き、PAT は使わない」に改める。「`permissions: contents: read` を明示する」に、「書き込みが要るジョブにだけ、要る権限を与える。App のトークンは対象のリポジトリと権限を絞って発行する」を足す。`pull_request_target` を使わない約束は変えない

## Risks / Trade-offs

- [Xcode 27 のイメージは preview で、beta の更新で Xcode が入れ替わる] → ビルド番号が違えば失敗させ、draft のまま残す。イメージの更新に合わせて `XCODE_BUILD` とパスを上げる PR を出す。手元の Xcode と同じビルド番号にそろえる
- [macOS ランナーのキューの待ちや失敗] → `timeout-minutes` を付け、`gh run rerun --failed` でやり直す
- [App の秘密鍵が漏れる] → Environment で `main` に限定し、App の権限を Contents と Pull requests だけにする。漏れたら App の鍵を失効させ作り直す手順を README に書く
- [`project.xcproj` のコメントの印が Xcode の保存で消える] → 検査でバージョンとタグの一致を確かめるので、消えたら最初のリリースで失敗して気づく。消えたときは印を付け直す
- [初回起動と更新のたびに Gatekeeper に止められる] → `caveats` と README で手順を案内する。不便が大きければ、後で Developer ID と notarize を別の change で入れる
- [ad-hoc 署名のため、更新の後に通知の許可やログイン項目が外れるかもしれない] → 実機で確かめ、外れるなら設定し直す手順を案内する
- [Homebrew の仕様の変化が速い] → Cask は最小限の stanza にし、tap の CI で毎回 `brew style` と `brew audit` を通す
- [最初の本番のリリースが結合テストを兼ねる] → 最初に `xcode-27` のラベルと Xcode のパスを確かめる小さな試しを行い、失敗しても draft が残るだけになるようにする

## セキュリティ

- トークンの流れ（アプリ）: この change はアプリのコードを変えないため、gh のトークンの取得・保持・送信・破棄は変わらない。配布物にトークンを含むファイルは入らない（zip の中身は `Mewbell.app` だけ）
- トークンの流れ（CI）: App の秘密鍵は Environment `release` のシークレットにだけ置き、`create-github-app-token` がジョブの中で 1 時間で切れるインストールトークンに換える。トークンは Action の出力からそのジョブの `env` に渡すだけで、ログには出さない（Actions がマスクする）。ジョブの終わりに `create-github-app-token` が失効させる
- `.claude/rules/security.md` への対応:
  - アプリのトークン・gh サブプロセス・ネットワーク・URL を開く処理: 該当しない（アプリのコードに触れない）。spec のルールにある API のエンドポイントとステータスコードも、この capability はアプリから API を使わないので該当しない
  - アプリとビルドの設定: Release の Hardened Runtime、緩める entitlement と `get-task-allow` が無いこと、ATS の例外が無いことを `verify_app` で配布物ごとに確かめ、偽の .app のテストで検査そのものを確かめる
  - 依存とサプライチェーン: アプリの依存は増やさない。Action はコミット SHA で固定する。CI のシークレットと権限の約束は D7 のとおり改め、そのとおりに作る。`pull_request_target` は使わず、リリースのワークフローは `main` への push と（tap は）`repository_dispatch` だけで動く
  - tap: `repository_dispatch` の payload は検証してから使い、URL と SHA-256 は自分で決める。Cask は `https` の GitHub Releases だけを指し、`sha256` を必ず入れる
- Gatekeeper: quarantine を消す処理を Cask に入れず、Gatekeeper をシステム全体で無効にする手順も案内しない

## Migration Plan

1. ユーザーが 2 つの GitHub App を作り、インストールし、両リポジトリに Environment `release` と変数・シークレットを置く。homebrew-tap で auto-merge を有効にし ruleset を作る
2. この change をマージする（`feat:` の PR）。release-please が最初の Release PR を作る
3. Release PR を `0.1.0` にしてマージし、ビルド・添付・公開・tap の PR とマージまでを見届ける
4. 別の場所に `brew install --cask` で入れて、Gatekeeper の手順と起動を確かめる

戻すとき: `release.yml` を消し、残った draft とタグを消す。tap の Cask を消す。アプリのコードは変えていないので、手元のビルドには影響しない。

## Open Questions

- `Release-As: 0.1.0` で最初の Release PR を `0.1.0` にできるか（できなければマニフェストを `0.0.0` から始める）。D1 の形は変わらない
