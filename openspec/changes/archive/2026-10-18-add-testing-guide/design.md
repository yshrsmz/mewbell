# Design

## Context

文書の分担は、スキル `update-architecture-doc` の表が決めている。今はテストの方針も「コードの構造の約束」として `docs/architecture.md` が受け持ち、A12 の 1 段落に収めている。`docs/architecture.md` は `scripts/check-architecture.sh` が次の点を検査している。

- 書式
- ID の参照
- 根拠の change
- バッククォートで書いたコードの名前
- ほかの文書への写し

A12 を ID で引いているのは次の 2 か所。

- CLAUDE.md（`SWIFT_APPROACHABLE_CONCURRENCY` の注意）
- `.swiftlint.yml` の `no_thread_sleep` の `message`

## Goals / Non-Goals

**Goals:**

- テストを書く・直す・削るときに、`docs/testing.md` だけを読めば判断できるようにする。
- レビューの指摘と design.md から、テストの方針を ID で引けるようにする。
- テストの方針の本文を 1 か所に置き、ほかの文書からは参照するだけにする。

**Non-Goals:**

- テストのコードを変えること。整理は続く 2 つの change で行う。
- `docs/testing.md` そのものの書式・コードの名前・T の ID を `scripts/check-architecture.sh` で検査すること。今の検査は原則の 5 項目の書式に依存しているので、`docs/testing.md` には合わない。ただし、`docs/testing.md` は A の ID を引き、原則の文を写すおそれもあるので、ID の参照と重複を探す先には足す。

## Decisions

### D1. テストの方針は `docs/testing.md` に置き、A12 はそこを指す原則にする（A12 を改める）

`docs/testing.md` を新設し、テストの方針の本文はそこにだけ書く。A12 は次の形に改める。

- 見出し: 「テストの方針は `docs/testing.md` に置く」
- 原則: テストの方針は `docs/testing.md` に項目として置く、という置き場所だけを示す。T1 の要約も書かない（`docs/testing.md` は `update-architecture-doc` の手順を通らないので、要約を置くと 2 つの言い回しがずれる）

A12 の ID は CLAUDE.md と lint から引かれているので、廃止せずに残す。

採らなかった案:

- A12 に書き足していく: 1 原則 5 項目の書式に、項目と例の多いテストの方針が収まらない。構造の原則の中でテストの項目が埋もれる。
- `.claude/rules/testing.md` に置く: 毎回読み込まれる利点はあるが、人が読む方針と Claude 向けの手順という今の分担から外れる。

### D2. `docs/testing.md` の項目に `T1` からの ID を振る

レビューの指摘の仕分けでは、`docs/architecture.md` の原則を ID で引いている。テストの指摘も同じく `T3` のように引けるようにする。ID は再利用しない。各項目は「方針」と「理由」を必ず書き、必要なら例を添える。`docs/architecture.md` の原則の 5 項目の書式までは求めない。

### D3. `docs/testing.md` の項目

精査で見つかった余分なテストの種類から、項目を決める。

| ID | 項目 | 主に防ぐもの |
|---|---|---|
| T1 | 残すかは、削ったら見逃す現実的な不具合で決める | 型・標準ライブラリの保証の確認、本番で通らない経路の確認 |
| T2 | 分岐を確かめる場所は 1 か所にし、ほかの層・入口はその責務だけを見る | 入口ごと・層ごとの確かめ直し |
| T3 | 期待値は仕様から書き、実装の式・表・文言・定数・手順を写さない | 実装の写し、内部手順への依存 |
| T4 | 同じ分岐を通る入力は代表に絞る。security.md の検証は例外 | 過剰なケース分け |
| T5 | fake は本物の契約どおりに振る舞わせる | fake の自己検証、本物と違う fake に頼るテスト |
| T6 | 実時間と同期的な待ちに頼らない | 不安定なテスト、actor が塞がる |
| T7 | 単体テストで確かめないものは、手元の確認として tasks に置く | 確かめられない読み上げのテスト |
| T8 | テストを足す・削るときの手順 | 統合で `#expect` を落とすこと、両方を消すこと |

T6 では、起きないことの確認だけは、区切りが無ければ短い固定の待ちを許す。短すぎても見逃すだけで、誤って落ちないためである。起きるはずのことを固定の待ちで待つ今のテストは、`docs/testing.md` の「既知の逸脱」に書く。`docs/testing.md` の項目を改めるときの参照の確かめ方と逸脱の扱いは、`update-architecture-doc` の手順ではなく `docs/testing.md` の「項目の足し方」に置く（検査の対象外なので、手順も文書の中で閉じる）。

T6 の同期的な待ちの理由（`SWIFT_APPROACHABLE_CONCURRENCY` で nonisolated の async 関数が呼び出し元の actor で動くこと）は、ビルド設定の癖として CLAUDE.md にも残す。CLAUDE.md からは `docs/testing.md` の T6 を引く。

### D4. 参照の付け替え

| 場所 | 変更 |
|---|---|
| `docs/architecture.md` の冒頭 | テストの方針は `docs/testing.md` が受け持つ、と分担の段落に足す |
| `docs/architecture.md` の「指摘の仕分けとの関係」 | テストの指摘は `docs/testing.md` の項目に照らして同じ表で扱う、と足す |
| `docs/architecture.md` の A12 | D1 の形に改める |
| `update-architecture-doc` の表 | 「テストの方針」を `docs/architecture.md` の行から外し、`docs/testing.md` の行を足す |
| `.claude/rules/review-process.md` | 指摘を直すかどうかの判断に `docs/testing.md` を足す |
| CLAUDE.md | 「実装上の約束」に `docs/testing.md` への参照を足す。`SWIFT_APPROACHABLE_CONCURRENCY` の注意の参照を T6 に替える |
| `.swiftlint.yml` | `no_thread_sleep` の `message` に T6 を添える（A12 は残す） |

### スレッドと actor の境界・テストでの差し替え

本体のコードとテストのコードは変えない。actor と `@MainActor` の境界（A2）も、差し替えの仕組み（A5）も変えない。

## セキュリティ

本体のトークンの流れは変えない。トークンは `gh auth token` で取得し、`CredentialStore` の actor の中にだけ持ち、リクエストごとにアカウントの API ベースへ送り、アカウントを外すときと終了時に破棄する。

`docs/testing.md` の T1 と T4 には、security.md の「ユニットテストで確かめる」性質（伏せ字、環境変数の除去、オリジン検査、リダイレクト拒否、ホスト名・ユーザー名の検証）について、次の 2 点を書く。性質の本文は security.md に置いたままにし、`docs/testing.md` からは参照するだけにする。

- 確かめるテストの最後の 1 本は必ず残す
- 攻撃の形ごとの引数は削らない

## Risks / Trade-offs

- [`docs/testing.md` は検査の対象外なので、書いたコードの名前が改名で古くなる] → 型名を書くのは例に限り、例が古くなっても方針は読めるようにする。レビューで直す。
- [A12 と `docs/testing.md` の T1 に同じ文が並ぶ] → A12 には置き場所だけを書き、T1 の要約も置かない。
