# Proposal

## Why

M2（`add-notification-fetch`）で入れた条件付きリクエストのせいで、通知の一覧が古いまま残る。手元では、API の未読は 9 件なのに一覧には 1 件しか出なかった。

GitHub の `GET /notifications` は、`Last-Modified` に未読スレッドの `updated_at` の最新値を返す。`If-Modified-Since` を付けると、この値が変わっていない限り `304` が返る。そのため、次の 2 つが起きても一覧が変わらない。

- 最新値より古い `updated_at` のスレッドが、後から受信箱に入る。Watch 経由（`reason: subscribed`）の通知は、イベントの時刻より遅れて入ることがある。手元で欠けていた 8 件はどれも `subscribed` で、`last_read_at` は空だった
- Web や別のクライアントでスレッドを既読・Done にしても、最新値が上がらないので一覧から消えない

`304` が返り続ける限り、ずれは直らない。

マイルストーン: M2 の不具合修正。M2 の PR（#3）がまだマージされていないので、その上に積む。

## What Changes

- ポーリングは、前回の条件なしの取得（`If-Modified-Since` を付けない取得）から 5 分たっていたら、`If-Modified-Since` を付けずに取得する。それ以外は今までどおり `If-Modified-Since` を付ける
- 再読み込みボタンを押したら、各アカウントの次の取得を条件なしにする。取得を間隔より早めることはしない（`X-Poll-Interval` と下限 60 秒は今までどおり守る）
- CLAUDE.md の「ポーリングは API の指示に従う」に、定期的に条件なしで取り直すことを書き足す

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- `polling`: 「条件付きリクエスト」に、5 分ごとの条件なしの取得と、再読み込みの後の条件なしの取得を足す
- `ui`: 「再読み込みボタン」で、各アカウントの次の取得を条件なしにすることを足す

## Impact

- コード: `Mewbell/Polling/AccountPoller.swift`（条件なしにするかどうかの判断）、`Mewbell/Polling/NotificationStore.swift`（再読み込みからの指示）、`Mewbell/App/MenuBarContentView.swift`（再読み込みボタン）、テスト
- ネットワーク: 触れる。送るリクエストは同じ `GET /notifications` で、`If-Modified-Since` の有無だけが変わる。送り先・トークンの付け方・オリジン検査は変えない（security.md の「ネットワーク」の約束はそのまま）
- トークン・gh サブプロセス・URL を開く処理: 触れない。トークンは今までどおりメモリにだけ持ち、永続化しない
- API の利用量: リクエストの回数は増えない。認証付きの条件付きリクエストへの `304` はレート制限に数えられないが、5 分に 1 回の条件なしの取得は数えられるので、アカウントあたり 1 時間に最大 12 回（ページがあればその分）増える。上限の 5,000 回に比べて小さい
