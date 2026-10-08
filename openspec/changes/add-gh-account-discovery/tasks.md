# Tasks

## 1. 依存とドキュメント

- [ ] 1.1 Yams を `exactVersion: 6.2.2` で `Mewbell` ターゲットに追加する（design.md D4。`xcrun xcodeproj` で足せなければ Xcode の Add Package Dependencies で「Exact Version」を選ぶ）。`Package.resolved` が `Mewbell.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` にでき、`git status` に出ることを確かめる。確認: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -resolvePackageDependencies` が成功し、`import Yams` を書いたファイルで `xcodebuild build` が通る（確かめたら仮の import は消す）
- [ ] 1.2 `SETUP.md` の M4 の行に「gh のパスの上書き（設定画面と UserDefaults。M1 の検出処理は上書きパスを受け取れる）」を書き足し、README の「開発中」の説明を M1 の状態（gh のアカウントを一覧できる）に更新する。確認: 差分を読んで M4 の要点に上書きが入っている

## 2. サブプロセスとトークン型（GhCLI）

- [ ] 2.1 `ProcessRunning` と `SubprocessRunner` を実装する（design.md D2: 絶対パスと引数配列、標準入力は `/dev/null`、読みながら出力上限を確かめる、タイムアウトで SIGTERM → 1 秒後に SIGKILL、`Mutex` で 1 回だけ resume）。確認: `/bin/echo` の出力と終了コードを受け取る、`/bin/sleep 5` がタイムアウト 0.5 秒で `timedOut` になりプロセスが残らない、`/usr/bin/yes` が出力上限で `outputTooLarge` になる、のテストが通る
- [ ] 2.2 `GhEnvironment` を実装する（design.md D5）。確認: `GH_TOKEN` など 5 つが取り除かれ、`GH_PROMPT_DISABLED=1`・`GH_NO_UPDATE_NOTIFIER=1`・`NO_COLOR=1` が入り、`HOME`・`GH_CONFIG_DIR` が残るテストと、作った環境で `/usr/bin/env` を `SubprocessRunner` で実行して出力に `GH_TOKEN=` が無いテストが通る
- [ ] 2.3 `AccessToken` と `Redaction` を実装する（design.md D6）。確認: `"\(token)"`・`String(reflecting:)`・`dump` の結果に値が含まれないテスト、`gh[opsu]_` と `github_pat_` の文字列が `<redacted>` になり、それ以外の文字列は変わらないテストが通る（テスト中のトークン風文字列は分割して書く）

## 3. gh の検出とバージョン（GhCLI）

- [ ] 3.1 候補パスの検証を実装する（design.md D3: 絶対パス、`realpath`、通常ファイル、`X_OK`、group/world-writable の拒否、実パスを返す）。確認: 一時ディレクトリで、通常の実行ファイルは通り、`chmod 777`・`chmod 775`・実行ビットなし・ディレクトリ・相対パス・存在しないパスは拒否され、シンボリックリンクは実体のパスが返るテストが通る
- [ ] 3.2 `GhLocator` を実装する（上書きパス → 既定の候補 → ログインシェル。`/etc/shells` の確認、出力の最後の空でない行、起動ごとに 1 回だけ）。確認: 偽のランナーで、既定の候補にあればシェルを起動しない、rc の出力が混ざっても最後の行を使う、2 回目の検索ではシェルを起動しない、`/etc/shells` に無いシェルは使わない、上書きパスがあるとそれだけを確かめる、のテストが通る
- [ ] 3.3 `GhVersion` の解析と比較、`GhClient.version()` を実装する。確認: `gh version 2.39.2 (…)` は 2.40.0 未満、`2.40.0` と `2.102.0` は対応、読めない出力は「古い」扱いになるテストと、`--version` に渡る引数と環境が正しいことを偽のランナーで確かめるテストが通る

## 4. hosts.yml の読み取り（GhCLI）

- [ ] 4.1 `GhConfigDirectory` を実装する（`GH_CONFIG_DIR` → `XDG_CONFIG_HOME/gh` → `~/.config/gh`）。確認: 3 通りの環境の辞書で期待するパスになるテストが通る
- [ ] 4.2 ホスト名とユーザー名の検証を実装する（gh-cli spec の「ホスト名とユーザー名の検証」）。確認: `github.com`・`acme.ghe.com`・`alice`・`alice_acme` は通り、`-x`・`--help`・`evil host/path`・空文字・長すぎる値・`a..b` は拒否されるテストが通る
- [ ] 4.3 `HostsFile` を Yams の `compose` で実装する（design.md D4。1 MiB 上限、`users` のキーと `user` だけを取り出す）。確認: 複数アカウント形式、以前の形式、`users.<login>.oauth_token: test-token` を含む形式、不正なエントリが混ざった形式、空ファイル、壊れた YAML、のフィクスチャのテストが通り、`oauth_token` を含むフィクスチャの結果を `String(reflecting:)` しても `test-token` が出ない

## 5. トークン取得とアカウント（GhCLI / Accounts）

- [ ] 5.1 `GhClient.token(host:user:)` を実装する（引数 `["auth", "token", "--hostname", host, "--user", user]`、タイムアウト 10 秒、出力上限 4 KiB、空・空白入り・非 0 終了は失敗、標準エラー出力は伏せ字化して `Logger` へ）。確認: 偽のランナーで引数と環境、成功・非 0 終了・タイムアウト・出力超過・改行を含む出力のテストが通る
- [ ] 5.2 `HostKind`、`AccountID`、`Account` と並び順を実装する（accounts spec）。確認: 3 種類のホストの判定、ホスト名の小文字化、`github.com` 先頭・アクティブ先頭の並び順のテストが通る
- [ ] 5.3 `CredentialStore` を実装する（設定、取得、指定したアカウント以外の破棄、全破棄）。確認: 消えたアカウントのトークンだけが捨てられるテストと、全破棄のテストが通る
- [ ] 5.4 `AccountDiscovery` を実装する（design.md D7 の 1〜5。状態を `AsyncStream` で流す）。確認: 偽のランナーと一時ディレクトリの `hosts.yml` で、gh が無い・古い・`hosts.yml` が無い・壊れている・アカウントあり、の各状態になるテスト、2 回目の読み込みで「使える」アカウントに `gh auth token` を呼ばないテスト、失敗したアカウントは取り直すテスト、消えたアカウントのトークンが捨てられるテスト、状態が「アカウントあり」以外になると全トークンが捨てられるテストが通る
- [ ] 5.5 `AccountStore`（`@MainActor @Observable`）を実装する（`reload()` の重複抑止、テストとプレビューでは自動で始めない、`willTerminateNotification` で全破棄）。確認: `reload()` を続けて 2 回呼んでも読み込みは 1 回だけ走るテストと、`AccountStore` の公開する状態に `AccessToken` が含まれないこと（型で保証されていること）をコードで確かめる

## 6. 画面（UI）

- [ ] 6.1 `MenuBarExtra(.window)` の `onAppear` がポップオーバーを開くたびに呼ばれるかを手で確かめ、呼ばれなければ `NSWindow.didBecomeKeyNotification` に切り替える（design.md Risks）。確認: ログ（`Logger`）で開くたびに読み直しが走ることを Console.app で見る
- [ ] 6.2 `CommandRow`（等幅のコマンドとコピーボタン）と `GuidanceView`（確認中、gh が見つからない、gh が古い、`hosts.yml` を読めない、未ログイン）を実装する。`https://cli.github.com/` は定数から開く。確認: 各状態の SwiftUI プレビューを Xcode で表示し、コピーボタンで `pbpaste` にコマンドが入ることを手で確かめる
- [ ] 6.3 `AccountListView`（ホストごとの見出しと種別、ユーザー名、アクティブの印、状態、トークンを取れない行の `gh auth login --hostname <host>` とコピーボタン）を実装する。確認: 2 ホスト・アクティブあり・取得中・取れない行を含むプレビューを表示して spec の表示内容と照らす
- [ ] 6.4 `MenuBarContentView` を design.md D8 の並びにし、再読み込みボタン（読み込み中は無効）をつなぐ。`MewbellApp` で `AccountStore` を作って渡す。確認: `bash scripts/run.sh` で起動し、自分の gh アカウントが一覧に出て「使える」になる。「Mewbell」の表示、Quit、⌘Q が引き続き動く

## 7. 最終確認

- [ ] 7.1 ビルドが通る: `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する。Release の `.app` で `codesign -d --entitlements -` に緩める entitlement が無いことも確かめる
- [ ] 7.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 7.3 手元で起動して確認した: (a) gh ありでアカウント一覧が出る、(b) `GH_CONFIG_DIR` を空の一時ディレクトリにして `open --env` で起動すると「未ログイン」の案内が出る、(c) `GH_CONFIG_DIR` に壊れた `hosts.yml` を置くと「読めない」の案内が出る、(d) gh が無い・古い状態は手元の gh を消さずに 5.4 のテストで確かめたものとし、PR 本文にそう書く、(e) `GH_TOKEN=dummy` を付けて起動しても一覧が gh のアカウントどおりになる、(f) ポップオーバーを開き直しても `gh auth token` が再実行されない（`sudo fs_usage` ではなく `Logger` のログで確かめる）
- [ ] 7.4 トークンが残っていないことを確かめた: 起動して一覧が「使える」になった後、`defaults read com.codingfeline.mewbell`、`~/Library/Application Support/com.codingfeline.mewbell/`、`log show --predicate 'subsystem == "com.codingfeline.mewbell"' --last 10m --info --debug` に `gh auth token` の出力が含まれないことを確かめる（トークンの値を画面に出さないよう、`grep -c -F "$(gh auth token)"` のように件数だけを見る）

## 8. 別コンテキストでのレビュー

- [ ] 8.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 8.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 8.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認（security.md のどの項目を満たしたか）を PR 本文に書いた
