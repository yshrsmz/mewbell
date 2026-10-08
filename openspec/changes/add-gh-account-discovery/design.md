# Design

## Context

M0 の時点で、アプリは `Mewbell/App/` の 3 ファイル（`MewbellApp`、`MenuBarContentView`、`SingleInstance`）だけでできている（動機は proposal.md の Why を参照。満たすべき振る舞いは `specs/gh-cli`、`specs/accounts`、`specs/ui`）。

設計に効く事実:

- `project.xcproj` の `Mewbell/` と `MewbellTests/` は `"kind": "folder"`（同期フォルダー）なので、`Mewbell/GhCLI/` などにファイルを置けばターゲットに入る。プロジェクトを編集するのは SwiftPM の依存を足すときだけ
- `SWIFT_DEFAULT_ACTOR_ISOLATION` は指定なし（`nonisolated` 既定）、strict concurrency は `complete`、`SWIFT_APPROACHABLE_CONCURRENCY=YES`
- 手元の gh は 2.102.0。`hosts.yml` は次の形（gh 2.40.0 以降の複数アカウント形式）。トークンは Keychain にあり、`hosts.yml` には入っていない。ただし Keychain が使えない環境では gh が `users.<login>.oauth_token` に平文で書くことがあり、2.40.0 より前の形式ではホスト直下に `oauth_token` と `user` が並ぶ

  ```yaml
  github.com:
      git_protocol: https
      users:
          <login>:
      user: <login>
  ```

- `gh auth token --user` は gh 2.40.0 で入った（`pkg/cmd/auth/token/token.go` の v2.39.2 には `--user` が無く、v2.40.0 にはある）
- Finder や `open` から起動したアプリには、シェルの rc ファイルで設定した環境変数（`GH_CONFIG_DIR` など）が渡らない

## Goals / Non-Goals

**Goals:**

- gh の起動・`hosts.yml` の読み取り・トークンの保持を、M2 のポーリングからそのまま使える形にする（アカウントの ID とトークンの受け取り口を M2 で作り直さない）
- gh サブプロセスとファイルシステムを差し替えて、セキュリティ上の約束（環境変数の除去、パスの検証、出力上限、伏せ字）をユニットテストで確かめられるようにする
- M4 で gh のパスの上書きを足すとき、設定画面と UserDefaults の追加だけで済むようにする

**Non-Goals:**

- `hosts.yml` の変更監視（FSEvents など）。読み直しはポップオーバーを開いたときと再読み込みボタンで足りる
- API ベース URL の導出と、トークンを付けたリクエスト（M2）
- アプリのログイン項目化・アカウントの ON/OFF（M4）

## Decisions

### D1. モジュールと型の分担

| 置き場所 | 型 | 役割 |
| --- | --- | --- |
| `GhCLI/` | `ProcessRunning`（protocol）と `SubprocessRunner` | 実行ファイルの絶対パスと引数配列でプロセスを起動し、タイムアウトと出力上限を守って結果を返す |
| `GhCLI/` | `GhEnvironment` | 子プロセスに渡す環境変数を作る（除去と追加。D5） |
| `GhCLI/` | `GhLocator`（actor） | 候補パスの検証、ログインシェルでの検索を 1 回に制限する状態を持つ（D3） |
| `GhCLI/` | `GhVersion` | `gh --version` の出力の解析と比較 |
| `GhCLI/` | `GhConfigDirectory`、`HostsFile` | 設定ディレクトリの決定と `hosts.yml` の解析（D4） |
| `GhCLI/` | `AccessToken`、`Redaction` | 伏せ字になるトークン型と、ログ用のトークンらしい文字列の伏せ字化（D6） |
| `GhCLI/` | `GhClient` | 上の部品を使って `gh --version` と `gh auth token` を実行する |
| `Accounts/` | `HostKind`、`AccountID`、`Account` | アカウントの値型（`AccountID` は `<host>/<user>`、ホストは小文字） |
| `Accounts/` | `CredentialStore`（actor） | `AccountID` → `AccessToken` の辞書。トークンを持つのはここだけ |
| `Accounts/` | `AccountDiscovery`（actor、`AccountDiscovering` に準拠） | 検出 → バージョン確認 → `hosts.yml` → トークン取得の流れと、前回の結果との差分（D7） |
| `Accounts/` | `AccountStore`（`@MainActor @Observable`） | UI に見せる状態（全体の状態とアカウントの行）と、読み直しの起動・重複の抑止 |
| `UI/` | `AccountListView`、`GuidanceView`、`CommandRow` | 一覧、案内、コマンドとコピーボタンの行 |

`AccountStore` が UI に渡すのは `Account` と状態（取得中 / 使える / トークンを取れない）だけで、`AccessToken` は渡さない。M2 のポーラーは `CredentialStore` から `AccountID` でトークンを受け取る。

### D2. 並行性の境界

- `AccountStore` と View は `@MainActor`。`reload()` は `Task` を 1 つだけ持ち、走っている間の再読み込み要求は無視する（ボタンは無効にする。ポップオーバーを開いたときの要求も同じ扱い）
- `AccountDiscovery`、`GhLocator`、`CredentialStore` は actor。gh の実行、ファイルの読み取り、YAML の解析はこれらの actor の上で行い、メインスレッドで行わない
- アカウントごとのトークン取得は `withTaskGroup` で並べて走らせる。同じアカウントの取得が同時に 2 つ走らないことは、`reload()` の重複を抑えることで保証する
- `SubprocessRunner` は `Process` を作って `terminationHandler` と `Pipe` の `readabilityHandler` で結果を集め、`withCheckedThrowingContinuation` で async に返す。ハンドラーは任意のスレッドで呼ばれるので、集めている途中のデータと「1 回だけ resume する」フラグは `Mutex`（Synchronization）で守る。`Process` は Sendable でないため、ランナーの外に出さない
- 出力は読みながら上限と比べ、超えた時点で `terminate()` する。`waitUntilExit()` の後に `readToEnd()` する方式はパイプが詰まると止まるので採らない
- タイムアウトは別の `Task` で `Task.sleep` し、時間が来たら `terminate()`（SIGTERM）し、さらに 1 秒たっても終わらなければ `kill(pid, SIGKILL)` する

### D3. gh の検出

- 候補の順: 上書きパス（M1 では常に `nil`。M4 で UserDefaults から渡す）→ `/opt/homebrew/bin/gh` → `/usr/local/bin/gh` → ログインシェル。上書きパスがあるときはそれだけを確かめる
- ログインシェルは `getpwuid(getuid())` の `pw_shell` を使い、`/etc/shells` に載っていることを確かめてから `[shell, "-l", "-c", "command -v gh"]` で起動する（タイムアウト 5 秒、出力上限 64 KiB）。出力の最後の空でない行を候補にする。`GhLocator` は「試したかどうか」を持ち、成否にかかわらず 2 回目は行わない
- 候補の検証: 絶対パスであること → シンボリックリンクを解決（`realpath`）→ `stat` で通常ファイル、`access(X_OK)`、`st_mode & (S_IWGRP | S_IWOTH) == 0`。実行するのは解決後の実パス（検証したファイルと実行するファイルを一致させるため）
- 代替案: `PATH` を自前で探す → アプリの `PATH` はシェルと違うので、結局ログインシェルが要る。採らない

### D4. `hosts.yml` の読み取りと Yams

- 設定ディレクトリは `ProcessInfo.processInfo.environment` の `GH_CONFIG_DIR` → `XDG_CONFIG_HOME/gh` → `~/.config/gh`。gh の子プロセスにも同じ環境を渡すので、Mewbell が読むディレクトリと gh が読むディレクトリは一致する
- Yams の `compose` でノード木を作り、トップレベルのマッピングのキー（ホスト名）、各ホストの `users` マッピングのキー、`user` のスカラーだけを取り出す。`Decodable` の型に流さないのは、`users.<login>` の値（`oauth_token` を含みうるマッピング、または null）の形に左右されないようにするため。取り出した値は D1 の検証（gh-cli spec「ホスト名とユーザー名の検証」）を通してから `HostsFile` に入れる。`HostsFile` の型には `oauth_token` を入れる場所を作らない
- ファイルは 1 MiB を上限に読む。超えたら「読めない」扱いにする
- 代替案: 自前の最小パーサー → gh が書く形式は限られているが、引用符・コメント・フロースタイルの扱いで読み違えるおそれがある。採らない（ユーザーと合意済み）
- 代替案: `gh auth status --json hosts` → YAML が要らずスコープも取れるが、ホストごとに通信して検査するので、オフラインや VPN 外で遅い・失敗する。採らない（ユーザーと合意済み）

Yams の追加:

- `https://github.com/jpsim/Yams` を `exactVersion: 6.2.2` で `Mewbell` ターゲットにだけ追加する（2026-05-26 公開、MIT。ターゲットは C の `CYaml` と Swift の `Yams` だけで、ビルドツールプラグインやマクロは無い）
- `Mewbell.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` をコミットする（`.gitignore` は `xcuserdata/` だけを除外しているので対象外にならない）
- push 前の警告をエラー扱いにしたビルドは、`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` をコマンドラインで渡す方式をやめる。コマンドラインの設定は Yams のターゲットにも掛かり、パッケージに付く `-suppress-warnings` と衝突してビルドが止まるため。代わりにプロジェクトの設定を `SWIFT_TREAT_WARNINGS_AS_ERRORS = $(MEWBELL_WARNINGS_AS_ERRORS)`（既定 `NO`）にし、`MEWBELL_WARNINGS_AS_ERRORS=YES` を渡す。Yams は別プロジェクトなので、この変数を参照しない。CLAUDE.md と README のコマンドも合わせて変える

### D5. 子プロセスの環境

`GhEnvironment.make(from:)` は、アプリの環境をもとに次の変更をした辞書を返す。すべての gh の起動（`--version`、`auth token`）とログインシェルの起動で使う。

- 取り除く: `GH_TOKEN`、`GITHUB_TOKEN`、`GH_ENTERPRISE_TOKEN`、`GITHUB_ENTERPRISE_TOKEN`、`GH_HOST`
- 設定する: `GH_PROMPT_DISABLED=1`、`GH_NO_UPDATE_NOTIFIER=1`、`NO_COLOR=1`
- 残す: `HOME`、`PATH`、`GH_CONFIG_DIR`、`XDG_CONFIG_HOME` などそれ以外（gh が Keychain や設定ディレクトリを見つけるのに要る）

### D6. トークン型と伏せ字

- `AccessToken` は `Sendable` な struct で、値は `fileprivate` ではなく `package`/`internal` の読み取り専用プロパティに持つ（M2 で `Authorization` ヘッダーを作るため）。`description`・`debugDescription` は `AccessToken(<redacted>)` を返し、`CustomReflectable` で `dump` や `Mirror` にも値を出さない。`Codable` には準拠させない（エンコードの経路自体を作らない）
- `gh auth token` の出力は、前後の空白を除いて空でなく空白文字を含まないときだけ `AccessToken` にする。出力上限は 4 KiB
- `Redaction.redactTokens(in:)` は `gh[opsu]_[A-Za-z0-9_]+` と `github_pat_[A-Za-z0-9_]+` を `<redacted>` に置き換える。gh の標準エラー出力（上限 16 KiB）は、これを通してから `Logger` の `.private` で記録する。UI には出さない

### D7. 読み込みの流れと差分

`AccountDiscovery.reload(update:)` は次の順に進み、途中と最後の状態を `update` コールバックで `AccountStore` に渡す（`AccountStore` は `@MainActor` で受け取って反映する）。

1. `GhLocator` で gh を探す。無ければ「gh が見つからない」にして `CredentialStore` を空にする
2. `hosts.yml` を読む。読めなければ「`hosts.yml` を読めない」にして `CredentialStore` を空にする（gh は `hosts.yml` を解釈できないと `gh --version` でも失敗するので、バージョンより先に確かめる。手元の gh 2.102.0 で確認）
3. gh のパスが前回と違う（または初回）なら `gh --version`（タイムアウト 5 秒）を実行し、2.40.0 未満か読めなければ「gh が古い」にする。続いて、アカウントが 0 件なら「未ログイン」にする。どちらも `CredentialStore` を空にする
4. 前回の一覧と比べ、消えたアカウントのトークンを `CredentialStore` から捨てる
5. トークンを持っていないアカウント（新しいもの、前回失敗したもの）について `gh auth token --hostname <host> --user <user>`（タイムアウト 10 秒）を並べて実行し、結果を `CredentialStore` と状態に反映する

起動時の読み込みは `MewbellApp` で `AccountStore` を作ったときに始める。テストのホストや SwiftUI プレビューとして起動されたとき（`SingleInstance` と同じ環境変数の判定）は自動で始めない。ポップオーバーを開いたことは、`MenuBarContentView` の `onAppear` で `AccountStore.reload()` を呼んで知る。アプリの終了時は `AppDelegate.applicationShouldTerminate` で `.terminateLater` を返し、`CredentialStore` を空にしてから終了する（`willTerminateNotification` では actor の処理を待てないため）。起動時の読み込みも `AppDelegate.applicationDidFinishLaunching` から始め、`AccountStore` は `AppDelegate` が持つ。

### D8. 画面

- `MenuBarContentView` は上から「Mewbell」の見出しと再読み込みボタン、状態に応じた本体（`AccountListView` か `GuidanceView`）、Quit ボタンの順に並べる。幅は M0 の 240pt から 320pt に広げる（コマンドの行が収まるように）
- コマンドの行は等幅フォントの `Text` とコピーボタン（`NSPasteboard.general`）。コマンド文字列は固定の書式に、検証済みのホスト名だけを埋め込む
- `https://cli.github.com/` を開くボタンは、コード中の定数 URL を `NSWorkspace.shared.open` に渡すだけにする

### D9. テストでの差し替え

- `ProcessRunning` の偽物が、受け取った実行ファイル・引数・環境変数を記録し、用意した結果（終了コード、標準出力、タイムアウト、出力超過）を返す。`GhClient`、`GhLocator` のログインシェル検索、`AccountDiscovery` のテストで使う
- `SubprocessRunner` そのものは、`/usr/bin/env`（環境変数が渡っていないこと）、`/bin/sleep`（タイムアウト）、`/usr/bin/yes`（出力上限）を実際に起動して確かめる
- パスの検証は、テスト用の一時ディレクトリにファイルを作って `chmod` で権限を変えて確かめる（`/opt/homebrew` など本物の候補は使わず、候補の一覧を注入する）
- `hosts.yml` の解析は文字列のフィクスチャで確かめる（トークンは `test-token` のようなダミー。`gho_` などで始めない）。`AccountDiscovery` には設定ディレクトリを注入し、開発者の `~/.config/gh` を読まない

## セキュリティ

トークンの流れ:

- 取得: `GhClient` が `gh auth token --hostname <host> --user <user>` の標準出力から受け取り、すぐ `AccessToken` にする
- 保持: `CredentialStore`（actor）の辞書にだけ置く。`AccountStore`・View・ログには渡さない
- 送信: M1 では送らない。M2 で、`AccountID` に対応するホストの API ベースへのリクエストにだけ付ける
- 破棄: アカウントが `hosts.yml` から消えたとき、全体の状態が「アカウントあり」以外になったとき、アプリの終了時（`applicationShouldTerminate`）

`.claude/rules/security.md` への対応:

| 項目 | 対応 |
| --- | --- |
| トークンは `gh auth token` の標準出力からだけ取得。`hosts.yml` はホスト名とユーザー名以外を型に載せない | 対応（D4、D6）。`oauth_token` を含むフィクスチャで値が結果に無いことをテストする |
| トークンはメモリ上の actor にだけ持つ | 対応（`CredentialStore`） |
| トークン専用の型で `description` などを伏せ字に | 対応（D6）。`Codable` には準拠させない |
| `Logger` を使い可変値は `.private` / ヘッダーとボディを出さない | 対応。HTTP は M1 では無い |
| gh の標準エラー出力をそのまま UI・ログに出さない | 対応（D6）。UI には出さず、ログは伏せ字化してから |
| テスト・フィクスチャに本物の形式のトークンを書かない | 対応（`test-token` を使う。伏せ字化のテストに要る `ghp_` 形式の文字列は、ソース上で `"gh" + "p_"` のように分けて書き、secret scanning に引っかからないようにする） |
| 削除・無効化・終了時にトークンを破棄 | 対応（D7）。無効化は M4 |
| `Process` に絶対パスと引数配列 / シェル経由は `command -v gh` の 1 回だけで結果を検証 | 対応（D3） |
| gh のパスの検証（通常ファイル・実行可能・world-writable でない） | 対応（D3）。group-writable も拒否する |
| 子プロセスの環境変数から `GH_TOKEN` などを除去 | 対応（D5）。偽のランナーと `/usr/bin/env` の両方でテストする |
| ホスト名・ユーザー名の検証、`-` で始まる値の拒否 | 対応（gh-cli spec、D4） |
| サブプロセスのタイムアウトと出力上限 | 対応（D2、D3、D6） |
| ネットワーク（オリジン検査、HTTPS、リダイレクト、キャッシュ） | 該当しない。M1 では Mewbell から HTTP リクエストを送らない |
| ブラウザで開く URL | 固定の `https://cli.github.com/` だけ（D8）。外部由来の URL は開かない |
| Hardened Runtime、緩める entitlement を付けない | M0 の設定のまま。Yams は静的にリンクされるので library validation に影響しない |
| 通知の本文 | 該当しない（M3） |
| 依存の固定と `Package.resolved` のコミット | 対応（D4） |
| GitHub Actions | 変更しない |

## Risks / Trade-offs

- [gh が Keychain のアクセス確認を出して止まる] → 10 秒のタイムアウトで「トークンを取れない」にする。ポップオーバーを開くたびに失敗したアカウントを取り直すので、ユーザーが確認を許可した後に開き直せば回復する
- [`MenuBarExtra(.window)` の `onAppear` がポップオーバーを開くたびに呼ばれない] → 実装の最初に手で確かめる。呼ばれなければ、ポップオーバーのウィンドウの `NSWindow.didBecomeKeyNotification` を使う
- [Finder から起動すると、シェルで設定した `GH_CONFIG_DIR` が効かない] → 既定の `~/.config/gh` を読む。gh の子プロセスにも同じ環境を渡すので、読む場所と gh が使う場所はずれない。シェルと違う場所を使っているユーザーは M4 以降の課題にする
- [ログインシェルの起動で rc ファイルが重い・対話を求める] → タイムアウト 5 秒と、起動ごとに 1 回だけの制限で影響を抑える。標準入力は `/dev/null` にする
- [ユーザー名の許可範囲を広げすぎる] → 英数字・`-`・`_` だけにし、`-` で始まる値は拒否する。gh の引数は配列で渡すのでシェルの解釈は入らない
- [Yams のノード木に一時的に `oauth_token` の値が載る] → 解析は `AccountDiscovery` の中で完結させ、ノード木を外に出さない。`hosts.yml` にトークンが平文で入っているのは gh 側の設定の問題で、Mewbell が読み取って保持することはない

- [一度持ったトークンを取り直す経路が無い（`gh auth refresh -s repo` や再ログインの後も古いトークンを持ち続ける）] → M1 ではトークンを送らないので影響しない。M2 で、API が 401 を返したときやスコープ不足を見つけたときに、そのアカウントのトークンを捨てて取り直す
- [`gh auth login` などが `hosts.yml` を書いている途中に読むと「読めない」になり、トークンをすべて捨てる] → 安全側に倒す。次に開いたときに取り直すので、Keychain の確認やタイムアウトがアカウントの数だけ起きることはあるが、トークンを持ち続けるよりよい
- [子プロセスが起動したバックグラウンドのプロセスがパイプを開いたまま残る（ログインシェルの rc がエージェントを起動するなど）] → 子プロセスの終了から 500ms だけ EOF を待ち、それまでに読んだ分で結果を返す

## Migration Plan

M0 からの移行は無い。ロールバックは PR を戻すだけでよい（トークンも設定も永続化しないので、残るものが無い）。
