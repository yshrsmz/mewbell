# Proposal

## Why

ポップオーバーの一覧は未読のスレッドしか出さず、既読にしたものや Done にしたもの、保存（Saved）したものを見たり、GitHub の Web の絞り込み（`reason:`・`repo:` など）を使ったりするには、ブラウザで通知の一覧を開き直す必要がある。今は Mewbell からそこへ移る導線が無く、アカウントが複数のホスト（github.com・`*.ghe.com`・GHES）にまたがると、どのホストの一覧を開けばよいかをユーザーが覚えておくことになる。

この change は M5（v0.1.0）の公開後の、M4（設定と操作）の UI の延長にあたる改善。

## What Changes

- アカウントの区画の見出しの「すべて既読」の隣に、そのアカウントのホストの Web の通知一覧（`https://<host>/notifications`）を既定のブラウザで開くボタンを置く
- 開く URL には絞り込みを付けない。アカウントの「参加しているスレッドだけにする」の設定は反映しない
- ボタンはトークンの状態や取得の状態にかかわらず、一覧に出ているアカウントの区画（無効のアカウント以外）にいつも出す（スコープ不足やトークンを取れないときも、Web では通知を見られるため）
- ボタンを押しても、スレッドの既読・Done やリクエストの送信は行わない

## Capabilities

### New Capabilities

（なし）

### Modified Capabilities

- `ui`: 「Web の通知一覧を開く」の Requirement を新しく足す（アカウントの区画の見出しのボタン、開く URL とその検査）

## Impact

- 変わるコード: `Mewbell/GitHubAPI/ThreadWebURL.swift`（Web の通知一覧の URL を組み立てて検査する）、`Mewbell/Polling/NotificationStore.swift`（URL を開く）、`Mewbell/UI/AccountSectionView.swift`（見出しのボタンと `ThreadListActions`）、`Mewbell/App/MenuBarContentView.swift`（つなぎ込み）、README の現状の説明
- トークン: 扱わない。ボタンはトークンを使わず、何も永続化しない
- gh サブプロセス: 触れない
- ネットワーク: 触れない。API へのリクエストもポーリングも変えない
- URL を開く処理: 触れる（`.claude/rules/security.md` が適用される）。開く URL はアカウントの検証済みのホストから組み立て、`https` でホストがアカウントの Web ホストと一致することを確かめてから開く
- 外部依存: 追加しない
