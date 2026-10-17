# Tasks

## 1. 開閉のボタンの並び

- [x] 1.1 `DisclosureButton` を `DisclosureButton<Icon: View, Label: View>` にし、`@ViewBuilder let icon: Icon` を足す。山形とアイコンは中央揃えの `HStack` に、`label` と件数は `.firstTextBaseline` の `HStack` に入れる。畳めるときと畳めないときを同じ並びにする。`Icon == EmptyView` の extension に `icon` を取らないイニシャライザを置き、リポジトリの見出しの呼び出しはそのままにする（design D1・D2）。確認: `RepositoryGroupView` の呼び出しを変えずにビルドが通る
- [x] 1.2 `DisclosureButtonCountTests` の型の書き方を、引数が 2 つの generic に合わせて直す。`DisclosureButtonHeightTests` に、アカウントの見出しと同じ組み合わせ（記号のアイコン、`.headline` の文字と `.subheadline` の文字）を渡す場合を足す（design D3）。確認: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test -only-testing:MewbellTests/DisclosureButtonHeightTests -only-testing:MewbellTests/DisclosureButtonCountTests` が通り、結果のスイート数が 2 になる

## 2. アカウントの見出し

- [x] 2.1 `AccountHeadingView` の `tokenIcon` を `title` から外し、`.frame(width: ListLayout.iconColumnWidth)` を付けたまま `DisclosureButton` の `icon` に渡す。`title` は文字だけの `HStack(alignment: .firstTextBaseline)` にする。`.help` と `.accessibilityLabel` はアイコンに付けたままにする（design D1）。確認: ビルドが通り、`AccountHeadingView` の `title` にトークンの状態のアイコンが残っていない

## 3. 確認

- [x] 3.1 ビルドとテストが通ることを確かめる。確認: `bash scripts/format.sh` の後に `bash scripts/lint.sh`、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test`、`MEWBELL_WARNINGS_AS_ERRORS=YES` の Debug と Release のビルド、`pnpm exec openspec validate fix-account-heading-baseline --strict` が通る
- [x] 3.2 `bash scripts/run.sh` で起動し、ポップオーバーの範囲だけを撮って測る（proposal の Why と同じ方法）。確認: アカウントの見出しのユーザー名・アクティブの印・ホスト名の下端（ベースライン）が同じ行にあり、山形とトークンの状態のアイコンの中心が文字の中心から 0.5pt 以内に残る。アカウントの見出しを畳んだときの件数も同じベースラインにある。リポジトリの見出しの山形とリポジトリ名の位置が、変更前（山形の中心 262.5px、リポジトリ名の大文字の中心 261.5px からの差）と変わらない。見出しの高さが 24pt のまま。結果（倍率 2、px）: ユーザー名・アクティブの印・ホスト名の最後にインクのある行は、変更前の 164・161・161 から、3 つとも 162 になった。畳んだときの件数も 162。山形の中心は 154.5（畳むと 154.0）、トークンの状態のアイコンの中心は 153.5 で変更前と同じ。文字の中心は 153〜154。リポジトリの見出しは山形 262.5、リポジトリ名 261.5 で変わらない。見出しの下の「Updated」の行の位置も変わらない（高さは `DisclosureButtonHeightTests` でも確かめている）。`OneLineText` の中の `ViewThatFits` と `ZStack` はベースラインを外へ伝えていた（design の Risks）
- [ ] 3.3 手元で確かめる（ユーザーが行う）。確認: 参加しているスレッドだけを出す設定で、参加のみの印がホスト名と同じベースラインに出る。トークンの取得中（起動の直後か、アカウントを無効から有効に戻した直後）に、取得中の印が見出しの縦の中央に出て、記号に切り替わるときに上下に動かない。VoiceOver で、アカウントの見出しがトークンの状態の名前（`Ready` など）、ユーザー名の順に読まれ、トークンの状態のアイコンにマウスを載せるとツールチップが出る

## 4. レビュー

- [x] 4.1 別コンテキストの opus サブエージェントで `simplify` を実行する（`.claude/rules/review-process.md`）。変更を確かめてから取り込み、テストが通ることを確かめる。結果: 変更なし。簡素化の指摘 3 件（`Icon == EmptyView` のイニシャライザが引数を写していること、揃え方の理由のコメントが 3 か所にあること、新しい高さのテストが既存のテストに近いこと）は、design D1 の形・`HoverActionButtons` との対称・それぞれのコメントの役割の違い・守る経路の違いから見送った
- [x] 4.2 別コンテキストの opus サブエージェントで `code-review` を effort medium で実行する。指摘ごとに直すか直さないかを決め、直さないものは理由を PR 本文に書く。結果: 正しさのバグなし。低 3 件。新しい高さのテストが本物の見出しより低い組み合わせしか並べていない指摘は、アクティブの印（上下に余白のあるバッジ）と参加のみの印を足して直した。`Icon == EmptyView` のイニシャライザが既定値を写している指摘と、揃え方の理由のコメントが 3 か所にある指摘は、4.1 と同じ理由で直さない（PR 本文に書く）
- [x] 4.3 ロジックの変更を含む修正が多ければ、4.2 を新しいサブエージェントでもう一度実行する。結果: 直したのはテストの並べる中身だけでロジックの変更が無いので不要

## Workflow follow-up

- レビューを終えたら `/opsx:archive fix-account-heading-baseline` で archive し、PR を ready にする
