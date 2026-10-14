# Mewbell

macOS のメニューバーに常駐し、複数の GitHub アカウント（github.com / GHE Cloud データレジデンシー `*.ghe.com` / GHES 3.13+）の通知をまとめて受け取るネイティブアプリ。認証は **gh CLI の認証情報を再利用する**のが最大の特徴で、アプリ独自のログイン導線（PAT 入力・OAuth App）は持たない。

- 言語: Swift 6 / SwiftUI（必要箇所のみ AppKit）
- 対応 OS: macOS 26 以上
- App Sandbox: 無効（gh をサブプロセス実行するため）
- 配布: public リポジトリ・MIT。GitHub Releases の zip と自分の Homebrew tap（`yshrsmz/homebrew-tap`）の Cask。署名は ad-hoc のままで notarize はせず、自動更新（Sparkle など）も入れない。リリースは release-please と `.github/workflows/release.yml` で自動化している（`openspec/specs/distribution/`）
- Bundle ID: `com.codingfeline.mewbell`

## 開発の進め方（OpenSpec）

この repo は OpenSpec（OPSX）準拠で進める。**コードを書く前に必ず `openspec/changes/<change>/` の proposal → specs → design → tasks を揃える。** 仕様の正本は `openspec/specs/`。

- 新しい機能・設計変更・リファクタ → `/opsx:propose <change-name>` で変更を起こす。1 マイルストーン（M0〜M5）を 1〜数個の change に分ける
- 実装 → `/opsx:apply <change-name>`。tasks.md のチェックボックスを進めながら実装し、完了ごとにチェックを付ける
- 実装完了 → `/opsx:archive <change-name>`。delta spec が `openspec/specs/` にマージされる
- 迷ったら `/opsx:explore` で先に考える。タイポ修正や 1 行の修正は change 不要。ただし `openspec/specs/` に書かれた振る舞い（大きさ・配置・読み上げなど）を変える修正は、行数にかかわらず change を起こす
- change 名は `add-`, `update-`, `fix-`, `remove-` 始まりの kebab-case（例: `add-gh-account-discovery`）
- プロジェクト文脈と artifact ごとのルールは `openspec/config.yaml` にある。CLAUDE.md と重複させない

## リポジトリ構成（目標）

```
Mewbell/
├── Mewbell.xcodeproj/
│   └── project.xcproj          # Xcode 27.2+ の JSON 形式。コミットする。直接編集してよい
├── Mewbell/
│   ├── App/                    # @main, MenuBarExtra, Settings シーン
│   ├── GhCLI/                  # gh の検出・hosts.yml 解析・gh auth token 実行
│   ├── Accounts/               # AccountStore, Account
│   ├── GitHubAPI/              # URLSession クライアント、Notifications エンドポイント、HostKind
│   ├── Polling/                # Poller（アカウントごとの Task）
│   ├── Notifications/          # Notifier（UNUserNotificationCenter）
│   ├── Diagnostics/            # アカウント状態
│   ├── UI/                     # 一覧・設定の View
│   └── Shared/                 # どの層からも使う小さな道具（Logger(category:)）
├── MewbellTests/
├── openspec/
└── scripts/                    # build.sh, run.sh など
```

モジュールの責務は `openspec/config.yaml` の context と `openspec/specs/` を、層と型の置き場所は `docs/architecture.md` の A1 を正とする。

## ビルドとテスト

```bash
bash scripts/build.sh            # build/Debug/Mewbell.app を作る（Release は引数に Release）
xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test
bash scripts/run.sh              # ビルドして起動する（起動中の Mewbell は終了させる）
bash scripts/package-release.sh 0.1.0   # 配布物（zip と SHA-256）を build/dist/0.1.0/ に作る。リリースの CI と同じ処理
bash scripts/tests/verify-app-test.sh    # 配布物の署名・entitlement の検査（scripts/lib/verify-app.sh）のテスト
bash scripts/tests/check-architecture-test.sh   # docs/architecture.md の検査（scripts/check-architecture.sh）のテスト

# push 前の確認: 警告をエラー扱いにして Debug と Release をビルドする
xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build
xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Release MEWBELL_WARNINGS_AS_ERRORS=YES build
```

- 確認は `bash scripts/lint.sh`（`swift-format lint`、`swiftlint`、`docs/architecture.md` の検査）。整形は `bash scripts/format.sh`。CI（GitHub Actions）は macOS ランナーが高価なので ubuntu だけを使い、lint（`docs/architecture.md` の検査とそのテストを含む）と `openspec validate` だけを回す。macOS ランナーを使うのはリリースに関わるワークフロー（mewbell の `release.yml` と、homebrew-tap の Cask の PR の CI。`brew audit --cask` を確実に動かすため）だけ。`xcodebuild` のビルドとテストは PR の CI で回らないので、push 前に手元で必ず通す（テスト、lint、警告をエラー扱いにした Debug と Release のビルド）
- プロジェクトは Xcode 27.2 以降の JSON 形式（`project.xcproj`）。`project.pbxproj` には戻さない。ターゲット追加・ビルド設定の変更は `project.xcproj` を直接編集してよいが、編集後は必ず `xcodebuild` で開けることを確認する
- `DerivedData`・`build/`・`xcuserdata/` はコミットしない
- `SWIFT_APPROACHABLE_CONCURRENCY` が有効なので、nonisolated の async 関数は呼び出し元の actor の上で動く。テストの fake で同期的に待つと、その actor（`AccountPoller` など）が塞がり、テストが止まる（`docs/architecture.md` の A12。待たせ方の例は `FakeHTTPTransport` の `pausedMethod`）
- `openspec` は PATH に無い。プロジェクトの devDependency を `pnpm exec openspec ...` で動かす
- `xcodebuild test -only-testing:MewbellTests/<名前>` にはファイル名ではなくスイートの型名を渡す（`ThreadActionPollingTests.swift` の中は `DonePollingTests` と `MarkAllReadPollingTests`）。無い名前を渡してもエラーにならずに飛ばすので、結果の「N tests in M suites」のスイート数を確かめる
- SwiftUI の `Text` に `.font(.body)` を明示すると、既定の書体と同じ 13pt でも折り返し方が変わる（短い最後の行を避けるように折り返す）。スレッドの件名の `Text` には書体を付けない
- ユニットテストの `NSHostingView` では SwiftUI のアクセシビリティの要素が作られず、`accessibilityLabel` や `accessibilityHidden` の効き目は確かめられない。読み上げは手元の VoiceOver で確かめる項目として tasks に置く

## 実装上の約束

コードの構造の約束（層と依存の向き、状態の持ち方、actor と `@MainActor` の境界は A2、外部依存は A13 など）は `docs/architecture.md` にまとめている。設計（design.md）・実装・レビューの指摘の仕分けで判断が要るときに読む。文書を変えるときはスキル `update-architecture-doc` の手順に従う。ここに書くのは、振る舞いの約束の要約だけにする。

- **トークンを永続化しない。** `gh auth token --hostname <host> --user <user>` で取得し、メモリにだけ持つ。ログ・エラーメッセージ・テストフィクスチャにトークン文字列を出さない
- **リクエストごとにトークンを明示的に付ける。** 共有クライアントのデフォルトヘッダーに入れない（アカウント混在時にページネーションでトークンが入れ替わる Gitify の不具合 #2176 を踏まない）
- **ポーリングは API の指示に従う。** アカウントごとに `Last-Modified` を保持して `If-Modified-Since` を送り、`304` は無視、`X-Poll-Interval`（下限 60 秒）より短い間隔で叩かない。ただし 5 分ごとと再読み込みの後は `If-Modified-Since` を付けずに取り直す（`Last-Modified` は未読の `updated_at` の最新値なので、それより古いスレッドの増減や Web での既読が `304` に隠れる）。ユーザーが再読み込みを押したときだけは間隔を待たずにすぐ取り直す（アカウントごとに前の取得の開始から 10 秒より早くはせず、レート制限で待っている間は早めない）
- **ホスト種別の判定**: `github.com` → `https://api.github.com`、`*.ghe.com` → `https://api.<host>`、それ以外 → `https://<host>/api/v3`
- **スコープ確認**: 初回レスポンスの `X-OAuth-Scopes` に `repo` も `notifications` も無いアカウントは「スコープ不足」にして止め、`gh auth refresh -s repo` を案内する
- gh が無い／未ログインのときはインストール・`gh auth login` の案内画面を出すだけ。フォールバックの認証経路は作らない
- gh のパスは `/opt/homebrew/bin/gh`, `/usr/local/bin/gh` の順に探し、見つからなければログインシェル経由で `command -v gh` を試す。自動では起動ごとに 1 回だけで、見つかっていなければユーザーが再読み込みを押したときだけ探し直す。設定で上書き可
- 新着通知は 1 スレッド 1 通知。通知 ID は `<host>/<user>/<threadId>`。既読・Done にしたスレッドの通知は取り下げる
- 通知クリックは「ブラウザで開く → `PATCH /notifications/threads/{id}` で既読」
- UI の一覧はアカウント → リポジトリの 2 段グルーピング。既定は `participating=false`（設定で切替）

## やらないこと（v1）

GitHub 以外のフォージ、Windows / Linux、コメント本文の表示や返信、自前 OAuth App、PAT 入力、Mac App Store 配布、Keychain の直接読み取り。

## コミットと PR

- Conventional Commits（`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`）。1 change = 1 PR を基本にし、PR 本文に対応する `openspec/changes/<change>/` を書く
- `/opsx:propose` で proposal / specs / design / tasks が揃い `openspec validate --strict` が通ったら、change 名のブランチを切って artifact をコミット・push し、**draft PR** を作る。実装（`/opsx:apply`）は同じブランチに積み、レビュー（`.claude/rules/review-process.md`）と archive を終えてから ready にする
- AI 生成コードを含む PR はその旨を書く
- main への直接 push はしない
