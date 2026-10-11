# Tasks

## 1. 変更前の記録

- [x] 1.1 変更前のポップオーバーを測る。ライトモードで後ろに暗いウィンドウがある条件で、未読のあるアカウントのポップオーバーのスクリーンショットを撮り、スレッドの行の 2 行目・リポジトリの見出し・「Updated」の行・ホスト名の文字と背景のコントラスト比と、一覧に一度に見えるスレッドの数を記録する。確認: 測った値を 1.1 の結果としてここに書いた。結果（後ろは暗いターミナル、背景の輝度は 0.39 前後。領域の中でいちばん暗い画素といちばん明るい画素の比なので概算）: 件名 8.9 : 1、スレッドの行の 2 行目 4.33 : 1、「Updated」の行 4.37 : 1、リポジトリの見出し 4.32 : 1、ホスト名 4.41 : 1。未読が 1 件だけだったので、見えるスレッドの数は比べられない（3.3 (a) では行の高さで比べる）

## 2. 書体と色の変更

- [x] 2.1 スレッドの行とリポジトリの見出しを変える（design D2）: `ThreadRow` の 2 行目を `.subheadline`、`RepositoryGroupView` の見出しを `.subheadline.weight(.semibold)` にして `.secondary` を外す。確認: 「Thread row hovered」のプレビュー（描けなければ一時的な `ImageRenderer` のテスト。コミットしない）で、件名が 2 行で省略され、ホバーのボタンが件名の 1 行目に揃い、ボタンの下の件名が消えていることを見る。結果: Xcode のプレビューは「Collapsed」を描いた後、プレビューの実行環境が `VStack.init` で落ちるようになり（コードを変えずに再現し、同じ ThreadRow を含む「Collapsed」は描ける）、「Thread row hovered」は描けなかった。手元で起動したポップオーバーで行にマウスを載せ、ボタンが件名の 1 行目に揃い、ボタンの下の件名が消えることを見た
- [x] 2.2 アカウントの見出しを変える（D2）: ユーザー名を `.headline`、active の印・ホスト名・参加のみの印を `.subheadline` にする。見出しの山形（`DisclosureChevron`）を `.subheadline.weight(.semibold)`、折りたたんだときの件数（`CollapsedCount`）を `.subheadline.monospacedDigit()`、すべて既読の確認の文を `.subheadline.weight(.semibold)` にする。確認: 「Collapsed」と「Mark all as read」のプレビューに 40 文字のホスト名の GHES のアカウントを足して、幅 380pt の中で見出しが 1 行に収まり、ホスト名が省略され、すべて既読と Web の通知一覧のボタンが押せる位置に残ることを見る。結果: 「Collapsed」のプレビューに `notifications.ghes.engineering.example.com` の `erin`（active、参加のみ）を足し、ライトとダークで見出しが 1 行に収まりホスト名が中央で省略されることを見た。手元のポップオーバーで、すべて既読を 1 回押した確認の文（Mark 2 as read?）でもホスト名が省略されて 1 行に収まった
- [x] 2.3 取得の状態・操作の失敗・案内の文を変える（D2）: `FeedStatusView`、`ActionFailureView`、`AccountSectionView` の「Checking gh…」とトークンを取れないときの文、`NotificationPermissionBanner` を `.subheadline` にする。確認: `ActionFailureView` と「Permission banner」のプレビューで、文が折り返して切れずに出ることを見る。結果: 2.1 と同じ理由でこの 2 つのプレビューは描けなかった。「Collapsed」のプレビューの dave の「Rate limited. Retrying at …」（`FeedStatusView`）と、手元のポップオーバーの「Updated」の行が 11pt で出ることを見た。`ActionFailureView` と案内の帯は、書体の指定を変えただけで、折り返しの指定（`fixedSize(horizontal: false, vertical: true)`）は変えていない
- [x] 2.4 10pt が残っていないことを確かめる（D1）。確認: `grep -nE '\.(caption2?|footnote)\b' Mewbell/UI/ThreadRow.swift Mewbell/UI/RepositoryGroupView.swift Mewbell/UI/AccountSectionView.swift Mewbell/UI/ActionFailureView.swift Mewbell/UI/DisclosureButton.swift Mewbell/UI/NotificationPermissionBanner.swift Mewbell/UI/GuidanceView.swift Mewbell/UI/CommandRow.swift Mewbell/App/MenuBarContentView.swift` が何も出さない。文字の色に `.opacity` を掛けた箇所が無い（`grep -n 'foregroundStyle(.*opacity' Mewbell/UI Mewbell/App` が何も出さない）。結果: どちらも何も出さなかった

## 3. 最終確認

- [x] 3.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [x] 3.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [x] 3.3 手元で起動して確認した: (a) 1.1 と同じ条件でスクリーンショットを撮り、同じ箇所のコントラスト比と見えるスレッドの数を測って 1.1 と比べた結果をここに書いた、(b) スレッドの行の 2 行目・見出し・取得の状態に 10pt の文字が無い（見た目で、件名と 2 行目の大きさの差が 2pt あることを含む）、(c) ポップオーバーの幅が変わらず、横にスクロールしない、(d) ダークモードでも同じように読める、(e) システムの「コントラストを上げる」をオンにすると、薄い色の文字も濃くなる（設定の切り替えはユーザーに頼む）、(f) ホバーのボタン、開閉、すべて既読の確認がこれまでどおり動く。結果: (a) 同じ条件（後ろは暗いターミナル、背景の輝度 0.39 前後）で、件名 8.83 : 1、スレッドの行の 2 行目 4.39 : 1、「Updated」の行 4.34 : 1、リポジトリの見出し 8.81 : 1（変更前 4.32）、ホスト名 4.47 : 1、ユーザー名 9.13 : 1。薄い色の文字の比は変わらず（design D3 のとおり）、10pt から 11pt になった。行の高さは数値では測っていない。未読が 1 件なので見えるスレッドの数も比べられず、2 行目と見出しが 1pt ずつ大きくなった分だけ高くなることを、スクリーンショットで見た、(b) 10pt の文字は無く、件名（13pt）と 2 行目（11pt）の差は見た目でも分かる、(c) 幅は変わらず横にスクロールしない、(d) ダークモードは「Collapsed」のプレビューの Dark Appearance で見た（システムの外観は切り替えていない）、(e) システムの設定は切り替えず、プレビューの Increased Contrast の変種で確かめた。白い背景の上の補足の文字は 3.10 : 1 から 8.18 : 1 に上がった、(f) ホバーのボタンが出て、リポジトリの開閉（1.1 の前に開いたもの）とすべて既読の確認の文が出ることを見た（2 回目は押していない）
- [x] 3.4 README にポップオーバーの見た目の説明やスクリーンショットがあれば、変更に合わせて直す。確認: 差分を読み、spec と食い違いが無い（直すものが無ければそう書く）。結果: README には文字の大きさや見た目の説明もスクリーンショットも無いので、直すものは無い

## 4. 別コンテキストでのレビュー

- [ ] 4.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 4.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 4.2 をやり直す。確認: 指摘の件数と対応結果を PR 本文に書いた
