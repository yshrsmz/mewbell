## ADDED Requirements

### Requirement: アカウントごとの設定の識別と保持

アカウントごとの設定は `<host>/<user>`（ホスト名は小文字）で識別しなければならない（MUST）。gh からログアウトして一覧から消えたアカウントの設定は消さずに残し、同じアカウントでログインし直したときに同じ設定に戻らなければならない（SHALL）。

#### Scenario: ログインし直すと設定が戻る

- **GIVEN** `github.com/bob` を無効にした後、ユーザーが `gh auth logout --user bob` を実行し、Mewbell がアカウントを読み直した
- **WHEN** ユーザーが `gh auth login` で `bob` にログインし直し、Mewbell がアカウントを読み直す
- **THEN** `bob` は無効のまま一覧に戻る

## MODIFIED Requirements

### Requirement: 設定項目と既定値

Mewbell の設定は次の項目だけでなければならず（MUST）、値が保存されていない項目は既定値として扱わなければならない（MUST）。

| 範囲 | 項目 | 既定値 |
|---|---|---|
| 全体 | macOS の通知に音を付ける | オン |
| 全体 | gh の実行ファイルのパスの上書き | なし（gh-cli「gh 実行ファイルの検出」の順に探す） |
| 全体 | gh の設定ディレクトリの上書き | なし（gh-cli「hosts.yml の場所と読み取り」の順に決める） |
| アカウントごと | 有効 | オン |
| アカウントごと | 参加しているスレッドだけにする（`participating=true`） | オフ |
| アカウントごと | macOS の通知を出す | オン |

ログイン時に起動するかどうかは、Mewbell の設定として保存せず、macOS のログイン項目の登録の状態をそのまま使わなければならない（MUST）。

#### Scenario: 初めて起動したとき

- **GIVEN** Mewbell の設定を一度も変えたことがない
- **WHEN** ユーザーが `github.com/alice` で Mewbell を使う
- **THEN** `alice` は有効で、`participating=false` で取得され、macOS の通知は音付きで出る

#### Scenario: ログインし直すと設定が戻る

- **GIVEN** `github.com/bob` を無効にした後、ユーザーが `gh auth logout --user bob` を実行し、Mewbell がアカウントを読み直した
- **WHEN** ユーザーが `gh auth login` で `bob` にログインし直し、Mewbell がアカウントを読み直す
- **THEN** `bob` は無効のまま一覧に戻る
