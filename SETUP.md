# Mewbell ブートストラップ手順（Claude Code + OpenSpec）

このフォルダの `CLAUDE.md` と `openspec/config.yaml` を新しいリポジトリに置き、以下の順で進める。

## 1. リポジトリと OpenSpec の初期化

```bash
mkdir Mewbell && cd Mewbell && git init
cp <このフォルダ>/CLAUDE.md .
mkdir -p openspec && cp <このフォルダ>/openspec/config.yaml openspec/

# OpenSpec CLI はグローバルに入れず、package.json でバージョン固定してプロジェクトローカルに入れる
npm ci --ignore-scripts
npx openspec init --tools claude  # .claude/skills/openspec-* と openspec/specs, changes を生成。config.yaml は上書きされない
```

以降 `openspec` コマンドは `npx openspec` で呼ぶ。artifact を日本語で書く設定は `config.yaml` の `context` に入っている（`openspec init --language Japanese` が書き込むのと同じ行）。

`openspec init` が `config.yaml` を上書きするか聞いてきたら「No」。生成後 `openspec/config.yaml` に `context:` と `rules:` が残っていることを確認する。

## 2. Claude Code で M0 を起こす

Claude Code を repo 直下で開き、まず探索せずに change を起こす：

```
/opsx:propose add-project-skeleton
```

説明として次を渡す（そのまま貼ってよい）：

> M0「土台」。Xcode 27.2 以降の JSON プロジェクト形式（project.xcproj）で、SwiftUI の `MenuBarExtra`（window スタイル）を持つ `LSUIElement` なアプリを作る。Bundle ID `com.codingfeline.mewbell`、Deployment target macOS 26、Swift 6 strict concurrency、App Sandbox 無効。MIT の LICENSE、README、`.gitignore`（DerivedData・build・xcuserdata。xcodeproj はコミットする）、swift-format と swiftlint の設定、GitHub Actions（Xcode 27.2 以降が入ったランナーを `xcode-select` で指定し、lint・ビルド・テスト）。メニューバーに猫アイコンが出て、ポップオーバーに「Mewbell」と Quit ボタンがあり、終了できる。テストターゲット MewbellTests にダミーテストを 1 つ。

生成された `proposal.md` / `specs/` / `design.md` / `tasks.md` を読み、違和感があれば直してから：

```
/opsx:apply add-project-skeleton
```

ビルドが通って起動を確認したら：

```
/opsx:archive add-project-skeleton
```

## 3. 以降の change（目安）

| M | change 名 | 要点 |
| --- | --- | --- |
| M1 | `add-gh-account-discovery` | gh 検出、hosts.yml 解析、`gh auth token` 実行、アカウント一覧表示、未検出/未ログイン案内 |
| M2 | `add-notification-fetch` | GitHubAPI クライアント、ホスト種別判定、ポーリング（304 / X-Poll-Interval）、一覧（アカウント→リポジトリ）、クリックで開く |
| M3 | `add-system-notifications` | UNUserNotificationCenter、1 スレッド 1 通知、クリックで開いて既読、未読バッジ |
| M4 | `add-settings-and-actions` | Done、全既読、participating 切替、アカウント ON/OFF、ログイン時起動、Diagnostics 表示 |
| M5 | `add-distribution`（任意） | ビルドスクリプト、署名、Sparkle、Homebrew Cask |

1 change が大きくなりそうなら分割する（例: M2 を `add-github-api-client` と `add-notification-list` に）。

## 4. 運用メモ

- `openspec status --change <name>` で artifact の進捗、`openspec validate` で spec の形式チェック
- `CLAUDE.md` は「どう作るか」の約束、`openspec/specs/` は「何を満たすか」の正本。重複させない
- Claude Code の `/compact` 前に tasks.md のチェックを更新しておくと、文脈が切れても再開しやすい
- 設計判断の経緯は claude.ai 側のドキュメント「Mac 用 GitHub 通知アプリ：既存プロダクト調査と要件整理」にある。必要なら README から参照する
