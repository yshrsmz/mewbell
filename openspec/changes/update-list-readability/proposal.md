# Proposal

## Why

ポップオーバーの一覧の文字が小さく、薄くて読みづらい。スレッドの行の 2 行目（番号・理由・更新日時）、リポジトリの見出し、「Updated」の行、ホスト名、件数のバッジ、取得の状態と操作の失敗の文が、どれも `.caption`（macOS では 10pt。HIG が macOS の最小とする大きさ）で、その多くに `.secondary` を重ねている。手元で実測すると、これらの文字と背景のコントラスト比は 4.3〜4.4 : 1 で、HIG が 17pt 以下の文字に勧める 4.5 : 1 をわずかに下回っていた（ライトモードのポップオーバーの後ろに暗いウィンドウがあり、半透明の背景が灰色になっている条件）。macOS の SwiftUI には Dynamic Type が無く、ユーザーが文字を大きくして補うこともできない。

狙いは文字の大きさと、見出しと補足の区別を付けることで、薄い色の文字のコントラスト比を数値で上げることではない（システムの副次的な文字色は白い背景の上でも 4.5 : 1 に届かない）。コントラストが足りないユーザーは、システムの「コントラストを上げる」で補える（design D3）。

この change は M5（v0.1.0）の公開後の、M4（設定と操作）の UI の延長にあたる改善。

## What Changes

- ポップオーバーの文字は 11pt（`.subheadline`）より小さくしない。10pt の `.caption` / `.caption2` を使っている箇所（スレッドの行の 2 行目、リポジトリの見出し、ホスト名、active の印、参加のみの印、取得の状態、操作の失敗、トークンを取れないときの案内、通知が切られているときの案内、折りたたんだときの件数、すべて既読の確認の文、見出しの山形、「Checking gh…」）を `.subheadline` に上げる。「No unread notifications」は、ほかの補足の文と揃えるため、12pt（`.callout`）から 11pt（`.subheadline`）にする（この change で小さくなるのはここだけ）
- アカウントの見出しのユーザー名を、スレッドの件名（13pt）より小さい 11pt の semibold から、13pt の太字（`.headline`）に上げ、見出しとして件名より目立たせる
- 見出し（アカウントのユーザー名、リポジトリの `owner/name`）は `.secondary` で薄くせず、標準の文字色で出す。`.secondary` は補足の情報（スレッドの行の 2 行目、ホスト名、「Updated」の行など）にだけ使う。トークンを取れないときの案内と一覧を打ち切ったことの知らせも、読めないと困る文なので標準の文字色にする。薄い色にする文字の範囲は spec の Requirement を正とする
- 文字の色はシステムの色（`.primary` / `.secondary`）だけを使い、文字に独自の透明度を掛けない（「コントラストを上げる」「透明度を下げる」の設定がそのまま効くように）
- 幅 380pt のポップオーバーに収まることは変えない。アカウントの見出しはホスト名 → ユーザー名の順に省略して 1 行に収め、active の印・件数・すべて既読の確認の文は省略しない。リポジトリの見出しは 1 行にして中央を省略する（今は折り返している）。ユーザー名・ホスト名・リポジトリ名はツールチップで全体を読める。件名は今と同じく 2 行まで
- 再試行の文（Rate limited. / Could not fetch notifications. Retrying at <時刻>）を、時刻の途中で折り返さないよう文ごとに 1 つの文にする
- `gh auth login --hostname <host>` の文字列を 1 か所にまとめる（表示は変えない）
- 設定ウィンドウは対象にしない。不透明な背景の標準の `Form` で、項目の説明に `.caption` と `.secondary` を使うのは macOS の設定画面の慣習どおりのため

## Capabilities

### New Capabilities

（なし）

### Modified Capabilities

- `ui`: ポップオーバーの文字の大きさと色の決まりを定める Requirement「ポップオーバーの文字の読みやすさ」を新しく足す。既存の Requirement「操作の失敗の表示」の「1 行」の言い方を、1 つの知らせとして折り返してよい意味に直す（MODIFIED）。表示する項目は変えない。リポジトリの見出しは、折り返す代わりに省略してツールチップで全体を出す

## Impact

- 変わるコード: `Mewbell/UI/`（`ThreadRow.swift`、`RepositoryGroupView.swift`、`AccountSectionView.swift`（`AccountSectionView`・`FeedStatusView`）、`ActionFailureView.swift`、`DisclosureButton.swift`（山形・件数・`capsuleBadge`・`ListLayout.ellipsisWidth`・`sectionNote()`）、`CommandRow.swift`（`GhCommand`）、`MewbellTests/AccountDiscoveryTests.swift`、`MewbellTests/ActionFailureMessageTests.swift`、`NotificationPermissionBanner.swift`）、`SettingsView.swift`、`Mewbell/Accounts/Account.swift`（ホスト名とホスト種別の書式を、`HostKind.displayName` の隣の `Account.hostLabel` にまとめ、見出しと設定画面で使う。表示は変えない）。表示する内容と操作は変えない（省略したリポジトリ名・ホスト名・ユーザー名の全体はツールチップで読める）
- 設定ウィンドウの文字の大きさと色（`SettingsView`、`DiagnosticsSettingsView`）とメニューバーのアイコン（`MenuBarLabel`）は変えない
- トークン: 扱わない。何も永続化しない
- gh サブプロセス: 触れない
- ネットワーク: 触れない
- URL を開く処理: 触れない
- 外部依存: 追加しない
