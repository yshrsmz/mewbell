# Design

## Context

archive 済みの 18 件の design.md の Decisions とコードを横断して、change をまたいで効いている約束を 12 のテーマに分けた。

| テーマ | 主な根拠 | 文書化の状況 |
| --- | --- | --- |
| 依存の向きと組み立て | 機能を足す change の D1（配置の表） | 依存の向きは暗黙 |
| actor と `@MainActor` の境界 | add-project-skeleton D3、add-notification-fetch D2・D7、add-settings D3、add-diagnostics D6 | 書かれている（config.yaml の design の規則） |
| 状態の持ち主 | add-thread-actions D8、update-notification-list D1・D4・D6、add-settings D2 | 原則は暗黙 |
| View の組み立て | add-thread-actions D7、add-notification-fetch D9、add-web-notifications-link D2、update-list-readability D7・D8 | ViewModel を置かないことは暗黙 |
| 外部の差し替え | add-project-skeleton D4、add-gh-account-discovery D9、add-notification-fetch D10、add-settings D11 | 一部 |
| 関所を 1 か所にする | add-notification-fetch D2、add-thread-actions D2、add-web-notifications-link D1・D2 | 書かれている（security.md） |
| 判断の値型 | add-notification-fetch D5、add-system-notifications D2、update-reload-fetch-now D2、add-thread-latest-event §3 | 原則は暗黙 |
| エラーと結果の表し方 | add-notification-fetch D2、add-thread-actions D2、add-diagnostics D1、add-settings D8 | 書かれている |
| 部品を足す基準 | update-list-readability D1・D6、fix-thread-icon-column D3、update-unknown-state-icon D2 | 手順として review-process.md にある |
| 可視性 | add-thread-latest-event §2・§3、remove-redundant-tests | 原則は暗黙 |
| ログ | security.md、add-gh-account-discovery D6 | カテゴリの付け方は暗黙 |
| テストの方針 | remove-redundant-tests、fix-thread-icon-column D3、CLAUDE.md | 書かれている |

change によって判断が割れていた点は、ユーザーと決めた（proposal.md の What Changes）。原則を書いた後の検証で見つかった点は D10 に書いた。add-settings の D3・D7 は「`SystemNotifier` が `AppSettings` を読む」と書いているが、今のコードは AppDelegate からクロージャを受け取る形である。archive は当時の記録なので直さず、原則は今のコードの形（外部の差し替えのクロージャ）に合わせる。

文書を読む側は 3 つある。

- **メインのエージェント**: 設計・実装・指摘の仕分けで読む。
- **OpenSpec の design 段階**: config.yaml の `context` と `rules` が artifact の指示に注入される。
- **レビューのサブエージェント**: 経緯を渡さず、CLAUDE.md と `.claude/rules/` を読むよう指示されて起動する。

`.claude/rules/` に置いたファイルは、毎回のセッションとサブエージェントに自動で読み込まれる。

## Goals / Non-Goals

**Goals:**

- 指摘の仕分けで、「方針に反する」「方針が退けた案を求めている」「方針が決めていない」を区別できるようにする。
- 方針の変更が、ほかの change と同じ流れで記録されるようにする。

**Non-Goals:**

- 既知の逸脱をこの change で直すこと（proposal.md の Impact に挙げた別の change で行う）。
- 振る舞いの約束（ポーリング・トークン・ホスト種別など、spec にあるもの）を文書に写すこと。CLAUDE.md の「実装上の約束」のうち、振る舞いを要約した項目はそのまま残す。
- review-loop スキル（`~/.claude/skills/`、このリポジトリの外）の依頼文を変えること。依頼文は「CLAUDE.md と `.claude/rules/` を読む」と指示しているので、CLAUDE.md からの参照で届く。

## Decisions

### D1. 設計の方針は 1 つの文書に「今の形」として書く。ADR も spec も使わない

`docs/architecture.md` の 1 ファイルに、今の方針だけを書く。経緯は、根拠の change（archive の design.md）へのリンクで足りる。

採らなかった案:

- **ADR を決定ごとに積む**: 今の方針を知るには、置き換えの連鎖をたどる必要がある。レビューに渡すにも索引が要る。決定の経緯と時点は、archive された change（proposal、design.md、archive の日付）がすでに残している。
- **OpenSpec の spec（capability `architecture`）にする**: 5 つのテーマを試しに Requirement と Scenario で書いた。Scenario が自然に書けたのは、テストの隔離とログのように実行時に確かめられるものと、lint が判定するものだけだった。actor 境界や依存の向きは、THEN が「レビューで指摘される」の形になった。OpenSpec のスキーマは spec を振る舞いの約束とし、「外から見える振る舞いを変えずに実装を変えられるなら spec に書かない」としている。採らなかった案を置く場所も spec には無い。
- **`.claude/rules/architecture.md` に置く**: 毎回自動で読み込まれ、渡し忘れが無い。一方で、判断の要らない作業でもコンテキストが増える。読む場面は設計・実装・レビューの判断に限られるので、参照で渡す（D4）。

### D2. 文書の構成

```
# Mewbell の設計方針
（この文書の位置づけ。spec が振る舞い、この文書がコードの構造の約束を受け持つ。更新は update-architecture-doc スキルで行う）

## 方針が割れたときの優先順位
## 指摘の仕分けとの関係
## 方針を足す・改める
## 原則
### A1. …
（各原則: 原則 / 理由 / 採らなかった案 / 適用外 / 根拠）
## 既知の逸脱
```

- **ID**: `A1` からの通し番号にし、再利用しない。原則を廃止したときは、見出しを残して「廃止（<change 名>）」と書く。レビューの指摘・仕分けの理由・design.md から ID で引くため、番号がずれないようにする。ほかの文書からは、`A3` のように ID だけで引く。
- **書式**: 検査（D8）が読めるよう、各原則を次の決まった形で書く。

  ```
  ### A3. 状態の持ち主は、残す期間で決める

  - **原則**: …
  - **理由**: …
  - **採らなかった案**:
    - <案>: <理由>
  - **適用外**: …（無ければ「なし」）
  - **根拠**: add-thread-actions D8、update-notification-list D1
  ```

  廃止した原則は、見出しを `### A3. 廃止（<change 名>）` にし、本文は `- **廃止の理由**: …` の 1 行だけにする。
- **原則の数**: 12 のテーマを 1 つずつ原則にし、CLAUDE.md から移す外部依存の約束（D4）と、検証で見つかった判断（D10）を足して 15 にする。依存の向きと置き場所の軸（使う層のうち最も下に置く）は同じ原則に入れる。
- **各項目の分量**: 原則・理由は数文、採らなかった案は 1 案 1 行にする。コードの例は型名を挙げるだけにし、コードは貼らない。
- **既知の逸脱**: 原則に合わない今のコードを、直す予定の change の名前とともに書く。逸脱を直したら行を消す。
- **書き方**: 経緯を並べない（「〜したが、〜に変えた」と書かない）。

### D3. 優先順位と、指摘の仕分けとの関係

優先順位は次のとおり。

1. `openspec/specs/` の要件
2. `.claude/rules/security.md`
3. この文書の原則
4. Swift と Apple のプラットフォームの慣用

原則と慣用が食い違うときは、原則の「理由」がその場面に当てはまるかで決める。当てはまらないなら、それは原則への異議として扱う。

指摘の仕分けとの対応は次のとおり。review-process.md の「指摘の直し方」から、この節を参照する。

| 指摘 | 扱い |
| --- | --- |
| 原則に反している | 直す。原則の ID を添える |
| 原則が「採らなかった案」に挙げた形を求めている | 直さない。理由は原則の ID |
| 原則そのものへの異議（理由がその場面に当てはまらない、など） | AskUserQuestion で確かめる。採るなら原則を改める（D5） |
| 方針が何も決めていない論点 | AskUserQuestion で確かめる。決めたことは change の design.md に書き、change をまたいで効くものは同じ change で文書にも足す |

採らなかった案:

- **優先順位を書かない**: 原則と慣用のどちらを取るかで、レビューの周ごとに判断が揺れる。
- **慣用を原則より上に置く**: 「Apple の慣用に沿う」を理由に、過去に退けた案（`@AppStorage`、`@Environment(\.openURL)` など）が再提案されたとき、原則で止められない。

### D4. 文書の渡し方

| 読む側 | 渡し方 |
| --- | --- |
| メインのエージェント | CLAUDE.md の「実装上の約束」の前に、文書の場所と読む場面（設計・実装・レビューで判断が要るとき）を 1〜2 行で書く。CLAUDE.md の構造の約束（strict concurrency と actor の境界、外部依存を最小限にする）は文書の原則に移し、CLAUDE.md には参照だけを残す |
| OpenSpec の design 段階 | `openspec/config.yaml` の `rules.design` に足す。各 Decision に、従う原則の ID を書く。原則から外れる判断は、その旨と理由を書く。change をまたいで効く新しい判断は、同じ change で文書にも足すタスクを置く。`context` には足さない（全 artifact に注入されるため） |
| レビューのサブエージェント | review-process.md の「サブエージェントへの渡し方」に、`docs/architecture.md` を読ませることを足す。対象は simplify・code-review・目標の形の検証。「経緯を渡さない」の規則とは衝突しない。文書は今の方針であって、メインのエージェントの判断の経緯ではない |

`rules.tasks` には 1 行だけ足す。`docs/architecture.md` を変える change は、update-architecture-doc スキルでの更新と `bash scripts/check-architecture.sh` の実行をタスクに含める。

### D5. 方針を足す・改める手順

- **足す**: 方針に無い論点を change の中で決めたら、その change の design.md に Decision として書く。change をまたいで効くものは、同じ change で `docs/architecture.md` に原則として足す（または既存の原則に書き足す）。
- **改める**: 原則を変えるときは、そのための change を起こす。振る舞いが変わらなければ `skip_specs: true` にする。design.md に、改める理由と採らなかった案を書く。今のコードが新しい原則に合わなくなるなら、「既知の逸脱」に書く。
- **change をまたいで効くかの目安**: 別の機能を足すときにも同じ問いが出るか。出るなら原則にする。

採らなかった案:

- **archive のときにまとめて昇格する**: archive は実装とレビューの後なので、レビューの間に決めたことが、その周のレビューに届かない。

### D6. lint に移す約束

`.swiftlint.yml` の `custom_rules` に、正規表現で書ける約束だけを移す。CI（ubuntu の Docker の swiftlint 0.65.1）でもそのまま動く。

| 規則 | 対象 | 根拠 |
| --- | --- | --- |
| `print(` を使わない | `Mewbell/` | security.md（ログは `Logger`） |
| `Thread.sleep` を使わない | `Mewbell/`・`MewbellTests/` | CLAUDE.md（actor が塞がる） |
| `URLSession.shared` を使わない | `Mewbell/` | security.md（キャッシュを使わない設定のセッションだけを使う） |
| `import SwiftUI`・`import AppKit` は `UI/`・`App/` だけ。`Polling/NotificationStore.swift` は除く | `Mewbell/` | 依存の向きの原則 |
| `"Authorization"` を書くのは `GitHubAPI/GitHubAPIClient.swift` だけ | `Mewbell/` | 関所の原則、security.md |
| `.system(size:` を使わない | `Mewbell/UI/`・`Mewbell/App/` | update-list-readability D1（大きさはテキストスタイルで指定する） |

規則ごとに、`message` に原則の ID を入れる。今のコードがどれかに引っかかる場合は、規則の範囲（`included` / `excluded`）が原則と合っているかを見直す。原則に合わないコードは「既知の逸脱」にして、その場所だけを除外する。

採らなかった案:

- **`NSWorkspace.shared.open` を `NotificationStore` だけに限る**: 案内画面（gh のサイト）と通知の許可のバナー（システム設定）が、API 由来でない固定の URL を開いている。関所の原則が守るのは「API 由来の URL を開く前の検査」なので、正規表現では区別できない。
- **型の参照の向きを lint で守る**: 正規表現では書けない。SwiftPM のモジュールに分けるのは、この change の範囲を超える。

### D7. 割れていた判断と、既知の逸脱

| 原則 | 決めた形 | 今のコードとの関係 |
| --- | --- | --- |
| 置き場所の軸 | 使う層のうち最も下の層に置く。1 つの層だけが使うならその層、複数の層が使うなら共通の依存先 | `RepositoryGroup`（`Polling/`）、`hostLabel`（`UI/`）、`displayName`（`AccountID`）はどれも合う |
| 両方が使う文言 | ポップオーバーと macOS の通知の両方が使う文言は `UI/` の外に置く | `ThreadReason`・`ThreadEventText` が `UI/` にあり、`Notifications/` から使われている → 逸脱 |
| store を受け取る View | store を直接受け取るのは、シーンのルート（`MenuBarContentView`、`SettingsView`、`MenuBarLabel`）だけ。それ以外の View は値と操作のクロージャを受け取る | `DiagnosticsSettingsView` などの設定のタブの子が store を受け取っている → 逸脱 |
| 関所の可視性 | 関所は `private` を保つ。行数の上限で分けるときは、関所を分けずにそのファイルの上限を緩める | `GitHubAPIClient.send` の `private` が外れている → 逸脱 |

D10 で、既知の逸脱をさらに 5 つ足した。

### D8. 機械的な検査（`scripts/check-architecture.sh`）

文書の更新で起きる漏れのうち、機械的に見つけられるものを、bash と grep / awk だけの検査で見つける。macOS（手元）と ubuntu（CI）の両方で動くようにし、外部の依存は足さない。検査するルートのディレクトリを引数で受け取れるようにして、テストで偽のリポジトリを組めるようにする（既定はリポジトリのルート）。

| 検査 | 見つける漏れ |
| --- | --- |
| 書式 | 原則の見出しが `### A<番号>. ` の形でない。ID が重複している。5 つの項目（原則・理由・採らなかった案・適用外・根拠）のどれかが欠けている（廃止した原則を除く） |
| ID の参照 | `CLAUDE.md`、`.claude/rules/*.md`、`.claude/skills/*/SKILL.md`、`openspec/config.yaml`、`.swiftlint.yml`、`openspec/changes/` の design.md（archive を含む）が引いている `A<番号>` が、文書に無い。archive でない文書と `.swiftlint.yml` が、廃止した原則を引いている |
| 根拠の change | 「根拠」に書いた change の名前が、`openspec/changes/` にも archive にも無い |
| コードの名前 | 文書の中の、バッククォートで囲んだ型名（大文字で始まる英数字）がコードに出てこない（`Mewbell/`・`MewbellTests/` を単語単位で探す）。`Mewbell/` で始まるパスが実在しない |
| 重複 | 文書の原則の文（「。」で区切った 1 文で、40 文字以上のもの）が、`CLAUDE.md`・`.claude/rules/*.md`・`openspec/config.yaml` にそのまま現れる |

- 実行する場所: `scripts/lint.sh` の最後と、CI の lint のジョブ（ubuntu、Docker を使わずにそのまま実行する）。CI では、検査のテスト `scripts/tests/check-architecture-test.sh` も実行する。
- 見つけたら、ファイル・行・どの検査か・直し方の 1 行を標準エラー出力に出し、終了コード 1 で終える。

採らなかった案:

- **原則を YAML で持ち、Markdown を生成する**: 1 か所から生成すれば書式の崩れは起きない。一方で、生成の道具と生成物の同期の検査が要り、読み書きするのは Markdown のままである。決まった書式の Markdown を検査すれば足りる。
- **重複を意味で判定する**: 言い換えた重複は機械では見つけられない。それはスキルの手順（D9 の受け持ちの表）とレビューに任せ、検査はそのまま写した文だけを見つける。
- **型名が「定義されているか」を確かめる**: `URLSession` のような Apple の型も文書に出てくる。コードに「出てくるか」を見れば、改名や削除の漏れは見つけられる。

### D9. 更新の手順（スキル `update-architecture-doc`）

判断の要る部分は、プロジェクトのスキル `.claude/skills/update-architecture-doc/SKILL.md` に手順として書く。スキルは使うときだけ読み込まれるので、常時のコンテキストは増えない。

- **使う場面**（スキルの description に書く）: design.md に change をまたいで効く Decision を書いたとき。レビューの指摘で、方針に無い論点を決めたとき。原則を改める・廃止するとき。既知の逸脱を直したとき・見つけたとき。
- **受け持ちの表**: 約束ごとに、本文を書く文書を 1 つに決める。ほかの文書は ID かパスで引くだけにする。

  | 約束 | 本文を書く文書 |
  | --- | --- |
  | 振る舞い（ユーザー・API から見えるもの） | `openspec/specs/` |
  | セキュリティの約束 | `.claude/rules/security.md` |
  | コードの構造の約束 | `docs/architecture.md` |
  | 開発の進め方、ビルドとテストの方法、ツールの癖 | `CLAUDE.md`、`.claude/rules/` |
  | artifact ごとの書き方の規則 | `openspec/config.yaml` |
  | 機械的に守れる約束 | `.swiftlint.yml`（`message` に ID を書き、文書の原則からも lint で守っていることを書く） |

- **手順**（種類ごとに書く）:
  - **足す**: D5 の目安で、change をまたいで効くかを確かめる。既存の原則に書き足せるかを先に探す。足すなら次の番号を振り、5 項目を埋める。今のコードが合わなければ既知の逸脱にも書く。正規表現で守れるなら lint の規則も足す
  - **改める**: 本文を今の形に書き換える。経緯は書かない。前の形を採らなかった案に移すのは、また提案されそうなときだけにする。`grep` でその ID を引いている箇所をすべて開き、食い違わないかを確かめる。lint の規則と既知の逸脱もそろえる
  - **廃止する**: 見出しを廃止の形にする。その ID を引いている lint の規則と、archive でない文書の参照を外す
  - **逸脱を直した**: 既知の逸脱から行を消す。原則の「適用外」に同じものが書かれていないかも確かめる
- 最後に `bash scripts/check-architecture.sh` を実行して通す。

採らなかった案:

- **手順を `.claude/rules/` に置く**: 毎回読み込まれ、常時のコンテキストが増える。
- **スキルを `~/.claude/skills/` に置く**: このリポジトリの文書の形に依存するので、リポジトリに置いてコミットする。

### D10. 原則を archive とコードに照らして決め直したこと

原則を書いた後、別のサブエージェントに、archive の design.md とコードに照らして検証させた。D 番号の誤り、例に挙げた型の誤り、archive と食い違う「採らなかった案」の理由は、事実に合わせて直した。そのうえで、次の点をユーザーと決めた。

| 論点 | 決めた形 |
| --- | --- |
| 下の層が上の層の型を使っている（`HostKind`、`ThreadAction`、`Logger(category:)`） | 原則は変えず、既知の逸脱にする |
| 中間の層（`Accounts/`・`Polling/`・`Notifications/`・`Settings/`）どうしの参照 | 同じ高さとして互いの参照を許す（A1） |
| テストのためだけに公開しているメンバー | 非同期の処理の終わりを待つフックは適用外にする。状態を読むだけの `AccountPoller.pendingRefreshCount` は既知の逸脱にする（A10） |
| どの原則にも入っていなかった、change をまたいで効く判断 | 4 つとも足す。状態の正本はポーラーに置くことと、消えたアカウントの片付けを 1 か所で行うことは A3 に書き足し、コールバックでつなぐことを A14、世代で捨てることを A15 にする |

ユーザーに確かめず、事実に合わせて決めた点は次のとおり。

- **URL を開く処理の既定値（A5）**: add-system-notifications D5 は既定値を `NSWorkspace.shared.open` にしたが、今のコードは既定値を持たない（`NotificationStore` のコメント）。テストで渡し忘れると本物のブラウザが開くので、今の形を原則にする。時刻と待ちは本物を既定値にしてよい。
- **UI/ の状態（A1・A4）**: `ListExpansion` などの表示だけに使う状態の型は `UI/` に置き、下位の View に渡してよい（update-notification-list D1）。
- **ログのカテゴリ（A11）**: `App/SingleInstance.swift` だけがディレクトリ名と違う。これは既知の逸脱にする。

## Risks / Trade-offs

- [参照で渡すので、読まれないことがある] → 読む場面を CLAUDE.md に書く。レビューのサブエージェントには review-process.md で明示する。design 段階は config.yaml の規則で毎回求める。
- [文書がコードとずれる] → 「既知の逸脱」で今のずれを明示し、直したら消す。原則を変えるときは change を起こし、design.md の規則で原則の ID を引かせる。引けない Decision が出たら、文書に無い論点として足す。
- [原則が増えすぎて、それ自体がコンテキストを太らせる] → 原則にするのは change をまたいで効くものだけにする（D5 の目安）。各項目の分量を D2 で抑える。
- [この change 自体の文書を、この change のレビューが根拠にする（自己参照）] → 原則の中身は、archive 済みの design.md とユーザーが決めた判断から起こす。PR 本文で人の目での確認を求める。

## セキュリティ

トークン・gh サブプロセス・ネットワーク・URL を開く処理のコードは変えない。トークンの流れ（取得・保持・送信・破棄）は変わらない。

`.claude/rules/security.md` との関係:

- security.md の項目は文書に写さない。優先順位で security.md を原則より上に置き、関所の原則からは security.md を参照する。
- lint の規則（D6）が、security.md の次の項目を機械的に確かめるようになる。
  - `print` を使わない
  - `URLSession.shared` を使わない（キャッシュを使わない）
  - `Authorization` を付ける場所を 1 か所にする
- lint の規則に、トークンの形式の文字列は書かない。

## Migration Plan

文書と設定だけの変更なので、移行の手順は無い。戻すときは、この change のコミットを revert する。既知の逸脱を直す 3 つの change は、この change のマージ後に別に起こす。
