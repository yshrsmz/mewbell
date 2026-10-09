# Proposal

## Why

マイルストーン **M2「通知取得」** に属する change。M1 で gh にログイン済みのアカウントとそのトークンをメモリに持てるようになったが、まだ GitHub に問い合わせていないので、ポップオーバーにはアカウントの一覧しか出ない。Mewbell の目的である「複数アカウントの通知をまとめて見る」ために、アカウントごとに Notifications API をポーリングし、未読の通知をアカウント → リポジトリの 2 段で一覧にする。トークンを初めてネットワークに送る change なので、送り先の制限・リダイレクト・ページネーションでトークンが他のホストや他のアカウントへ漏れない仕組みもここで作る。

## What Changes

- アカウントのホストから API ベース URL を導く（`github.com` → `https://api.github.com`、`*.ghe.com` → `https://api.<host>`、それ以外 → `https://<host>/api/v3`）。Web のベース URL（`https://<host>`）も同じ規則の中で決める
- GitHub API クライアントを作る。トークンはリクエストごとに `Authorization` ヘッダーへ付け、共有のヘッダーには入れない。送信前にリクエスト先がアカウントの API ベースと同じオリジン（スキーム・ホスト・ポート）であることを確かめる。リダイレクトはすべて拒否し、`URLCache`・Cookie を使わない
- `GET /notifications`（未読だけ、`participating=false`、`per_page=50`）を取得し、`Link` ヘッダーの `rel="next"` を同じオリジン検査を通してたどる（上限のページ数を設ける）。200 / 304 / 401 / 403 / 422 とそれ以外の失敗をそれぞれ扱う
- アカウントごとにポーリングする。`Last-Modified` を覚えて次から `If-Modified-Since` を送り、304 なら一覧を変えない。`X-Poll-Interval`（下限 60 秒、無ければ 60 秒）より短い間隔では問い合わせない。403 のレート制限や通信の失敗のときは、`Retry-After`・`X-RateLimit-Reset`・段階的に延ばす待ち時間に従う
- 最初のレスポンスの `X-OAuth-Scopes` に `repo` も `notifications` も無ければ「スコープ不足」にしてそのアカウントのポーリングを止め、`gh auth refresh --hostname <host> --scopes repo` を案内する（アクティブでないアカウントには先に `gh auth switch --hostname <host> --user <user>` を案内する）
- API が 401 を返したら、そのアカウントのトークンを捨てて gh から 1 回だけ取り直す。取り直しても 401 なら「認証エラー」にして止め、`gh auth login --hostname <host>` を案内する。止めたアカウントは、ユーザーが再読み込みを押したときにトークンを取り直して再開する
- ポップオーバーの一覧を、アカウント（見出しに状態）→ リポジトリ → 通知スレッドの 3 層の表示に変える（グルーピングはアカウント → リポジトリの 2 段）。スレッドの行には種類のアイコン、タイトル、理由（`reason`）、更新日時を出す
- スレッドをクリックするとブラウザで開く。開く URL は API の値をそのまま使わず、`subject.url` のパスとリポジトリ名から Web の URL を組み立て、`https` でホストがアカウントの Web ホストと一致するものだけを開く。組み立てられない種類はリポジトリのページを開く

この change では次のことはしない:

- macOS の通知（UNUserNotificationCenter）、既読化（`PATCH /notifications/threads/{id}`）、メニューバーの未読バッジ（M3）
- Done、すべて既読、`participating` の切替、アカウントの ON/OFF、ポーリング間隔の設定（M4）
- 既読の通知の表示（`all=true`）、コメントへのアンカー付きリンク（`latest_comment_url` を追加で取得すること）

## Capabilities

### New Capabilities

- `github-api`: API ベース URL と Web ベース URL の導出、トークンをリクエストごとに付けること、送信先のオリジン検査、リダイレクトの拒否、キャッシュを使わないこと、`GET /notifications` とページネーション、ステータスコードごとの扱い、`X-OAuth-Scopes` の確認、ヘッダーとボディをログに出さないこと
- `polling`: アカウントごとのポーリングの開始と停止、`If-Modified-Since` / `Last-Modified` / 304、`X-Poll-Interval` に従った間隔、レート制限と通信失敗のときの待ち方、401 のときのトークンの取り直し、スコープ不足・認証エラーで止めることと再開のタイミング

### Modified Capabilities

- `accounts`: 「トークンをメモリにだけ持つ」の「トークンをどこにも送信してはならない」を、「そのアカウントの API ベースにだけ送る」に変える。「読み直しのタイミング」と「不要になったトークンの破棄」に、API が 401 を返したときと、スコープ不足・認証エラーで止まったアカウントをユーザーが再読み込みしたときのトークンの取り直しを足す。通知の取得の状態（スコープ不足・認証エラーなど）はトークンの状態とは分け、`polling` で定める
- `ui`: 「アカウント一覧の表示」を、アカウントごとの状態の下にリポジトリ → スレッドの一覧を出す形に変える。「再読み込みボタン」に、止まっているアカウントのポーリングの再開を足す。スレッドを開く操作と、スコープ不足・認証エラーの案内を ADDED にする

## Impact

- 追加されるコード: `Mewbell/GitHubAPI/`（URL の導出、トランスポート、クライアント、通知のモデル）、`Mewbell/Polling/`（ポーラーと通知の状態）、`Mewbell/UI/` の一覧の View、対応するテスト。`Accounts/` には API ベース URL の導出と、1 アカウントのトークンを取り直す口を足す。`AppDelegate` がポーラーを持ち、アカウントの状態に合わせて起動・停止する
- 外部依存: 追加しない（`URLSession` と `Foundation` だけを使う）
- **トークン: 扱う。** M1 の `CredentialStore` から、リクエストを作るたびに取り出して `Authorization` に付ける。保持はメモリ上の actor だけのままで、永続化しない方針（CLAUDE.md）を守る。401 のときにトークンを捨てる経路が増える
- **gh サブプロセス: 扱う。** 新しい gh コマンドは増やさないが、401 のときと再読み込みのときに既存の `gh auth token` の経路でトークンを取り直す。`.claude/rules/security.md` の「gh サブプロセス」の項目は M1 の実装のまま満たす
- **ネットワーク: 扱う（初めて）。** Mewbell が GitHub / GHE の API に HTTPS でリクエストを送る。`.claude/rules/security.md` の「ネットワーク」の項目がすべて適用される
- **URL を開く処理: 扱う（API 由来）。** 通知のスレッドを開くとき、API のレスポンスから Web の URL を組み立てて開く。`.claude/rules/security.md` の「ブラウザで開く URL」の項目が適用される
- Info.plist・entitlement: 変更しない（ATS の例外を入れない。Sandbox は無効なので network client の entitlement は要らない）
- ドキュメント: README に、取得する通知の範囲（未読・`participating=false`）とポーリングの間隔の説明を足す
