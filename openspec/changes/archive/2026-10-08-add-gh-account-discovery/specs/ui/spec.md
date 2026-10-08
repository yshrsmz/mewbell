# Spec Delta

## ADDED Requirements

### Requirement: アカウント一覧の表示

全体の状態が「アカウントあり」のとき、ポップオーバーはアカウントをホストごとにまとめて表示しなければならない（SHALL）。ホストの見出しにはホスト名とホスト種別（GitHub.com / GHE Cloud / Enterprise Server）を出し、その下に各アカウントのユーザー名と状態（取得中 / 使える / トークンを取れない）を出さなければならない（SHALL）。gh のアクティブなアカウントには、そうと分かる印を付けなければならない（SHALL）。トークンの値やその一部を表示してはならない（MUST NOT）。

#### Scenario: 2 つのホストのアカウントを表示する

- **GIVEN** `github.com/alice`（使える、アクティブ）と `acme.ghe.com/dave`（使える）がある
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 「github.com — GitHub.com」の下に `alice` がアクティブの印付きで、「acme.ghe.com — GHE Cloud」の下に `dave` が表示される
- **AND** どちらも「使える」状態として表示される

#### Scenario: トークンを取れないアカウント

- **GIVEN** `ghe.example.com/dave` が「トークンを取れない」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `dave` の行に警告と、実行すべきコマンド `gh auth login --hostname ghe.example.com` が表示される
- **AND** コマンドをクリップボードにコピーするボタンがある

### Requirement: 案内画面

全体の状態が「アカウントあり」以外のとき、ポップオーバーはアカウント一覧の代わりに、状態ごとに次の案内を表示しなければならない（SHALL）。案内に出すコマンドにはクリップボードへのコピーボタンを付けなければならない（SHALL）。Mewbell がターミナルを開いたり、案内のコマンドを代わりに実行したりしてはならない（MUST NOT）。gh や API のエラー出力をそのまま表示してはならない（MUST NOT）。

- 確認中: 進行中であることを示す表示
- gh が見つからない: gh のインストール方法（`brew install gh`）と、`https://cli.github.com/` をブラウザで開くボタン
- gh が古い: 検出したバージョン、必要なバージョン（2.40.0 以上）、更新方法（`brew upgrade gh`）
- gh を実行できない: gh が期待どおりに応答しなかったことと、手元で確かめるコマンド（`gh --version`）。確かめた後に再読み込みするよう促す
- `hosts.yml` を読めない: 読もうとしたファイルのパスと、`gh auth status` で状態を確かめるよう促す文
- 未ログイン: `gh auth login`（GHE の場合は `gh auth login --hostname <host>`）でログインするよう促す文

#### Scenario: gh が無いときの案内

- **GIVEN** 全体の状態が「gh が見つからない」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `brew install gh` とそのコピーボタン、`https://cli.github.com/` を開くボタンが表示される
- **AND** 「Mewbell」の表示と Quit ボタンは残っている

#### Scenario: 開くボタンは固定の URL だけを開く

- **GIVEN** 全体の状態が「gh が見つからない」
- **WHEN** ユーザーが `https://cli.github.com/` を開くボタンを押す
- **THEN** 既定のブラウザで `https://cli.github.com/` が開く

#### Scenario: 未ログインの案内

- **GIVEN** 全体の状態が「未ログイン」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `gh auth login` とそのコピーボタンが表示される

### Requirement: 再読み込みボタン

ポップオーバーには、gh の検出とアカウントの読み取りをやり直す「再読み込み」ボタンがなければならない（SHALL）。読み直している間はボタンを押せないようにしなければならない（SHALL）。

#### Scenario: gh をインストールした後に再読み込みする

- **GIVEN** 全体の状態が「gh が見つからない」で、ユーザーがその後 `brew install gh` と `gh auth login` を済ませた
- **WHEN** ユーザーが「再読み込み」を押す
- **THEN** 確認中の表示を経て、アカウント一覧が表示される
