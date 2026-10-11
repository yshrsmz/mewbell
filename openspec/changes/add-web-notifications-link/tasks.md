# Tasks

## 1. URL の組み立てと開く処理

- [x] 1.1 `ThreadWebURL.notificationsPage(endpoints:)` を足す（D1）。確認: `ThreadPresentationTests.swift` の `ThreadWebURLTests` にテストを足して通す: (a) `github.com` で `https://github.com/notifications`、(b) `acme.ghe.com` で `https://acme.ghe.com/notifications`、(c) `ghe.example.com` で `https://ghe.example.com/notifications`、(d) どれもクエリを含まず、API ベース URL にならない
- [x] 1.2 `NotificationStore.openWebNotifications(for:)` を足す（D2）。確認: `NotificationStoreOpenTests` にテストを足して通す: (a) 3 件を取得した `alice` で呼ぶと `openURL` に `https://github.com/notifications` が 1 回渡る、(b) 一覧の 3 件は残り、PATCH も PUT も送られない、(c) 「参加しているスレッドだけにする」がオンのアカウントでもクエリの無い URL が渡る、(d) ポーラーの無い（トークンを取得できない）アカウントでも開く。結果: (e) 検証を通らないホスト（`-bad`）では開かないテストも足した。(c) は `preferences` に `participatingOnly: true` を渡した store で確かめた

## 2. 見出しのボタン

- [x] 2.1 `ThreadListActions` に `openWebNotifications` を足し、`AccountSectionView.header` の「すべて既読」の前にボタンを置き、`MenuBarContentView` から `NotificationStore.openWebNotifications` につなぐ（D3）。プレビュー用の `.none` も直す。確認: ビルドが通り、`AccountSectionView.swift` のプレビュー（「Notifications」）で、取得できたアカウント・スコープ不足・認証エラー・トークンを取得できないアカウントのどの見出しにもボタンが出ることを見る。結果: `AccountSectionView.swift` が swiftlint の長さの上限（400 行）を超えたので、ボタンは `UI/OpenWebNotificationsButton.swift` に分けた。プレビューは Xcode の承認が要るので見ていない。ボタンは見出しで条件を付けずに置いている
- [x] 2.2 README の現状の説明に、アカウントの見出しのボタンで Web の通知一覧を開けることを足す。確認: 差分を読み、spec と食い違いが無い

## 3. 最終確認

- [x] 3.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [x] 3.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 3.3 手元で起動して確認した: (a) 各アカウントの見出しのボタンで、そのホストの `/notifications` がブラウザで開く、(b) 押しても一覧のスレッドは消えず、メニューバーの件数も変わらない、(c) ボタンにマウスを載せると `Open notifications on <host>` のツールチップが出る、(d) 畳んだアカウントや止まっているアカウントの見出しにも出る、(e) 長いホスト名でも見出しが崩れない、(f) VoiceOver でボタンのラベルが読まれる。途中経過: github.com のアカウントで (a)（Chrome で `https://github.com/notifications` が開き、GitHub が既定の `?query=is:unread` を付けて表示した）と (c) を確かめた。(b)・(d)・(e)・(f) は手元に該当するアカウントが無いか、自動では確かめられないので残す

## 4. 別コンテキストでのレビュー

- [ ] 4.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 4.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 4.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認を PR 本文に書いた
