# Tasks

## 1. イベントのモデルと決定の規則（GitHubAPI）

- [x] 1.1 `ThreadEvent`（`Kind` の 14 種類と実行者）と、Timeline の項目の最小限の DTO（`event`・`created_at`・`submitted_at`・`state`・`actor.login`・`user.login`・`committer.date` だけ。`body` は載せない）を足す。`GhIdentifier.isValidActor`（`isValidUser`、または `[bot]` を除いた値が `isValidUser`）を足す。確認: ユニットテストで `dependabot[bot]`・`Copilot` を受け入れ、`-x`・`a[bot]x`・`[bot]`・空文字を拒否する。形の崩れた項目は 1 件ずつ読み飛ばし、知らない `event` は DTO には残るが候補にならない
- [x] 1.2 `ThreadEventResolver` で spec「スレッドのイベントの決定」を実装する（候補の表、作成日時 + 60 秒より後かつ近さの幅（`updated_at` の −180 秒〜+60 秒）、いちばん近い候補と同じ近さのときは後ろのもの、`closed` の 60 秒前までの `merged` で Merged、Opened の条件、「無い」、実行者の検証）。確認: spec の Scenario（コメント、マージ、いちばん近い候補を選ぶ、遠い候補は使わない、updated_at の後の出来事、開かれた Pull request、候補にしないイベントだけ、ボット、`actor: null`）をユニットテストで確かめる。テストの JSON は `cli/cli` と `yshrsmz/since-android` で確かめた形（design「Context」）に合わせる
- [x] 1.3 `SubjectState` と Issue のレスポンスの DTO で spec「スレッドの状態の決定」を実装する。確認: Scenario（マージした Pull request、対応しないで閉じた Issue、下書きの Pull request）に加え、閉じた Pull request・開いた Issue・`state_reason: completed` と `null`・知らない `state` のユニットテスト
- [x] 1.4 `LinkHeader.lastURL(in:)` を足す（`nextURL` と同じ読み方）。確認: `rel="next"` と `rel="last"` が並ぶヘッダー、`rel="last"` だけ、無いときのユニットテスト

## 2. イベントの取得のリクエスト（GitHubAPIClient）

- [x] 2.1 `GitHubAPIClient.fetchEvent(for:endpoints:token:)` を足す。Issue と Timeline の 1 ページ目、`rel="last"` があれば最後のページ、候補が無ければその前のページ（最大 3 ページ）を取り、spec「スレッドのイベントの取得のリクエスト」の状態コードの扱いで `.found` / `.none` / `.unauthorized` / `.rateLimited` / `.failed` を返す。レート制限の判定は `fetchNotifications` と共通の関数にする。確認: `FakeHTTPTransport` で、200（1 ページ・5 ページ）、404 / 410、401、レート制限の 403 と 429、そのほかの 403 と 422、502、リダイレクト、形の崩れたボディをそれぞれ確かめる
- [x] 2.2 セキュリティのテストを足す: (a) URL は `subject.url` ではなく検証済みのリポジトリ名と番号から組み立てる（`subject.url` の `owner` の大文字小文字が違っても、送り先はスレッドのリポジトリ）、(b) 番号を持たないスレッド（Release・Commit・別のホストの `subject.url`）には何も送らない、(c) `rel="last"` が別のホスト・`http` を指すときは送らずに一時的な失敗、(d) すべてのリクエストにそのアカウントのトークンだけが付く、(e) GHES と `*.ghe.com` の API ベースで正しいパスになる、(f) ログにボディを出していないことをコードで確かめる（`Logger` の呼び出しを読む）。確認: テストが通る

## 3. ポーラーでの取得とキャッシュ（Polling）

- [x] 3.1 `ThreadEventCache`（キャッシュ、`pausedUntil`、前に知らせた一覧、`attach`、待っているスレッドの選び方）を値型で足す。確認: ユニットテストで、ID と `updated_at` が一致するときだけ付く、`updated_at` が進んだら待っているに戻る、一覧に無い ID を捨てる、「無い」は取り直さない、一時的な失敗は待っているのまま、番号を持たないスレッドは選ばない、更新日時の新しい順に上限まで選ぶ
- [x] 3.2 `AccountPoller` に、新着のイベントを知らせる前に取る処理（`previous` があるときだけ、最大 10 件、同時 4 件、打ち切り 20 秒。打ち切りの時間は引数で差し替えられる）を足す。確認: Scenario「新着のイベントを取ってから知らせる」「最初の一覧はイベントを待たずに知らせる」「新着が多い」を、`onUpdate` に届いた状態の列で確かめる。打ち切りは async で止める fake（`pausedMethod` と同じやり方）で確かめる
- [x] 3.3 `AccountPoller` に、知らせた後・待ち始める前に待っているスレッドを最大 30 件取って知らせ直す処理を足す（`200` と `304` の両方）。今の `state.threads` に付けるので、取っている間に外したスレッドは戻らない。確認: Scenario「変わっていないスレッドは取り直さない」「updated_at が進んだら取り直す」「イベントを取っている間に既読にした」をテストで確かめる
- [x] 3.4 失敗とレート制限の扱い: イベントの取得の結果で `state.phase`・`consecutiveFailures`・`recorder`（最後の失敗・打ち切り・間隔）を変えない。レート制限なら `pausedUntil` まで取らない。トークンが無ければ取らない。`stop(as:)` でキャッシュを空にする。止められた後に返った結果を捨てる。確認: Scenario「イベントの取得の失敗は取得の状態を変えない」「イベントの取得のレート制限」「止まったら捨てる」と、トークンが無いときに送らないことをテストで確かめる
- [x] 3.5 イベントを付けて知らせ直しても macOS の通知が出し直されないこと、新着の通知にはイベントが入ることを、`NotificationStore` と `FakeUserNotificationCenter` を使ったテストで確かめる

## 4. 表示（UI と macOS の通知）

- [x] 4.1 `ThreadEventText`（イベント名と ` by <ログイン名>`）を足し、`ThreadRow` の 2 行目の番号と理由の間に出す。プレビューにイベントの付いた行・実行者の無い行を足す。確認: 文言のユニットテスト（14 種類と実行者なし）と、プレビューで `#42 · Closed by alice · Watching · 3m` の並びを見る
- [x] 4.2 `ThreadRow` の種類のアイコンを種類と状態で決める（design「型と置き場所」の記号と色の案。macOS 26 の SF Symbols にあるかを確かめる）。`accessibilityLabel` に種類と状態を入れる。確認: 記号・色・ラベルを決める関数のユニットテスト（状態ごとに記号が違うこと、状態が無いときは今の記号）と、プレビューにすべての状態の行を並べてライトとダークで見る
- [x] 4.3 `ThreadNotificationContent` の本文を、イベントがあれば `<イベント> · <理由> · <アカウント>` にする。確認: Scenario「イベントが付いたスレッド」「Pull request のレビュー依頼」のテストと、本文・`userInfo` にトークン・API の URL が入らないことのテスト

## 5. 仕上げ

- [x] 5.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [x] 5.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 5.3 手元で起動して確認した: (a) `bash scripts/run.sh` で起動し、一覧の Issue と Pull request の行にイベントと状態のアイコンが出る（Web の Timeline と見比べる）、(b) Release などの行は今までどおり、(c) 自分のリポジトリの Issue にもう 1 つのアカウントか Web でコメントし、届いた macOS の通知の本文に `Commented by <ログイン名>` が入る、(d) ログ（PID で絞る）にトークンと Timeline のボディが出ていない。結果をここに書く 結果: (a) 手元の github.com アカウント（未読 18 件）で、`nuxt/cli#37` が `Commented by Jorgagu`、`yshrsmz/since-android` の Renovate の Pull request が `Commented by github-actions[bot]`、`#784` が `Commented by sincetimer-android-app[bot]`（design「Context」で Timeline と見比べたとおり）と出て、マージ済みの `#784` は紫のマージのアイコン、open の Pull request と Issue は緑のアイコンになった、(b) この時点の未読に Release などは無く、画面では見ていない（`ThreadIconTests` と一時的なテストの画像で、状態の無い行と Release の行が今までどおりなのを見た）、(c) 未確認: コメントを書く操作は外に出るのでユーザーに頼む、(d) ログ（PID で絞った `com.codingfeline.mewbell`）は可変の値がすべて `<private>` で、トークンもボディも出ていない
- [x] 5.4 README に一覧の行や通知の本文の説明があれば、変更に合わせて直す。確認: 差分を読み、spec と食い違いが無い（直すものが無ければそう書く） 結果: 「通知の取得」の節に、行に出すイベントと状態のアイコン、通知の本文、近い出来事が無いときは出さないこと、リクエストの数を足した

## 6. 別コンテキストでのレビュー

- [ ] 6.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 6.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 6.2 をやり直す。確認: 指摘の件数と対応結果を PR 本文に書いた
