# Proposal

## Why

ポップオーバーの一覧の文字が小さく、薄くて読みづらい。スレッドの行の 2 行目（番号・理由・更新日時）、リポジトリの見出し、「Updated」の行、ホスト名、件数のバッジ、取得の状態と操作の失敗の文が、どれも `.caption`（macOS では 10pt。HIG が macOS の最小とする大きさ）で、その多くに `.secondary` を重ねている。手元で実測すると、これらの文字と背景のコントラスト比は 4.3〜4.4 : 1 で、HIG が 17pt 以下の文字に勧める 4.5 : 1 をわずかに下回っていた（ライトモードのポップオーバーの後ろに暗いウィンドウがあり、半透明の背景が灰色になっている条件）。macOS の SwiftUI には Dynamic Type が無く、ユーザーが文字を大きくして補うこともできない。

この change は M5（v0.1.0）の公開後の、M4（設定と操作）の UI の延長にあたる改善。

## What Changes

- ポップオーバーの文字は 11pt（`.subheadline`）より小さくしない。10pt の `.caption` / `.caption2` を使っている箇所（スレッドの行の 2 行目、リポジトリの見出し、ホスト名、active の印、取得の状態、操作の失敗、トークンを取れないときの案内、通知が切られているときの案内、折りたたんだときの件数、すべて既読の確認の文、見出しの山形）を `.subheadline` に上げる
- アカウントの見出しのユーザー名を、スレッドの件名（13pt）より小さい 11pt の semibold から、13pt の semibold に上げ、見出しとして件名より目立たせる
- 見出し（アカウントのユーザー名、リポジトリの `owner/name`）は `.secondary` で薄くせず、標準の文字色で出す。`.secondary` は補足の情報（スレッドの行の 2 行目、ホスト名、「Updated」の行など）にだけ使う
- 文字の色はシステムの色（`.primary` / `.secondary`）だけを使い、文字に独自の透明度を掛けない（「コントラストを上げる」「透明度を下げる」の設定がそのまま効くように）
- 幅 380pt のポップオーバーに収まることは変えない（見出しのホスト名は今と同じく省略して 1 行に収め、件名は今と同じく 2 行まで）
- 設定ウィンドウは対象にしない。不透明な背景の標準の `Form` で、項目の説明に `.caption` と `.secondary` を使うのは macOS の設定画面の慣習どおりのため

## Capabilities

### New Capabilities

（なし）

### Modified Capabilities

- `ui`: ポップオーバーの文字の大きさと色の決まりを定める Requirement「ポップオーバーの文字の読みやすさ」を新しく足す。既存の Requirement の振る舞い（何を表示するか）は変えない

## Impact

- 変わるコード: `Mewbell/UI/`（`ThreadRow.swift`、`RepositoryGroupView.swift`、`AccountSectionView.swift`（`AccountSectionView`・`FeedStatusView`）、`ActionFailureView.swift`、`DisclosureButton.swift`（山形と件数）、`NotificationPermissionBanner.swift`）。表示する内容や操作は変えない
- 設定ウィンドウ（`SettingsView`、`DiagnosticsSettingsView`）とメニューバーのアイコン（`MenuBarLabel`）は変えない
- トークン: 扱わない。何も永続化しない
- gh サブプロセス: 触れない
- ネットワーク: 触れない
- URL を開く処理: 触れない
- 外部依存: 追加しない
