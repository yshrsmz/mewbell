# Proposal

## Why

実装の後のレビュー（`.claude/rules/review-process.md`、review-loop スキル）では、指摘を直すかどうかを「このコードベースにとって最も正しい変更か」で決めている。ところが Mewbell には、このコードベースで何を正しいとするかを書いた文書が無い。

change をまたいで効く設計の約束は、change ごとの design.md の Decisions に散らばっている。archive されると次の change のレビューには届かない。archive 済みの 18 件の design.md とコードを横断すると、change をまたいで効いている約束が 12 あり、その半分以上は原則として書かれていない暗黙のものだった。そのため、独立したレビューは周ごとに一般論から正しさを組み立て直す。前の周と逆向きの提案が出たり、過去の change で退けた案が毎回あらためて提案されたりするのは、このためである。

判断が change によって割れているところもあり、レビューはどちらの形も「正しい」として提案できてしまう。

- ポップオーバーと通知の両方が使う文言の置き場所
- store を直接受け取る View の範囲
- 関所の可視性

## What Changes

- `docs/architecture.md` を新しく置く。設計の方針を、原則ごとに次の項目で書く。
  - 安定した ID
  - 原則
  - 理由
  - 採らなかった案
  - 適用外
  - 根拠の change

  あわせて次も書く。
  - 方針が割れたときの優先順位（spec、security.md、この文書、プラットフォームの慣用の順）
  - レビューの指摘をこの文書に照らしてどう仕分けるか
  - 文書に無い論点を決めたときと、原則を改めるときの手順
- 原則には、archive 済みの design.md とコードから抽出した 12 のテーマを起こす。テーマは次のとおり。
  - 依存の向き
  - actor 境界
  - 状態の持ち主
  - View の組み立て
  - 外部の差し替え
  - 関所
  - 判断の値型
  - エラーの表し方
  - 部品を足す基準
  - 可視性
  - ログ
  - テストの方針
- 割れていた判断は、次のように決める。
  - **両方が使う文言の置き場所**: ポップオーバーと macOS の通知の両方が使う文言は、`UI/` の外に置く。
  - **置き場所の軸**: 使う層のうち最も下の層に置く。
  - **store を受け取る View**: store を直接受け取ってよいのは、シーンのルートの View だけにする。
  - **関所の可視性**: 関所（`Authorization` を付ける送信など）は、行数の上限でファイルを分けるときも `private` を保つ。
- 今のコードがこれらの原則に合わない箇所は「既知の逸脱」として文書に書く。直すのは別の change で行う。
- 文書の渡し方は次のとおり。常時読み込まれるコンテキストは増やさない。
  - `CLAUDE.md`: 文書の場所と、読む場面（設計・実装・レビューで判断が要るとき）を書く。CLAUDE.md の「実装上の約束」のうち構造の約束（strict concurrency と actor、外部依存）は文書に移し、参照だけを残す。
  - `openspec/config.yaml`: `rules.design` に、各 Decision が従う原則の ID を書くこと、change をまたいで効く新しい判断を文書に足すこと、原則を改めるならその旨と理由を書くことを足す。
  - `.claude/rules/review-process.md`: simplify・code-review・目標の形の検証のサブエージェントに、この文書を読ませる。指摘の仕分けをこの文書に照らして行う手順を足す。
- 正規表現で守れる約束を `.swiftlint.yml` の `custom_rules` に移す。対象は次のとおり。
  - `print` を使わない
  - `Thread.sleep` を使わない
  - `URLSession.shared` を使わない
  - `UI/`・`App/` の外で SwiftUI・AppKit を import しない
  - `Authorization` ヘッダーを書くのは API クライアントだけ
  - 書体の大きさをポイント数で指定しない
- 文書の更新で、変更の漏れや記述の重複が起きないようにする。
  - `scripts/check-architecture.sh`: 機械的に確かめられることを検査する。対象は次のとおり。
    - 原則の書式と ID
    - 他の文書・lint の設定・design.md から引いている ID が実在するか
    - 根拠の change が実在するか
    - 文書に書いた型名・パスがコードに実在するか
    - 原則の文が CLAUDE.md や `.claude/rules/` に重ねて書かれていないか
  - `scripts/lint.sh` と CI の lint のジョブから、検査を実行する。検査のテストは `scripts/tests/` に置く。
  - プロジェクトのスキル `update-architecture-doc`（`.claude/skills/`）: 原則を足す・改める・廃止する・逸脱を足す / 消すときの手順を書く。どの約束をどの文書が受け持つかの表を持ち、同じ約束を 2 か所に書かないようにする。ID を引いている箇所の見直しと、lint の規則・既知の逸脱の同期も含める。

アプリの振る舞いは変えない。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

なし。開発の方針の文書と規約・lint の設定だけを変え、spec の要件は変えない（`.openspec.yaml` に `skip_specs: true` を設定）。設計の原則をコードの構造の約束として spec に書く案は、design.md で退けた理由を書く。

## Impact

- マイルストーン: 特定のマイルストーンには属さない、開発の進め方の change。
- 追加するもの: `docs/architecture.md`、`scripts/check-architecture.sh` とそのテスト、`.claude/skills/update-architecture-doc/SKILL.md`。
- 変更するもの: `CLAUDE.md`、`openspec/config.yaml`、`.claude/rules/review-process.md`、`.swiftlint.yml`、`scripts/lint.sh`、`.github/workflows/ci.yml`（検査の実行を足すだけで、権限・シークレット・使う Action は変えない）。アプリのコード（`Mewbell/`、`MewbellTests/`）は変えない。lint の新しい規則に今のコードが引っかかる場合は、規則の範囲を見直す。コードを直すのは、原則に合わせる別の change で行う。
- 後に続く change: 既知の逸脱を直す change を別に起こす。
  - `ThreadReason`・`ThreadEventText` を `UI/` の外に移す
  - 設定のタブの子の View を値とクロージャだけで組む
  - `GitHubAPIClient.send` を `private` に戻す
- トークン・gh サブプロセス・ネットワーク・URL を開く処理: 処理そのものには触れない。lint の規則で、`Authorization` ヘッダーを書く場所と、`URLSession.shared` を使わないことを機械的に確かめるようになる。トークンの永続化に関わる変更は無い。
