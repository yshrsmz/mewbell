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

change によって判断が割れていた点は、ユーザーと決めた（proposal.md の What Changes）。add-settings の D3・D7 は「`SystemNotifier` が `AppSettings` を読む」と書いているが、今のコードは AppDelegate からクロージャを受け取る形である。archive は当時の記録なので直さず、原則は今のコードの形（外部の差し替えのクロージャ）に合わせる。

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
（この文書の位置づけ。spec が振る舞い、この文書がコードの構造の約束を受け持つ）

## 方針が割れたときの優先順位
## 指摘の仕分けとの関係
## 方針を足す・改める
## 原則
### A1. …
（各原則: 原則 / 理由 / 採らなかった案 / 適用外 / 根拠）
## 既知の逸脱
```

- **ID**: `A1` からの通し番号にし、再利用しない。原則を廃止したときは、見出しを残して「廃止（<change 名>）」と書く。レビューの指摘・仕分けの理由・design.md から ID で引くため、番号がずれないようにする。
- **原則の数**: 12 のテーマを 1 つずつ原則にする。依存の向きと置き場所の軸（使う層のうち最も下に置く）は同じ原則に入れる。
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

`rules.tasks` には足さない。文書を足すタスクは、design の規則から tasks に落ちる。

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
