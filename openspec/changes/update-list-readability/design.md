# Design

## Context

ポップオーバーの文字は SwiftUI のテキストスタイルで指定している。macOS では `.caption` / `.caption2` / `.footnote` が 10pt、`.subheadline` が 11pt、`.callout` が 12pt、`.body` と `.headline`（semibold）が 13pt。いまの主な指定は次のとおり（動機は proposal.md の Why）。

| 箇所 | いまの指定 |
|---|---|
| スレッドの件名（`ThreadRow`） | `.body`（既定） |
| スレッドの行の 2 行目（番号・理由・更新日時） | `.caption` + `.secondary` |
| リポジトリの見出し（`RepositoryGroupView`） | `.caption.weight(.semibold)` + `.secondary` |
| アカウントのユーザー名（`AccountSectionView.title`） | `.subheadline.weight(.semibold)` |
| active の印 | `.caption` + `.tint.opacity(0.15)` のカプセル |
| ホスト名とホスト種別、参加のみの印 | `.caption` + `.secondary` |
| 取得の状態（`FeedStatusView`）、操作の失敗（`ActionFailureView`） | `.caption`（一部 `.secondary`） |
| 「Checking gh…」、トークンを取れないときの文 | `.caption` + `.secondary` |
| 見出しの山形（`DisclosureChevron`） | `.caption2.weight(.semibold)` + `.secondary` |
| 折りたたんだときの件数（`CollapsedCount`） | `.caption.monospacedDigit()` + `.secondary` |
| すべて既読の確認の文（`MarkAllReadButton`） | `.caption.weight(.semibold)` |
| 通知が切られているときの案内（`NotificationPermissionBanner`） | `.caption` |

案内画面（`GuidanceView`）とコマンドの行（`CommandRow`）は `.callout`（12pt）以上なので変えない。ポップオーバーの背景はシステムのマテリアル（半透明）で、`.secondary` の文字はその上で後ろの色の影響を受ける。

## Goals / Non-Goals

**Goals:**

- ポップオーバーに 10pt の文字を残さない
- 見出しと補足の区別を、色の薄さだけでなく大きさと太さで付ける

**Non-Goals:**

- コントラスト比を数値（4.5 : 1 など）で保証すること（D3）
- ポップオーバーの背景をマテリアルから不透明な色に変えること
- 設定ウィンドウ、メニューバーのアイコンと件数
- ユーザーが文字の大きさを選べる設定を足すこと

## Decisions

### D1: 大きさはテキストスタイルで指定し、ポイント数を書かない

`.font(.system(size: 11))` のような固定の大きさは使わず、`.subheadline` などのテキストスタイルで指定する。いまのコードの書き方に揃い、macOS が将来テキストスタイルの大きさを変えたり、ユーザーの文字の大きさの設定に追従するようになったりしたときに、そのまま効く。

- 代替案: 共有の型（`ListTypography` など）に書体をまとめる。指定は 10 か所あまりで、ほとんどが 1 行の modifier なので、型を挟むと読む場所が増えるだけになる。採らない。10pt が残っていないことは、ポップオーバーの View のファイルに `.caption` / `.caption2` / `.footnote` が無いことを `grep` で確かめる（tasks）

### D2: 新しい階層

| 箇所 | 変更後 |
|---|---|
| スレッドの件名 | `.body`（変えない） |
| スレッドの行の 2 行目 | `.subheadline` + `.secondary` |
| リポジトリの見出し | `.subheadline.weight(.semibold)`、`.secondary` を外す |
| アカウントのユーザー名 | `.headline`（13pt semibold） |
| active の印 | `.subheadline`（カプセルの塗りは変えない） |
| ホスト名とホスト種別、参加のみの印 | `.subheadline` + `.secondary` |
| 取得の状態、操作の失敗 | `.subheadline`（`.secondary` の付け方は変えない） |
| 「Checking gh…」、トークンを取れないときの文 | `.subheadline` + `.secondary` |
| 見出しの山形 | `.subheadline.weight(.semibold)` + `.secondary` |
| 折りたたんだときの件数 | `.subheadline.monospacedDigit()` + `.secondary` |
| すべて既読の確認の文 | `.subheadline.weight(.semibold)` |
| 通知が切られているときの案内 | `.subheadline` |

アカウントのユーザー名は、いまは件名（13pt）より小さい 11pt で、見出しなのに件名より目立たない。`.headline` にして件名と同じ大きさの太字にし、区画の区切りが分かるようにする。リポジトリの見出しは件名より 1 段小さい 11pt の太字に残し、色だけ標準に戻す（太さと大きさで件名と区別できるので、薄くする必要が無い）。

- 代替案: 補足の情報を `.callout`（12pt）にする。件名（13pt）との差が 1pt になり、行の 1 行目と 2 行目の区別が付きにくくなる。行の高さも増え、一度に見えるスレッドが減る。採らない

### D3: コントラストは数値の目標を置かず、見出しを標準の文字色にする

システムの副次的な文字色（`.secondary`）は、白い背景の上でも 4.5 : 1 を下回る色で（ライトモードの `secondaryLabelColor` は黒の 50%）、ポップオーバーのマテリアルの上では後ろのウィンドウの色でさらに変わる。アプリの側から比を数値で保証することはできないので、次の方針にする。

- 読めないと困る情報（件名、アカウントのユーザー名、リポジトリの見出し、操作の失敗）は標準の文字色にする
- `.secondary` は補足の情報にだけ使い、その場合も 11pt 以上にする（いちばん小さい文字に薄い色を重ねない）
- 文字の色はシステムの色だけにする。「コントラストを上げる」「透明度を下げる」はシステムの色とマテリアルに効くので、それで足りないユーザーはシステムの設定で補える

- 代替案: ポップオーバーに不透明な背景（`.background(.windowBackground)`）を敷く。後ろの色の影響は消えるが、ほかのメニューバーのポップオーバーと見た目が揃わなくなる。採らない
- 代替案: `.secondary` をやめてすべて標準の文字色にする。補足の情報と本文の区別が付かなくなる。採らない

### スレッドと actor の境界

View の modifier を変えるだけで、`@MainActor` の View の中で完結する。actor とネットワーク、ポーリングには触れない。

### テストでの差し替え

SwiftUI の書体はユニットテストから読めないので、ユニットテストは足さない。次で確かめる。

- `grep` で、ポップオーバーの View のファイルに 10pt のテキストスタイルが残っていないこと
- プレビュー（Xcode の RenderPreview、使えなければ一時的な `ImageRenderer` のテスト。コミットしない）で、幅 380pt の中の配置、長いホスト名の省略、件名の 2 行の省略、ホバーのボタンの位置（件名の 1 行目に揃う）
- 手元で起動したポップオーバーのスクリーンショットで、変更の前と同じ条件（ライトモード、後ろが暗いウィンドウ）の文字の大きさとコントラスト比を測って比べる

## セキュリティ

トークン・gh サブプロセス・ネットワーク・URL を開く処理のいずれにも触れない。表示する内容も変えないので、トークンや API の URL を表示しないこと（ui「アカウント一覧の表示」）はそのまま保たれる。`.claude/rules/security.md` の項目で、この change で新しく満たすものは無い。

## Risks / Trade-offs

- [行の高さが増え、一度に見えるスレッドが減る] → 増えるのは 2 行目と見出しの 1pt ずつで、一覧はいまも 480pt でスクロールする。変更の前後のスクリーンショットで、見えるスレッドの数を比べて記録する
- [見出しの行が横にあふれる] → ホスト名は今も `lineLimit(1)` と中央の省略で縮むので、ユーザー名と active の印が大きくなった分はホスト名が省略される。長いホスト名のプレビューで確かめる
- [ホバーのボタンと件名の重なり] → 件名の大きさは変えないので、ボタンの位置と件名を消す範囲（`ThreadActionButtons.titleFade`）は変えずに済む。ホバーのプレビューで確かめる
