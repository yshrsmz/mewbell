# Proposal

## Why

スレッドの行の状態のアイコンは、SwiftUI のシステムの色（`.green`・`.red`・`.purple`）で描いている。GitHub の Web は同じ状態を Primer の色（open の緑、closed の赤、merged と完了の紫）で描くので、色の割り当ては同じでも色そのものが違う。特にシステムの紫（ライト `#AF52DE`、ダーク `#BF5AF2`）は赤の成分が強く、マージした Pull request のアイコンが小さいと赤っぽく見え、閉じた Pull request の赤と見分けにくいとユーザーが指摘した。GitHub を見慣れた人が色で状態を読めるよう、Web と同じ色に揃える。

## What Changes

- スレッドの行の状態のアイコンのうち色の付くもの（Pull request の open・merged・closed、Issue の open・closed as completed）を、GitHub の Primer の状態の色（`fgColor-open`・`fgColor-closed`・`fgColor-done`）で描く。ライト・ダークと、それぞれの「コントラストを上げる」の 4 通りで、Primer の対応するテーマ（light・dark・light-high-contrast・dark-high-contrast）の値を使う。
- 色はアセットカタログの色セットに置き、外観と「コントラストを上げる」の切り替えはシステムに任せる。
- 状態ごとの色の割り当て（どの状態が緑・赤・紫か）、記号の形、薄い色で出すもの（draft の Pull request、closed as not planned の Issue、状態が分からないもの）は変えない。
- アカウントの見出しのトークンの状態のアイコン（緑・黄）とメニューバーの猫アイコンの緑は、システムの色のまま変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

- `ui`: 「スレッドの行の状態のアイコン」に、状態の色を GitHub の Web と同じ色（Primer の状態の色）にし、外観と「コントラストを上げる」に合わせて変える要件を足す。「ポップオーバーの文字の読みやすさ」はアイコンの色を文字の色の決まりから外しているので、変えない。

## Impact

- マイルストーン: M4（設定と操作）以降に足した一覧の見た目の改善。特定のマイルストーンには属さない。
- 変更するもの: `Mewbell/UI/ThreadIcon.swift`、`Mewbell/Assets.xcassets`（色セットを 3 つ足す）、`MewbellTests/ThreadPresentationTests.swift`。プロジェクトはフォルダ単位でファイルを取り込んでいるので、`project.xcproj` は変えない見込み。
- 外部依存は足さない。色の値は Primer（`@primer/primitives` 11.10.0）の公開の値を書き写すだけで、パッケージは取り込まない。
- トークン・gh サブプロセス・ネットワーク・URL を開く処理には触れない（表示の色だけの変更）。
