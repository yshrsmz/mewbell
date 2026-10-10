# Tasks

## 1. スレッドの番号（GitHubAPI / UI）

- [x] 1.1 `ThreadWebURL.subjectNumber(for:endpoints:)` を足し、`target(for:endpoints:)` が返す型が Pull request か Issue のときだけ、その `id` を返す（D4）。確認: テストを足して通す: (a) `https://api.github.com/repos/octo/app/pulls/42` で `42`、(b) GHES の `https://ghe.example.com/api/v3/repos/team/svc/issues/7` で `7`、GHE Cloud の `https://api.acme.ghe.com/repos/acme/web/pulls/3` で `3`、(c) `https://evil.example.com/repos/octo/app/pulls/42` で `nil`、(d) リポジトリが一致しない `subject.url` で `nil`、(e) Commit・Release・Discussion・`subject.url` が無いスレッドで `nil`、(f) 番号が数字でない（`pulls/abc`）と `nil`。既存の `ThreadWebURL` のテストが通る。結果: (e) の Commit は `commits/<SHA>` の `subject.url` で確かめた（Release と Discussion 以外は、`target` は種類でなく URL の形で分けるので、番号は URL の形で決まる）。review-loop の修正（6.1・6.2）で今の形に変えた
- [x] 1.2 `ThreadRow` の 2 行目を `#<番号> · <理由> · <更新日時>` にし、番号は `NotificationThread.subjectNumber` を読んで出す。`ThreadRow` には番号の引数を持たせない（D4）。確認: プレビューに番号のある行と無い行を足して見る（件名が 2 行の行でも 2 行目の並びが崩れない）。ビルドが通る。結果: Xcode のプレビューは使えない（RenderPreview は未承認）ので、プレビューの追加にとどめ、見た目は 4.3 の手元での起動で確かめる。review-loop の修正（6.1・6.2）で今の形に変えた

## 2. 折りたたみの状態（UI / App）

- [x] 2.1 `Mewbell/UI/ListExpansion.swift` に `ListExpansion` と `RepositoryKey` を作る（`isCollapsed`、`toggle`、`expand(account:repositories:)`、`retain`）（D1、D3）。確認: テストを足して通す: (a) 作った直後はどのアカウントもリポジトリも開いている、(b) `toggle` で折りたたみ、もう一度で開く。アカウントとリポジトリは別々に覚える、(c) 同じ `owner/name` でもアカウントが違えば別のもの、(d) `expand(account: alice, repositories: [octo/app])` で `alice` と `alice` の `octo/app` が開き、`alice` の `octo/lib` と `bob` の `octo/app` は折りたたんだまま、(e) `retain([alice])` で `bob` のアカウントとリポジトリの状態が消える。結果: 6.3 でアカウントごとの `AccountExpansion` に変えた（`RepositoryKey` は無くなった）
- [x] 2.2 新着の判定を `NotificationStore`（`ThreadChangeDispatcher`）に持たせ、新着のスレッドを、「macOS の通知を出す」で絞る前の値で `onNewThreads` に渡して一覧に知らせる（D2）。確認: 偽の `PollerFactory` と偽の notifier でテストを足して通す: (a) アカウントの最初の成功した取得では呼ばれない、(b) 次の取得で新しいスレッドが来ると、そのスレッドで呼ばれる、(c) `updated_at` が進んだスレッドで呼ばれる、(d) 「macOS の通知を出す」がオフでも呼ばれる、(e) スレッドを一覧から外した後に同じ `updated_at` で戻ったスレッドでは呼ばれない、(f) 再開の後の最初の取得では呼ばれない。既存の `SystemNotificationTests` と `SystemNotifierSettingsTests` が通る。結果: テストは `NotificationStoreNewThreadsTests` に置いた。review-loop の修正（6.1・6.2）で今の形に変えた
- [x] 2.3 `AppDelegate` で `ListExpansion` を作り、`onNewThreads` を `expand` に、`accountStore.onStateChange` を `retain`（「無効」以外のアカウント）につなぎ、`MewbellApp` から `MenuBarContentView` に渡す（D1〜D3）。テスト用ホストとプレビューでも `ListExpansion` を作る。確認: ビルドが通り、既存のテストが通る。結果: `AppDelegate.init` が swiftlint の長さの上限を超えたので、設定のコールバックのつなぎを `connectSettings()` に分けた

## 3. 見出しの開閉（UI）

- [x] 3.1 `AccountSectionView` の見出しに開閉のボタンを足す。折りたたんだときはリポジトリのグループと「No unread notifications」を隠し、取得の状態・操作の失敗・トークンを取れないときの案内は出し続ける。折りたたんでいて未読があるときは件数を出す。「すべて既読」は別のボタンのまま（D5）。確認: プレビューに「開いたアカウント」「折りたたんだアカウント（件数あり）」「折りたたんだアカウントの取得の失敗」を足して見る。山形のツールチップと、ボタンのアクセシビリティの値（`Collapsed` / `Expanded`）と説明が変わることをプレビューで見る（D5）。結果: 見出しは `山形・トークンの状態・ユーザー名…` の順にし、山形の幅をスレッドの行のアイコン（16）に揃えた。字下げ 22 は変えていない。プレビューは描けないので、手元で起動して未読 0 件のアカウントで、開閉、折りたたむと「No unread notifications」だけが隠れて取得の状態は残ること、ポップオーバーを閉じて開き直しても折りたたんだままであることを画面で見た
- [x] 3.2 リポジトリの見出しを開閉のボタンにし、折りたたんだときはスレッドの行を隠して件数を出す。開閉のアニメーションは「視差効果を減らす」がオンなら付けない（D5）。確認: プレビューに「折りたたんだリポジトリと開いたリポジトリが並ぶアカウント」を足して見る。ビルドが通る。結果: `RepositoryGroupView` は `UI/RepositoryGroupView.swift` に分け、「Collapsed」のプレビューもそこに置いた。見出しの共有の部品（`DisclosureButton`・`DisclosureChevron`・`CollapsedCount` など）は `UI/DisclosureButton.swift` に置いた。リポジトリの開閉は未読が要るので 4.3 で確かめる。review-loop の修正（6.1・6.2）で今の形に変えた

## 4. 最終確認

- [x] 4.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [x] 4.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 4.3 手元で起動して確認した: (a) Pull request と Issue の行に `#番号` が出て、クリックで開くページの番号と一致する。Release などの行には出ない、(b) リポジトリとアカウントを折りたたむと行が隠れて件数が出て、メニューバーの件数は変わらない、(c) ポップオーバーを閉じて開き直しても折りたたんだまま、(d) 再起動するとすべて開いている、(e) 折りたたんだリポジトリに新着を作ると、そのリポジトリとアカウントが開き、ほかの折りたたんだリポジトリは閉じたまま、(f) `defaults read com.codingfeline.mewbell` に折りたたみの状態が無い、(g) 見出しの山形にマウスを載せると `Collapse <user> (<host>)` のツールチップが出て、トークンの状態のアイコン・active の印にマウスを載せるとそれぞれのツールチップ（`Ready` など）が出る、(h) トークンを取れないアカウント・スコープ不足で止まったアカウントには山形が出ない、(i) 畳んだアカウントでも操作の失敗の表示が出たまま、(j) VoiceOver で見出しの中身（ユーザー名、ホスト、トークンの状態）に続けて `Collapsed` / `Expanded` と説明が読まれ、件数は「N unread」と読まれる、(k) 「視差効果を減らす」をオンにすると開閉にアニメーションが付かない、(l) gh からログアウトしてログインし直すと、畳んだアカウントが開いて戻る、(m) アカウントを無効にして有効に戻すと、畳んでいたアカウントが開いて戻る、(n) gh の設定ディレクトリの上書きを変えて戻しても（確認中を挟んでも）、畳んだアカウントは畳んだまま、(o) リポジトリを畳んだまま全部既読にし、参加のみを切り替えて戻すと、そのリポジトリは畳んだまま戻る
- [x] 4.4 README の現状の説明を更新する（折りたたみと番号の表示）。確認: 差分を読み、spec と食い違いが無い

## 5. 別コンテキストでのレビュー

- [x] 5.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る。結果: 直したもの 4 件（無効でないアカウントの取り出しを `DiscoveryState.enabledStatuses` にまとめた、見出しの開閉のボタンを `DisclosureButton` にまとめた、`RepositoryGroupView` に key でなくアカウントを渡す、`ListExpansion` で変わらないときは書き込まない）。直さなかった候補 6 件は PR 本文に理由を書く
- [ ] 5.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 5.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認を PR 本文に書いた

## 6. review-loop の修正

- [x] 6.1 review-loop の 1 周目の指摘を直す（新着の判定を NotificationStore に移す、番号を取得のときに求める、状態を捨てる規則を `DiscoveryState.retainedAccountIDs` にまとめる、`AccountDisclosure` で畳めるかと件数を 1 か所で決める、共有の部品を `UI/DisclosureButton.swift` に分ける）。確認: `xcodebuild test`・`bash scripts/lint.sh`・`npx openspec validate --all --strict` が通る。ユーザーが決めたこと（状態は出ている通知の取り下げと同じ規則で捨てる（確認中だけ残す）、消えて戻ったものは畳んだまま、新着の判定を NotificationStore に移す、番号は取得のときに 1 回だけ求める）を design に書いた
- [x] 6.2 review-loop の 2 周目の指摘を直す（tracker と通知の操作を `ThreadChangeDispatcher` にまとめる、`NotificationTracker` を `Polling/` に移す、番号を読み取るときに `let` で決める、通知の取り下げのメソッドを `retractAll(for:)` にまとめる、見出しの書き方を揃える、spec の言葉を既存の仕様に揃える）。確認: `xcodebuild test`・`bash scripts/lint.sh`・`npx openspec validate --all --strict` が通る
- [x] 6.3 描き直しの範囲と重さを直す: 折りたたみの状態をアカウントごとの `AccountExpansion` に分け、グループ分けを `FeedState.repositories` に持たせる（ユーザーの判断）。確認: `ListExpansionTests` の観測の粒度のテスト（ほかのアカウントの開閉で onChange が呼ばれない）と `FeedState.repositories` のテストが通る。`xcodebuild test`・`bash scripts/lint.sh`・`npx openspec validate --all --strict` が通る
