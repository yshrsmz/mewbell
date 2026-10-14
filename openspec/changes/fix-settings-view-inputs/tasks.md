# Tasks

## 1. 設定の下位の View の入力を値と操作にする

- [x] 1.1 `Mewbell/UI/SettingsView.swift` に `SettingsActions` と `static var none` を足し、`SettingsView` の `body` で `AppSettings` と `LaunchAtLogin` のメソッドから組み立てる（design.md D1）。`GeneralSettingsView` と `GhSettingsView` を、値と `SettingsActions` を受け取る形にする（D2）。対応する `#Preview` を、`AppSettings`・`LaunchAtLogin` を組まずに描く形にする（D5）。`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build` が通ることを確かめる。
- [x] 1.2 `AccountsSettingsView` と `AccountSettingsSection` を、`state`・`preferences` のクロージャ・`AccountPreferences` の値と `SettingsActions` を受け取る形にする（D3）。Accounts の `#Preview` を、無効のアカウントと参加しているスレッドだけのアカウントを `preferences` のクロージャで描く形にする（D5）。1.1 と同じビルドが通ることを確かめる。
- [x] 1.3 `Mewbell/UI/DiagnosticsSettingsView.swift` の `DiagnosticsSettingsView` を、`report: () -> DiagnosticsReport` だけを受け取り `body` で呼ぶ形にし、組み立てとアプリ・OS の版の `static let` をルートの `SettingsView` に移す（D4）。doc コメントに、クロージャを自分の `body` で呼ぶ理由を書く。`git grep -n "AppSettings\|AccountStore\|NotificationStore\|LaunchAtLogin\b" Mewbell/UI/SettingsView.swift Mewbell/UI/DiagnosticsSettingsView.swift` で、store の型が出てくるのが `SettingsView` の中だけであることを確かめる。1.1 と同じビルドが通ることを確かめる。
- [x] 1.4 スキル `update-architecture-doc` の手順で、`docs/architecture.md` の「既知の逸脱」から A4 の行を消し、A4 の本文に `LaunchAtLogin`（store の例）と `SettingsActions`（操作のクロージャの例）を、根拠に `fix-settings-view-inputs D1・D2` を足す（D5）。`bash scripts/check-architecture.sh` と `bash scripts/tests/check-architecture-test.sh` が通ることを確かめる。

## 2. 確認

- [x] 2.1 ビルドとテストが通ることを確かめる。
  - `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` で全テストを通す。
  - `MEWBELL_WARNINGS_AS_ERRORS=YES` で、Debug と Release のビルドを通す。
  - `bash scripts/lint.sh` と `pnpm exec openspec validate --all --strict` を通す。
- [ ] 2.2 `bash scripts/run.sh` で起動し、設定ウィンドウを手元で確かめる。General: 「Launch at login」と「Play a sound」の切り替えが反映され、設定ウィンドウを閉じて開き直しても保たれること。Accounts: アカウントの「Enabled」を切ると下の 2 つのトグルが無効になり、ポップオーバーからそのアカウントの区画が消えること、「Only threads I'm participating in」と「Show macOS notifications」の切り替えが保たれること。gh: 実行ファイルのパスに使えないパスを入れて Return を押すと警告が出て、Reset で消えること。Diagnostics: 次の取得の後に「Last fetched」の時刻が進むこと、Copy で `Copied` に変わること。

## 3. レビュー

- [x] 3.1 別コンテキストの opus サブエージェントで `simplify` を実行する。変更を確かめてから取り込み、テストが通ることを確かめる。（変更なし。`launchAtLoginIsOn` が `status` から導けるという候補は、D2 で承認待ちを含める判断を `LaunchAtLogin` の 1 か所に残すと決めているので見送った）
- [x] 3.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。（8 件。観測の粒度の 4 件は、別のサブエージェントの評価とユーザーの判断で今の形のままにし、design.md の D3 と Risks に理由を書いた。design.md の引数名の食い違いを直した。ほかの 3 件は直さない。理由は PR 本文）
- [x] 3.3 ロジックの変更を含む修正が多ければ、3.2 を新しいサブエージェントでもう一度実行する。（コードの修正が無いので再実行しない）
