# Proposal

## Why

`docs/architecture.md` の「既知の逸脱」に A4 の行が残っている。A4 は、store を直接受け取るのをシーンのルートの View（`SettingsView` など）だけにし、それ以外の View には値と操作のクロージャだけを渡すと決めている。設定ウィンドウでは、ルートの下の View が store を直接受け取っている。

- `GeneralSettingsView` が `AppSettings` と `LaunchAtLogin` を受け取る。
- `AccountsSettingsView`・`AccountSettingsSection`・`GhSettingsView` が `AppSettings` を受け取る。
- `DiagnosticsSettingsView` が `AppSettings`・`AccountStore`・`NotificationStore` を受け取る。

このため、プレビューで store を組まないと下位の View を描けず、どの操作が起きるかが引数から読めない。ポップオーバーの側（`ThreadListActions` を受け取る一覧の View）とも形が揃っていない。

## What Changes

- 設定の操作をまとめた操作の型（`ThreadListActions` の兄弟）を `UI/` に足す。ルートの `SettingsView` が `AppSettings` と `LaunchAtLogin` のメソッドから組み立て、下位の View に渡す。
- `GeneralSettingsView` は、通知の音の設定とログイン項目の状態（`status`・`failed`・`isOn`）を値で受け取り、切り替え・システム設定を開く・読み直しを操作の型で呼ぶ。`LaunchAtLogin` も A4 の store として扱う。
- `AccountsSettingsView` と `AccountSettingsSection` は、アカウントの状態と `AccountPreferences` の値を受け取り、`AccountID` を受け取る操作で設定を変える。
- `GhSettingsView` は、gh の実行ファイルと設定ディレクトリの上書きを値で受け取り、確定を操作の型で呼ぶ。
- `DiagnosticsSettingsView` は、ルートから `DiagnosticsReport` を作るクロージャを受け取り、自分の `body` で呼ぶ。ポーリングのたびに変わる通知の状態を読むのは、今と同じくこの View だけにする。
- `#Preview` を新しい引数で描くように直す。プレビューでは store を組まない。
- `docs/architecture.md` の「既知の逸脱」から A4 の行を消す。原則の本文と適用外は変えない。

設定ウィンドウの見た目と振る舞いは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。View が受け取る引数の形だけを変え、`openspec/specs/settings` と `openspec/specs/diagnostics` の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。

## Impact

- マイルストーン: 特定のマイルストーンには属さない保守の change。add-architecture-principles が「既知の逸脱」に記録した A4 の行を片付ける。
- 変更するもの: `Mewbell/UI/SettingsView.swift`、`Mewbell/UI/DiagnosticsSettingsView.swift`、`docs/architecture.md`（既知の逸脱）。`AppSettings`・`LaunchAtLogin`・`AccountStore`・`NotificationStore` と `MewbellApp` からの呼び出しは変えない。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: いずれにも触れない。トークンは今までどおりメモリにだけ持ち、永続化しない。gh のパスの上書きの検査（`ExecutableValidator`・`ConfigDirectoryValidator`）は今の呼び出しのまま残す。Diagnostics に出す内容（トークン・API の URL・スレッドの件名を出さない）は変えない。
