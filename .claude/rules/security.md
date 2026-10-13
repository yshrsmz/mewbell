# セキュリティ

Mewbell はユーザーの gh 認証情報（GitHub / GHE アカウントのトークン）をそのまま使う。トークンが漏れればアカウントを乗っ取られるのと同じなので、以下を例外なく守る。迷ったら安全側に倒し、AskUserQuestion で確認する。

## トークンの扱い

- トークンは `gh auth token --hostname <host> --user <user>` の標準出力からだけ取得する。`hosts.yml` に `oauth_token` が平文で入っていても読まない。`hosts.yml` の解析ではホスト名とユーザー名以外のキーを型に載せない
- トークンはメモリ上の actor の中にだけ持つ。ディスク・UserDefaults・Keychain・キャッシュ・クラッシュ時に残るファイルに書かない
- トークンを `String` のまま View・ログ・エラー・`description` に流さない。トークン専用の型を作り、`CustomStringConvertible` / `CustomDebugStringConvertible` / `Codable` の出力を伏せ字にする
- ログには `print` を使わず `Logger`（os_log）を使い、可変値は既定の `.private` のままにする。HTTP のヘッダー（特に `Authorization`）とレスポンスボディはログに出さない
- `gh` の標準エラー出力や API のエラーボディをそのまま UI やログに出さない。表示するときはトークンらしい文字列（`gh[opsu]_`、`github_pat_` など）を伏せ字にしてから出す
- テスト・フィクスチャ・ドキュメントには本物の形式のトークンを書かない（`test-token` のような明らかなダミーを使う。`gho_` で始めると secret scanning に引っかかる）
- アカウントの削除・無効化・アプリの終了時には、メモリ上のトークンを破棄する

## gh サブプロセス

- `Process` に実行ファイルの絶対パスと引数配列を渡して起動する。`/bin/sh -c` などのシェル経由で文字列を組み立てて実行しない（唯一の例外は CLAUDE.md にある「ログインシェルで `command -v gh`」（自動では起動ごとに 1 回だけ、ほかはユーザーの再読み込み時だけ）。この場合も結果のパスを検証してから使う）
- 見つけた gh のパスは、実在する通常ファイルであること・実行可能であること・他人が書き込めない（world-writable でない）ことを確かめてから使う
- 子プロセスの環境変数から `GH_TOKEN`、`GITHUB_TOKEN`、`GH_ENTERPRISE_TOKEN`、`GITHUB_ENTERPRISE_TOKEN`、`GH_HOST` を取り除く。これらがあると `gh auth token` が指定したアカウント以外のトークンを返す
- `hosts.yml` から読んだホスト名・ユーザー名は、引数や URL に使う前に形式を検証する（ホスト名は DNS 名として妥当か、ユーザー名は GitHub のログイン名として妥当か）。`-` で始まる値は拒否する
- サブプロセスにはタイムアウトを付け、標準出力のサイズにも上限を設ける

## ネットワーク

- トークンを送る先は、そのアカウントのホストから CLAUDE.md の規則で導いた API ベース URL だけにする。送信前に、リクエスト先のスキーム・ホスト・ポートがアカウントの API ベースと一致することを確かめる
- HTTPS 以外は使わない。ATS の例外（`NSAllowsArbitraryLoads` など）を Info.plist に入れない
- リダイレクトは `URLSessionTaskDelegate` で扱い、オリジン（スキーム・ホスト・ポート）が変わるリダイレクトは拒否する。`Authorization` を付けたまま他のホストへ飛ばさない
- API レスポンスに含まれる URL（`subject.url`、`latest_comment_url` など）にトークン付きでアクセスするときも、同じオリジン検査を通す
- ブラウザで開く URL は `https` で、ホストがアカウントの Web ホストと一致するものだけにする。一致しなければ開かずに、リポジトリのページなど安全な URL で代用する
- 共有 `URLSession` の `httpAdditionalHeaders` にトークンを入れない（CLAUDE.md）。キャッシュは使わない（`URLCache` に認証付きレスポンスを残さない）

## アプリとビルドの設定

- App Sandbox は無効だが、Hardened Runtime は有効にする（配布物になる Release で有効にする。Debug は `ENABLE_PREVIEWS` のため Xcode が自動で無効にし、`get-task-allow` も入るが、これは許容する）。`com.apple.security.cs.disable-library-validation`、`allow-dyld-environment-variables`、`allow-unsigned-executable-memory` などの緩める entitlement を付けない
- 通知（UNUserNotification）の本文には、タイトル・リポジトリ名など API が返す表示用の情報だけを入れる。トークンや API URL を入れない

## 依存とサプライチェーン

- 外部依存は `docs/architecture.md` の A13 のとおり最小限にする。追加するときはバージョンを完全に固定し、`Package.resolved` をコミットする
- GitHub Actions はタグではなくコミット SHA で固定し、ワークフローの既定には `permissions: contents: read` を明示する。書き込みは要るジョブにだけ、要る権限を与える。`pull_request_target` を使わない
- CI にシークレットを渡さない。例外はリリースのワークフロー（mewbell の `release.yml` と homebrew-tap の Cask の更新）で使う GitHub App の秘密鍵だけで、`main` からの実行に限定した Environment `release` に置く。PAT は使わない。App のトークンは `actions/create-github-app-token` でジョブごとに発行し、対象のリポジトリと権限をそのジョブに要るものに絞る
- `repository_dispatch` などで外から受け取った値は信用しない。形式を検証してから使い、`${{ }}` でシェルに直接埋め込まずに `env:` を通して渡す

## レビュー

- トークン・gh サブプロセス・ネットワーク・URL を開く処理に触れる変更では、PR 本文に「セキュリティ上の確認」の節を設け、上のどの項目を満たしたかを書く
- 上の項目を満たしているかはユニットテストで確かめる（伏せ字、環境変数の除去、オリジン検査、リダイレクト拒否、ホスト名・ユーザー名の検証）
