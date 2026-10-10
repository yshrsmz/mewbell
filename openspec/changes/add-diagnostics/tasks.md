# Tasks

## 1. 打ち切りの印（GitHubAPI）

- [x] 1.1 `NotificationsFetchResult.updated` に `truncated: Bool` を足し、`fetchNotifications` で 10 ページ目に `rel="next"` があったときだけ `true` にする（D1）。既存の `.updated` を作る・比べるテストとフェイクを新しい引数に合わせる。確認: `FakeHTTPTransport` でテストを足して通す: (a) 10 ページすべてに `rel="next"` があると、11 ページ目を要求せず `truncated == true`、(b) 10 ページ目に `rel="next"` が無いと `false`、(c) 2 ページで終わると `false`、(d) 10 ページ目までに重複と形の崩れたスレッドがあって 500 件より少なくても、10 ページ目に `rel="next"` があれば `true`。既存の `GitHubAPIClientTests` が通る

## 2. 取得の状態と操作の失敗の記録（Polling）

- [x] 2.1 `Polling/FeedDiagnostics.swift` に `FailureKind`（`FetchFailure`・`ThreadActionResult`・取得の失敗の case から作る。ポップオーバーの 3 分類を返す）、`ThreadActionKind`、`ActionFailure`、`TimedFailure`、`PollIntervalInfo`、`FeedDiagnostics` を作り、`FeedState` に `isTruncated`、`actionFailure`、`diagnostics` を既定値付きで足す（D1、D2）。確認: テストを足して通す: (a) `FetchFailure` と `ThreadActionResult` の各 case が期待の `FailureKind` になる（`unexpectedStatus(502)` → `httpStatus(502)` など）、(b) 3 分類が `unauthorized` → 認証エラー、`rateLimited` → レート制限、ほかはそれ以外、(c) `FeedState(phase:threads:)` で作った値の新しい項目が既定値。既存のテストがコードを書き換えずに通る
- [x] 2.2 `AccountPoller` で、打ち切り・次の取得の予定時刻・間隔・スコープ・最後の取得の失敗を記録する。`stop(as:)` では打ち切りと次の予定時刻を消し、最後の取得の失敗は引き継ぐ。トークンを取り直したらスコープを捨てる（D3）。確認: `FakeHTTPTransport` と fake の `sleep`・`now` でテストを足して通す: (a) 10 ページで打ち切った後の `304` で `isTruncated` が `true` のまま、次の `200` が 3 ページで終われば `false`、(b) `X-Poll-Interval: 120` の後、間隔が 120 秒・ヘッダーによるもの、次の予定時刻が 120 秒後。ヘッダーが無いと 60 秒・既定、`30` なら 60 秒・既定、(c) `X-OAuth-Scopes: repo, read:org` でスコープが `{repo, read:org}`、401 の後にトークンを取り直すと捨てられる、(d) `502` の後に成功しても最後の取得の失敗は「HTTP 502」と失敗の時刻のまま、(e) スコープ不足で止まると次の予定時刻は無く、打ち切りは `false`、最後の取得の失敗は残る。結果: `FeedState` を丸ごと比べていた既存の 3 本（`PollingTests`）を、`phase` とスレッドを比べるように直した
- [x] 2.3 `AccountPoller.perform` と `markAllRead` で操作の失敗を記録し、知らせる失敗を「結果が出た後に送った取得の成功」で消す（D3）。確認: テストを足して通す: (a) 既読化が `500` で、`actionFailure` と `diagnostics.lastActionFailure` がどちらも既読・HTTP 500 になり、`phase` と次の予定時刻は変わらない、(b) その後に送った取得が `200` で `actionFailure` が消え、`lastActionFailure` は残る、(c) `304` でも消える（結果: 操作の後の取得は必ず `If-Modified-Since` なしになり `304` は返らないので、テストでは再現できない。消す処理は `200` と同じ分岐にある）、(d) `pausedMethod` で取得を止めている間に Done が `401` になり、その後に止めていた取得が `200` を返しても `actionFailure` は残る、(e) すべて既読がレート制限の `403` で、すべて既読・レート制限が記録される、(f) トークンが無くて送らなかった既読化は「トークンを持っていない」で記録される、(g) スコープ不足で止まっているときの既読化と、取得できていないときのすべて既読は記録されない、(h) 成功（`205` / `204` / `202`）は記録されない、(i) 2 回続けて失敗すると後の失敗で置き換わる、(j) `stop(as:)` で `actionFailure` が消える。結果: トークンが無いすべて既読で更新が出ないことを確かめていた既存の `neitherSendsNorClearsWithoutAToken` を、「トークンを持っていない」が記録されることを確かめるように直した
- [x] 2.4 `NotificationStore.restart` と、無効にして有効に戻したときに作り直したポーラーの `FeedState` が、打ち切り・操作の失敗・診断の値を持たないことを確かめる。確認: 偽の `PollerFactory` でテストを足して通す: (a) `actionFailure` と `isTruncated` を持った `alice` を `restart` すると、`feeds[alice]` は `.loading` で新しい項目が既定値、(b) `SystemNotifier.feedChanged` は診断の値だけが変わった更新で `add` も `remove` もしない

## 3. gh の検出の結果の記録（GhCLI / Accounts）

- [x] 3.1 `GhLocator.locate` が `GhLocation`（実体の `url` と見つけ方 `override` / `standardLocation` / `loginShell`）を返すようにし、`GhConfigDirectory.resolve` が `Resolved`（`url` と決め方 `override` / `ghConfigDir` / `xdgConfigHome` / `default`）を返すようにする（D4）。候補の順序と検証は変えない。確認: 既存の `GhLocatorTests` を新しい戻り値に合わせて通し、テストを足して通す: (a) 上書き・既定の場所・ログインシェルのそれぞれで見つけ方が合う、(b) `GH_CONFIG_DIR`・`XDG_CONFIG_HOME`・どちらも無いときの決め方が合う、(c) 空文字の `GH_CONFIG_DIR` は使わず次の候補になる（今と同じ）
- [x] 3.2 `GhDiagnostics` を作り、`AccountDiscovery` が読み直しのたびに `lastGhDiagnostics` を書き直す。`verifiedVersion` を持ち、確かめ済みのときは `gh --version` を実行せずにそれを使う。`AccountDiscovering` に `ghDiagnostics()` を足し、`FakeDiscovery` にも実装する（D4）。確認: `FakeProcessRunner` でテストを足して通す: (a) 既定の場所の gh で、パス・見つけ方・バージョン `2.62.0`・設定ディレクトリと決め方が記録される、(b) 2 回目の読み直しで `gh --version` が実行されず、バージョンは残る、(c) gh が見つからなくなると、パスとバージョンが `nil` になる（前の値が残らない）、(d) 古いバージョン（`2.39.0`）でも記録され、全体の状態は今までどおり `.ghOutdated`、(e) 上書きした設定ディレクトリが使えないとき、設定ディレクトリは `nil`、(f) 設定ディレクトリを上書きすると決め方が `override`、(g) `GhDiagnostics` の値に `gh --version` の出力の文字列（日付の部分など）が含まれない。既存の `AccountDiscoveryTests` と `AccountDiscoverySettingsTests` が通る
- [x] 3.3 `AccountStore` に `@Observable` な `gh: GhDiagnostics` を足し、読み直し（続けて要求された分を含む）が終わるたびに `discovery.ghDiagnostics()` を読んで入れる（D4）。確認: `FakeDiscovery` でテストを足して通す: (a) 読み直しの後に `gh` が fake の値になる、(b) 設定ディレクトリを変えた後の読み直しで値が変わる、(c) `gh` を読むだけでは `reload` が呼ばれない

## 4. Diagnostics の中身（Diagnostics）

- [x] 4.1 `Diagnostics/DiagnosticsReport.swift` を作り、`GhDiagnostics`、`DiscoveryState`、`feeds`、アカウントごとの設定、`now`、Mewbell と macOS のバージョンから節と行を作る。`plainText` は ISO 8601（UTC）の時刻で `ラベル: 値` を並べ、`Redaction.redactTokens(in:)` を通す（D5）。確認: テストを足して通す: (a) 取得できている `alice`（間隔 60 秒、スコープ 2 つ、3 件）の行が spec のシナリオどおり、(b) 無効の `bob` はトークンの状態が「無効」で、取得の項目はポーリングしていない表示、(c) 打ち切りと最後の操作の失敗（Done、HTTP 500、時刻）が出る、(d) 分からない値（gh が見つからないときのバージョン）が分からない表示になる、(e) 上書きのパスに `ghp_` で始まる文字列があると、`plainText` では伏せ字になる、(f) スレッドの件名、`https://api.github.com` などの API の URL、`test-token` がどの行にも `plainText` にも含まれない（件名とトークンらしい値を入れたフィクスチャで確かめる）

## 5. UI

- [x] 5.1 `DiagnosticsSettingsView` を作り、`SettingsView` に 4 つ目のタブとして足す。`SettingsView` と `MewbellApp` の `Settings` シーンに `NotificationStore` を渡す。相対時刻は `TimelineView` で進める。Copy で `plainText` を `NSPasteboard.general` に入れる（D7）。確認: ビルドが通り、プレビューに「アカウント 3 つ（取得できた・無効・認証エラー）」「gh が見つからない」を並べて見る。タブの順序が General、Accounts、gh、Diagnostics であることをプレビューで見る
- [x] 5.2 `FeedStatusView` に打ち切りの表示を足し、`MarkAllReadButton` の確認の表示・ツールチップ・アクセシビリティのラベルを `participatingOnly || isTruncated` で決める（D7）。確認: プレビューに「打ち切った一覧」「打ち切った一覧の確認中」を足して見る。ボタンの文とラベルを決める処理を関数にしてテストを足して通す: (a) 打ち切っていなくて参加のみでない 3 件は `Mark 3 as read?`、(b) 打ち切った 500 件は `Mark all as read?` で、ツールチップに一覧に出ていない未読も既読になることが入る、(c) 参加のみは今までどおり。既存の確認を元に戻す条件のテストが通る
- [x] 5.3 `ActionFailureView` を作り、`AccountSectionView` で `feed.actionFailure` があるときに出す。文は操作（既読・Done・すべて既読）と 3 分類で決め、認証エラーには `CommandRow(command: "gh auth login --hostname <host>")` を添える（D7）。確認: 文を決める処理のテストを足して通す: (a) Done・HTTP 500 で、Done にできなかったことと次の取得で戻ることが入り、`500` は入らない、(b) 既読・認証エラーで、`gh auth login --hostname github.com` のコマンドが付く、(c) すべて既読・レート制限でレート制限と分かる文になる。プレビューに 3 つを並べて見る
- [x] 5.4 README の現状の説明を更新する（Diagnostics タブの項目とコピー、操作の失敗の表示、500 件で打ち切ったときの表示とすべて既読）。確認: 差分を読み、CLAUDE.md と `.claude/rules/security.md` の約束（API の URL やトークンを出さない）と食い違いが無い

## 6. 最終確認

- [x] 6.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [x] 6.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 6.3 手元で起動して確認した: (a) 設定ウィンドウに Diagnostics タブがあり、gh のパス・見つけ方・バージョン・設定ディレクトリ・決め方が出る、(b) アカウントごとの最後に取得できた時刻と次の取得の予定時刻が、開いたまま取得のたびに進む、(c) Copy で貼り付けたテキストに、トークン・API の URL・スレッドの件名が無い、(d) 通信を切った状態（Wi-Fi をオフ）でスレッドを既読にすると、区画に既読にできなかったことが出て、通信を戻した後の取得で消え、スレッドが一覧に戻る。Diagnostics には最後の操作の失敗が残る、(e) Diagnostics タブを開いても `log show` に `gh` の実行と `GET /notifications` が増えない（開く前後で比べる）。500 件の打ち切りは手元で再現できないので、5.2 のプレビューとテストで代える

## 7. 別コンテキストでのレビュー

- [ ] 7.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 7.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 7.2 をやり直す。確認: 指摘の件数と対応結果、セキュリティ上の確認を PR 本文に書いた
