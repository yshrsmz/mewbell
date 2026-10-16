## 1. 色セットと割り当て

- [x] 1.1 `Mewbell/Assets.xcassets` に色セット `StateOpen`・`StateClosed`・`StateDone` を足す。それぞれに、指定なし（ライト）、`luminosity: dark`、`contrast: high`、`luminosity: dark` かつ `contrast: high` の 4 つの外観を置き、spec の表の値を sRGB で書く（design D1）。`bash scripts/build.sh` で、生成された記号 `Color(.stateOpen)` などが使えることを確かめる
- [x] 1.2 `ThreadIcon.stateIcon` の `.green`・`.red`・`.purple` を `.stateOpen`・`.stateClosed`・`.stateDone` に置き換える（design D1）。draft と closed as not planned は `nil` のまま。既存の `ThreadIconTests` が通ることを確かめる
- [x] 1.3 `ThreadIconTests` に、状態ごとの色が色セットの `Color` と等しいこと、draft と closed as not planned の色が `nil` であることを確かめるテストを足す。`StateColorTests` を足し、3 つの色セットをライトとダークの外観で解決して、sRGB の成分が spec の表（8 bit に丸めて）と一致することを確かめる（design D2）。色セットの値を 1 つわざと変えるとテストが落ちることを手元で確かめてから戻す

## 2. 手元での確認（spec の Scenario ごと）

ユーザーが別の PC で確かめるため、マージの時点では 2.1〜2.4 は未確認（2.3 の `assetutil` での確認は済み。12 個の値がすべて表と一致した）。

- [ ] 2.1 `bash scripts/run.sh` で起動し、ライトの外観で、マージした Pull request（例: `yshrsmz/mewbell#54`）のアイコンが GitHub の Web と同じ紫で、閉じた Pull request（例: Renovate が autoclose した PR）の赤と見分けられることを確かめる。開いている Pull request と Issue が緑、完了として閉じた Issue が紫で出ることも確かめる
- [ ] 2.2 ダークの外観に切り替え、ポップオーバーを開き直さなくても次に描くときから GitHub のダークの色で出ることを確かめる
- [ ] 2.3 `xcrun assetutil --info build/Debug/Mewbell.app/Contents/Resources/Assets.car` で、3 つの色セットの `NSAppearanceNameAccessibilitySystem`・`NSAppearanceNameAccessibilityDarkAqua` の値が spec の表のコントラストを上げたときの値と一致することを確かめる（design D2）。「コントラストを上げる」をオンにして、ライトとダークの両方で、ハイコントラストの値（ライトでは濃く、ダークでは明るく）に変わることを確かめる
- [ ] 2.4 draft の Pull request、closed as not planned の Issue、状態が分からないスレッドのアイコンが薄い色のままであること、アカウントの見出しのトークンの状態のアイコンとメニューバーの猫アイコンの色が `main` と変わらないことを確かめる

## 3. 仕上げ

- [x] 3.1 `bash scripts/lint.sh` が通ることを確かめる
- [ ] 3.2 （警告をエラー扱いにした Debug と Release のビルドと、全テスト 512 件は通った。手元での確認は 2 のとおり未確認）`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell -configuration Debug MEWBELL_WARNINGS_AS_ERRORS=YES build` と同じ Release のビルドが通り、`xcodebuild -project Mewbell.xcodeproj -scheme Mewbell test` が通り、手元で起動して 2 の確認を終えたことを確かめる

## 4. レビュー（.claude/rules/review-process.md）

- [x] 4.1 別コンテキストの opus サブエージェント（`general-purpose`）で `simplify` を実行し、入った変更を確かめる
- [x] 4.2 別の opus サブエージェントで `code-review` を effort `medium` で実行し、指摘ごとに直す・直さない（理由）を決めて対応する。ロジックの変更を含む修正が多いときは、もう一度 `code-review` を新しいサブエージェントで回す
- [x] 4.3 PR 本文の Test plan に、simplify と code-review をサブエージェントで実行したこと、指摘の件数と対応を書く（トークン・ネットワーク・URL を開く処理に触れないので「セキュリティ上の確認」の節は要らない）
