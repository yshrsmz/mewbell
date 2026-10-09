# Proposal

## Why

M3 までで、一覧や macOS の通知からスレッドを開けば既読になるようになった。ただ、開かずに片付ける手段が無い。読む必要のないスレッドも 1 つずつブラウザで開くか、Web の受信箱で既読や Done にするしかない。未読がたまったアカウントをまとめて片付けることもできない。

マイルストーン: M4「設定と操作」の前半。M4 は 2 つの change に分ける。この change ではポップオーバーの一覧での操作（既読・Done・すべて既読）を扱う。後半の `add-settings` では、Settings シーン、`participating` の切替、アカウントの ON/OFF、ログイン時起動、gh のパスの上書き、Diagnostics を扱う。

## What Changes

- 一覧のスレッドの行にマウスを載せると、右端に「既読にする」と「Done にする」のボタンが出る。同じ 2 つを行のコンテキストメニュー（右クリック）にも入れる。どちらもブラウザでは開かない
- 「既読にする」は、既存の既読化（`PATCH /notifications/threads/{id}`）を、開かずに行う
- 「Done にする」は `DELETE /notifications/threads/{id}` を送る。Done にしたスレッドは、一覧と macOS の通知からすぐに消す
- アカウントの見出しに「すべて既読」のボタンを置く。1 回目のクリックでボタンが確認の表示（`Mark N as read?`）に変わり、数秒以内にもう一度押したときだけ `PUT /notifications` を送る。`last_read_at` は、そのアカウントの一覧にあるスレッドの `updated_at` の最大値にする（一覧を取った後に届いたスレッドは既読にしない）。成功したら、そのアカウントの一覧と macOS の通知をすぐに空にする
- Done やすべて既読の後の取得は、既読化と同じく `If-Modified-Since` を付けない取得にする。外したスレッドは、操作の後の取得で結果が確定するまで一覧に戻さない
- `SETUP.md` の M4 の行を `add-thread-actions` と `add-settings` の 2 行に分け、README の現状の説明を更新する

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

- `github-api`: スレッドを Done にする `DELETE /notifications/threads/{id}` と、アカウントの通知をすべて既読にする `PUT /notifications` を足す。どちらにも既存のオリジン検査・リダイレクトの拒否が掛かることと、状態コード（`202` / `204` / `205` / `304` / `401` / `403` / `404`）の扱いを書く
- `polling`: 「スレッドの既読化」と同じ規則（一覧からすぐ外す、次の取得を条件なしにする、結果が確定するまで戻さない）を、Done とすべて既読にも掛ける。すべて既読の非同期の処理（`202`）の間も一覧に戻さない
- `notifications`: 「通知の取り下げ」に、Done とすべて既読のときを足す
- `ui`: スレッドの行の操作（ホバーのボタンとコンテキストメニュー）と、アカウントの見出しの「すべて既読」（2 段階の確認）を足す。「未読バッジ」が Done とすべて既読でもすぐに減ることを書く

## Impact

- コード: `Mewbell/GitHubAPI/GitHubAPIClient.swift`（`DELETE` と `PUT` の追加、`send` にリクエストのボディを渡す口）、`Mewbell/Polling/AccountPoller.swift` と `NotificationStore.swift`（既読化の経路を Done とすべて既読に広げる）、`Mewbell/Notifications/SystemNotifier.swift` と `NotificationTracker.swift`（まとめての取り下げ）、`Mewbell/UI/AccountSectionView.swift`（行の操作、見出しのボタン）、テスト、`SETUP.md`、`README.md`
- トークン: 触れる。トークンを付けて送るリクエストに `DELETE /notifications/threads/{id}` と `PUT /notifications` が増える。トークンの取得・保持の仕方は変えず、今までどおりメモリ上の actor にだけ持ち、永続化しない。`PUT` のボディ（`last_read_at` と `read`）にトークンは入らない
- ネットワーク: 触れる。新しいリクエストも `GitHubAPIClient` の 1 か所で組み立て、アカウントの API ベースとのオリジン検査・リダイレクトの拒否・キャッシュなしを同じように掛ける
- URL を開く処理: 触れない（既読・Done・すべて既読はブラウザを開かない。開く経路は M3 のまま）
- gh サブプロセス: 触れない
- 永続化: しない。Done やすべて既読の操作の記録も、メモリにだけ持つ
- 取り消し: Done とすべて既読は GitHub の側で取り消せない。すべて既読は誤操作を防ぐために 2 段階にする。Done は 1 スレッドだけなので確認しない
