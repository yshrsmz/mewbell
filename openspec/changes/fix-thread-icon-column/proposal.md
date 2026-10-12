# Proposal

## Why

ポップオーバーの通知一覧で、Discussion のスレッドの行の種類のアイコン（`bubble.left.and.bubble.right`）の左端が約 1pt 欠けている。

スレッドの行の種類のアイコンは、幅 16pt の列（`ListLayout.chevronWidth`）の中央に置いている。この列には、見出しの山形（`DisclosureChevron`）とアカウントの見出しのトークンの状態のアイコン（`tokenIcon`）も置く。ところが、記号を本文の書体（13pt）で描くと、配置の幅（`NSHostingView` の `fittingSize`）が 16pt を超えるものがある。手元で実測した値は次のとおり。

| 記号 | 倍率 1 | 倍率 2 |
|---|---|---|
| `bubble.left.and.bubble.right`（Discussion） | 23pt | 22pt |
| `point.3.connected.trianglepath.dotted`（Commit） | 18pt | 17pt |
| `tag`（Release） | 17pt | 17pt |
| `exclamationmark.triangle.fill`（トークンの状態） | 16pt | 17pt |
| 丸の記号（Pull request・Issue の状態など） | 15pt | 15pt |
| `chevron.right`（山形、`.subheadline` の semibold） | 9×12pt | 9×12pt |

列からはみ出した部分は、行の `.mask`（マウスを載せたときに件名をボタンの下で消す処理）の外に出るので、左端が切れて見えていた。

この change は、M4（設定と操作）の UI の不具合の修正にあたる（M5 の v0.1.0 の公開後）。

## What Changes

- アイコンの列の幅を 16pt から 24pt にする。`ListLayout.chevronWidth` を `ListLayout.iconColumnWidth` に改名する。24pt は、列に置くどの記号の配置の枠も、倍率 1 と 2 のどちらでも収まる幅にあたる。見出しの下の中身の字下げ（`contentIndent`）は、今の式（列の幅と間隔の和）のまま 30pt になる
- 記号は縮めず、書体で決まる大きさのまま描く。書体・記号・見出しの揃え・`ThreadIcon`・View の構造は変えない
- 列に置く記号（スレッドの行の種類と状態のアイコン、トークンの状態のアイコン、山形）が、倍率 1 と 2 のどちらでも列に収まることを確かめるテスト（`IconColumnTests`）を足す
- ui の Requirement「ポップオーバーの文字の読みやすさ」のアイコンの段落に、アイコンの列の決まり（同じ幅の列の中央に置く、記号を縮めない、欠けずに出す）を足し、Discussion の行の Scenario を 1 つ足す（MODIFIED）

## Capabilities

### New Capabilities

（なし）

### Modified Capabilities

- `ui`: Requirement「ポップオーバーの文字の読みやすさ」に、アイコンの列の決まりと Scenario を足す（MODIFIED）。表示する項目と操作は変えない

## Impact

- 変わるコード: `Mewbell/UI/`（`ListLayout.swift`、`ThreadRow.swift`、`DisclosureButton.swift`、`AccountSectionView.swift`）、新規の `MewbellTests/IconColumnTests.swift`
- 見た目: 列の幅だけが変わる。列が 8pt 広がり、見出しの下の中身（リポジトリの見出し、スレッドの行、区画の中の文）の字下げも 8pt 深くなる。スレッドの件名は字下げと行の列の 2 つ分、アカウントの見出しのユーザー名は山形とトークンの状態の列の 2 つ分ずれるので、件名とアカウントの見出しに使える幅は main より 16pt 狭くなる。どの行も、記号と件名の間が約 4pt 空く（列の中央に置いた記号の右の空きが増える）
- トークン: 扱わない。何も永続化しない
- gh サブプロセス: 触れない
- ネットワーク: 触れない
- URL を開く処理: 触れない
- 外部依存: 追加しない
