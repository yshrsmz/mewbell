# Tasks

## 1. メニューバーのアイコン

- [x] 1.1 `MenuBarIcon.image(badge:)` を `Mewbell/UI/MenuBarLabel.swift` に足し、`MenuBarLabel` を `Image(nsImage:)` を返す形に替える（design.md D1〜D4）。0 件はテンプレート画像の猫、件数ありは緑の猫と `labelColor` の件数を 1 枚に描いた非テンプレート画像にする。`accessibilityLabel` は今のまま。確認: まず手元で起動し、未読があるときにメニューバーに緑の猫と件数が並んで出ること、メニューバーの外観（ライト・ダーク）に合わせて件数の文字の色が変わること（D2 の前提）を確かめる。崩れていたら design.md の Risks の代わりの手を取り、design.md を直す
- [x] 1.2 `MenuBarIcon` のユニットテストを `MewbellTests/SystemNotificationTests.swift` の `UnreadBadgeTests` の近くに足す（D6）。確認: (a) `nil` で `isTemplate == true`、件数ありで `false`、(b) `"1"` より `"99+"` が広く、どちらも猫だけより広い、(c) 件数ありの画像をライトとダークの外観でビットマップに描くと、緑の画素があり、文字の部分にライトでは暗い画素、ダークでは明るい画素がある。`xcodebuild test` で通る

## 2. 最終確認

- [x] 2.1 ビルドが通る: `MEWBELL_WARNINGS_AS_ERRORS=YES` を付けた Debug と Release の `xcodebuild build` が成功する
- [x] 2.2 テストが通る: `xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` と `bash scripts/lint.sh` が成功し、`npx openspec validate --all --strict` も通る
- [ ] 2.3 手元で起動して確認した: (a) 未読が 0 件のとき、猫だけがほかのアイコンと同じ色で出る、(b) 未読があるとき、緑の猫の右に件数が出る、(c) 最後の 1 件を既読にすると数字が消え、猫の色が戻る、(d) ライトとダークの外観で、緑の猫と件数の文字が見える、(e) 0 件と件数ありで猫の大きさと位置が変わらない。途中経過: (a) は確認した。(b) と (e) は件数を一時的に `+5` したビルドで確認した（緑の猫の右に `5`、猫の大きさと位置は 0 件と同じ）。(d) はメニューバーが暗い状態で、システムの外観をライトとダークに切り替えて確認した（件数の文字はどちらもメニューバーのほかのアイコンと同じ白）。メニューバーが明るい状態と (c) は、まだ確かめていない

## 3. 別コンテキストでのレビュー

- [ ] 3.1 新しいコンテキストの opus サブエージェントで `simplify` スキルを実行し、作業ツリーに入った変更を確かめる。確認: `bash scripts/lint.sh` と `xcodebuild test` が引き続き通る
- [ ] 3.2 別の新しいコンテキストの opus サブエージェントで `code-review` スキルを effort `medium` で実行し、指摘ごとに「直した / 直さない（理由）」を決めて対応する。ロジックに手を入れたら 3.2 をやり直す。確認: 指摘の件数と対応結果を PR 本文に書いた
