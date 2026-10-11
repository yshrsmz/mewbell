# Design

## Context

ポップオーバーの文字は SwiftUI のテキストスタイルで指定している。macOS では `.caption` / `.caption2` / `.footnote` が 10pt、`.subheadline` が 11pt、`.callout` が 12pt、`.body` と `.headline`（太字）が 13pt。いまの主な指定は次のとおり（動機は proposal.md の Why）。

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

ポップオーバーの幅 380pt は `MenuBarContentView` の今の幅で、これまでの spec には書かれていなかった。この change の spec で初めて決まりにする。

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

`.font(.system(size: 11))` のような固定の大きさは使わず、`.subheadline` などのテキストスタイルで指定する。いまのコードの書き方に揃い、macOS が将来テキストスタイルの大きさを変えたり、ユーザーの文字の大きさの設定に追従するようになったりしたときに、そのまま効く。spec の 13pt・11pt は、macOS の今のテキストスタイルの大きさ（`.headline` / `.body` が 13pt、`.subheadline` が 11pt）で、実装はスタイルで指定する。

- 代替案: 共有の型（`ListTypography` など）に書体をまとめる。指定は 10 か所あまりで、ほとんどが 1 行の modifier なので、型を挟むと読む場所が増えるだけになる。採らない。10pt が残っていないことは、ポップオーバーの View のファイルに `.caption` / `.caption2` / `.footnote` が無いことを `grep` で確かめる（tasks）

### D2: 新しい階層

| 箇所 | 変更後 |
|---|---|
| スレッドの件名 | `.body`（変えない） |
| 「No unread notifications」 | 変更前 `.callout` + `.secondary`、変更後 `.subheadline` + `.secondary`（`sectionNote()`） |
| スレッドの行の 2 行目 | `.subheadline` + `.secondary` |
| リポジトリの見出し | `.subheadline.weight(.semibold)`、`.secondary` を外す、`truncatedToOneLine(_:mode:)`（1 行、中央の省略、ツールチップで全体、「…」の分の最小幅） |
| アカウントのユーザー名 | `.headline`（13pt の太字）、`layoutPriority(1)`、`truncatedToOneLine(_:mode:)`（1 行、末尾の省略、ツールチップで全体、「…」の分の最小幅） |
| active の印・件数 | `.subheadline`（カプセルの塗りは変えない）、`capsuleBadge` の中の `fixedSize()`（省略しない） |
| ホスト名とホスト種別、参加のみの印 | `.subheadline` + `.secondary`、ホスト名は `truncatedToOneLine(_:mode:)`（1 行、中央の省略、ツールチップで全体、「…」の分の最小幅）、表示とツールチップは `Account.hostLabel`（UI 層の拡張） |
| 取得の状態、操作の失敗 | `.subheadline`（`sectionNote()`）。打ち切りの知らせは `.secondary` を外す。それ以外の `.secondary` の付け方は変えない |
| 「Checking gh…」 | `.subheadline` + `.secondary`（`sectionNote()`） |
| トークンを取れないときの文 | `.subheadline`、`.secondary` を外す（`sectionNote()`。コマンドの行と一緒に字下げする）。コマンドの行のコピーボタンのアイコンも `sectionNote()` の書体を受け継いで 13pt から 11pt になる（区画のほかのコピーボタンと揃う） |
| 見出しの山形 | `.subheadline.weight(.semibold)` + `.secondary`、アカウントの見出しでもリポジトリの見出しでも 11pt（幅は `ListLayout.chevronWidth` で揃える） |
| 折りたたんだときの件数 | `.subheadline.monospacedDigit()` + `.secondary`、`fixedSize()`（省略しない） |
| すべて既読の確認の文 | `.subheadline.weight(.semibold)`、`fixedSize()`（省略しない）、色は既存のとおりアクセントカラー（`.tint`） |
| 通知が切られているときの案内 | ベルと文を `Label` にして `.subheadline`（ボタンには掛けない） |

アカウントのユーザー名は、いまは件名（13pt）より小さい 11pt で、見出しなのに件名より目立たない。`.headline` にして件名と同じ大きさの太字にし、区画の区切りが分かるようにする。リポジトリの見出しは件名より 1 段小さい 11pt の太字に残し、色だけ標準に戻す（太さと大きさで件名と区別できるので、薄くする必要が無い）。

- 代替案: 補足の情報を `.callout`（12pt）にする。件名（13pt）との差が 1pt になり、行の 1 行目と 2 行目の区別が付きにくくなる。行の高さも増え、一度に見えるスレッドが減る。採らない

### D3: コントラストは数値の目標を置かず、見出しを標準の文字色にする

システムの副次的な文字色（`.secondary`）は、白い背景の上でも 4.5 : 1 を下回る色で（ライトモードの `secondaryLabelColor` は黒の 50%）、ポップオーバーのマテリアルの上では後ろのウィンドウの色でさらに変わる。アプリの側から比を数値で保証することはできないので、次の方針にする。

- 読めないと困る情報（件名、アカウントのユーザー名、リポジトリの見出し、操作の失敗、トークンを取れないときやスコープ不足・認証エラーの案内、取得の失敗の文、打ち切りの知らせ）は標準の文字色にする。範囲は spec の Requirement を正とする
- `.secondary` は補足の情報にだけ使い、その場合も 11pt 以上にする（いちばん小さい文字に薄い色を重ねない）
- 文字の色はシステムの文字色（標準・副次的）と、すべて既読の確認の文のアクセントカラーだけにする。アイコンは状態を表すシステムの色（黄・緑）も使う。「コントラストを上げる」「透明度を下げる」はシステムの色とマテリアルに効くので、それで足りないユーザーはシステムの設定で補える

- 代替案: ポップオーバーに不透明な背景（`.background(.windowBackground)`）を敷く。後ろの色の影響は消えるが、ほかのメニューバーのポップオーバーと見た目が揃わなくなる。採らない
- 代替案: `.secondary` をやめてすべて標準の文字色にする。補足の情報と本文の区別が付かなくなる。採らない

### D4: 見出しの行で縮める順

幅が足りないときは、ホスト名とホスト種別 → ユーザー名の末尾の順に省略する。active の印・件数・確認の文は `fixedSize()` で省略しない。ユーザー名は `layoutPriority(1)` にする。ホスト名・ユーザー名・リポジトリ名は、「…」が 1 つ入る幅を最小幅として残す。「…」も入らない幅まで縮むと、SwiftUI は省略記号を出さずに切れた字を描くため（39 文字のユーザー名で確認の文が出ているときに、半分切れた 1 文字が残った）。この幅は `@ScaledMetric(relativeTo: .subheadline)` の 16pt で、文字の大きさに合わせて変わる。1 行に収める・省略する・最小幅・ツールチップの 4 つは `truncatedToOneLine(_:mode:)` にまとめ、3 か所で同じ扱いにする。ホスト名が「g…」のように短くなりうるので、全体はツールチップで出す。リポジトリの見出しも 1 行で中央を省略する（2 行に折り返すと山形と件数が縦の中央に来るため）。

- 代替案: ホスト名を読めるだけの最低幅（60pt など）を残す。ユーザー名が早く省略され、ホスト名を読むことはツールチップで足りるので採らない（上の 16pt は切れた字を出さないための幅で、ホスト名を読ませるためのものではない）
- 代替案: 「…」も入らないときはホスト名を隠す。自前の `Layout` か `ViewThatFits` が要り、ホスト名があること自体が見えなくなるので採らない
- 代替案: ユーザー名を折り返す。確認の 5 秒だけ見出しが高くなり一覧が動くので採らない

### D5: 再試行の文

「Rate limited. Retrying at <時刻>」と「Could not fetch notifications. Retrying at <時刻>」は、文ごとに 1 つの `Text` にする。2 つの `Text` を並べると時刻だけが別に折り返し、文の一部を `String` で埋め込むとローカライズのキーから外れるため。

### D6: 区画の補足の文の体裁

区画の中の補足の文（取得の状態、操作の失敗、トークンを取れないときの案内）は、main では、取得の状態と操作の失敗は大きさ・字下げ・折り返しの 3 つを、「Checking gh…」は大きさと字下げを、トークンを取れないときの案内は大きさだけを指定していて、案内だけ字下げが無かった。これは書体の型ではなく区画の体裁の規則なので、`View` の拡張 `sectionNote()`（`ListLayout.swift`）に 1 つだけまとめ、トークンを取れないときの案内とコマンドにも使って字下げを揃える。「No unread notifications」も、「Checking gh…」と同じく薄い色の `sectionNote()` にする。行の間隔は `ListLayout.noteSpacing`（6）で揃える。

- 代替案: 中身を受け取るコンテナ（`SectionNote(kind:) { ... }`）にして、行の間隔と色（補足か案内か）も持たせる。SwiftUI では見た目は modifier で重ね、コンテナは並べ方や意味のまとまりに使うのが定石で、文字の階層（`.secondary`）も使う側が意味ごとに付ける。色を列挙で切り替える自前のコンテナは独自のデザインシステムに寄るので採らない（ユーザーの判断）。色と行の間隔は呼び出し側で付け、どの文字を薄くするかは spec の Requirement と D2 の表で確かめる

### D7: gh のコマンドの文字列

案内に出す gh のコマンド（`gh --version`、`gh auth status`、`gh auth login`、ホストを付けた `login`・`switch`・`refresh`）は、`Mewbell/UI/GhCommand.swift` の `GhCommand` ですべて作る。`gh auth login --hostname <host>` が 3 か所で組み立てられていたのがきっかけで、使う回数ではなく役割（区画と案内画面に出す gh のコマンド）でまとめる。

### D8: 表示用の名前と体裁の部品の置き場所

`hostLabel` と `accessibilityName` はモデルではなく UI 層の `Account` の拡張（`Mewbell/UI/Account+Display.swift`）に置く。モデルは自分を表示する画面を知らない。`ListLayout`・`sectionNote()`・`capsuleBadge`・`truncatedToOneLine` は一覧の体裁の部品なので、開閉のボタンのファイルではなく `Mewbell/UI/ListLayout.swift` に置く。

### スレッドと actor の境界

View の modifier を変えるだけで、`@MainActor` の View の中で完結する。actor とネットワーク、ポーリングには触れない。

### テストでの差し替え

SwiftUI の書体はユニットテストから読めないので、書体のユニットテストは足さない（文字列を作る `Account` の表示用の拡張と `GhCommand` にはテストを足す）。プレビューと一時的なテストで描く幅は、ポップオーバーの 380pt から `.padding()` を引いた中身の幅（348pt）にする。次で確かめる。

- `grep` で、ポップオーバーの View のファイル全部（`Mewbell/UI/` のうち `SettingsView.swift`・`DiagnosticsSettingsView.swift`・`MenuBarLabel.swift` を除いたものと `Mewbell/App/MenuBarContentView.swift`）に 10pt のテキストスタイルが残っていないこと
- プレビュー（Xcode の RenderPreview、使えなければ一時的な `ImageRenderer` のテスト。コミットしない）で、幅 380pt の中の配置、長いホスト名の省略、件名の 2 行の省略、ホバーのボタンの位置（件名の 1 行目に揃う）
- 手元で起動したポップオーバーのスクリーンショットで、変更の前と同じ条件（ライトモード、後ろが暗いウィンドウ）の文字の大きさとコントラスト比を測って比べる
- 「コントラストを上げる」はシステムの設定を切り替えず、プレビューの Increased Contrast の変種で、薄い色の文字の比が上がることを測る
- 「透明度を下げる」は、ポップオーバー全体の背景をシステムのマテリアルのままにし、独自の背景で覆っていないこと（囲み・バッジのシステムの塗りの色を薄く重ねたものは除く）を、上と同じポップオーバーの View のファイル全部に対する grep とコードで確かめる。設定の切り替えはしない
- Xcode のプレビューが描けないときは、一時的なテスト（コミットしない）で `NSHostingView` を画像にして、長いユーザー名・長いリポジトリ名・200 文字の件名・再試行の行・操作の失敗の文の配置を見る

## セキュリティ

トークン・gh サブプロセス・ネットワーク・URL を開く処理のいずれにも触れない。表示する内容も変えないので、トークンや API の URL を表示しないこと（ui「アカウント一覧の表示」）はそのまま保たれる。`.claude/rules/security.md` の項目で、この change で新しく満たすものは無い。

## Risks / Trade-offs

- [行の高さが増え、一度に見えるスレッドが減る] → 主に増えるのは 2 行目とリポジトリの見出しの 1pt ずつ、アカウントのユーザー名の 2pt（ほかに取得の状態の文と山形も 1pt 増え、「No unread notifications」は 1pt 減る）で、一覧はいまも 480pt でスクロールする。未読が少なく、見えるスレッドの数は比べられなかった（tasks.md 1.1・3.3）。行の高さが増えることは、一時的なテストの画像で見た（tasks.md 5.2）
- [見出しの行が横にあふれる] → D4 の順（ホスト名 → ユーザー名の末尾）で縮め、active の印・件数・確認の文は省略しない。長いホスト名・長いユーザー名のプレビューで確かめる
- [ホバーのボタンと件名の重なり] → 件名の大きさは変えないので、ボタンの位置と件名を消す範囲（`ThreadActionButtons.titleFade`）は変えずに済む。ホバーのプレビューで確かめる
