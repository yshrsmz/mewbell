## ADDED Requirements

### Requirement: メニューバーのアイコンの右クリックのメニュー

メニューバーの猫アイコンを右クリック、または Control キーを押しながらクリックすると、アプリはポップオーバーを開かずに、アイコンの下にメニューを出さなければならない（SHALL）。VoiceOver の「メニューを表示」の操作でも、同じメニューを出さなければならない（SHALL）。メニューの項目は、上から About Mewbell、区切り、Settings…、Mewbell Releases、区切り、Quit Mewbell の順でなければならない（SHALL）。Settings… には ⌘,、Quit Mewbell には ⌘Q のキーの表示を付け、メニューを開いている間はそのキーで選べなければならない（SHALL）。ポップオーバーを開いているときに右クリックした場合は、ポップオーバーを閉じてメニューを出さなければならない（SHALL）。修飾キーを押さない左クリックの動き（ポップオーバーを開く）は変えてはならない（MUST NOT）。

#### Scenario: 右クリックでメニューが出る

- **GIVEN** Mewbell が起動していて、ポップオーバーは閉じている
- **WHEN** ユーザーがメニューバーの猫アイコンを右クリックする
- **THEN** アイコンの下に About Mewbell、Settings…、Mewbell Releases、Quit Mewbell がこの順に並んだメニューが出る
- **AND** ポップオーバーは開かない

#### Scenario: Control+クリックでもメニューが出る

- **GIVEN** Mewbell が起動していて、ポップオーバーは閉じている
- **WHEN** ユーザーが Control キーを押しながら猫アイコンをクリックする
- **THEN** 右クリックと同じメニューが出る
- **AND** ポップオーバーは開かない

#### Scenario: VoiceOver でメニューを出す

- **GIVEN** VoiceOver を使っていて、メニューバーの猫アイコンにカーソルがある
- **WHEN** ユーザーが VoiceOver の「メニューを表示」（VO+Shift+M）を行う
- **THEN** 右クリックと同じメニューが出る

#### Scenario: 左クリックはポップオーバーのまま

- **GIVEN** Mewbell が起動していて、ポップオーバーは閉じている
- **WHEN** ユーザーが修飾キーを押さずに猫アイコンをクリックする
- **THEN** ポップオーバーが開き、メニューは出ない

#### Scenario: ポップオーバーを開いたまま右クリックする

- **GIVEN** ポップオーバーが開いている
- **WHEN** ユーザーが猫アイコンを右クリックする
- **THEN** ポップオーバーが閉じ、メニューが出る

### Requirement: About パネル

右クリックのメニューの About Mewbell を選ぶと、アプリは macOS 標準の About パネルを前面に出し、アプリ名、バージョン（`CFBundleShortVersionString`）、著作権表示を表示しなければならない（SHALL）。About パネルを開いている間も、Dock に Mewbell のアイコンを出してはならない（MUST NOT）。

#### Scenario: バージョンを確かめる

- **GIVEN** バージョン 0.5.0 の Mewbell が起動していて、ほかのアプリが前面にある
- **WHEN** ユーザーが右クリックのメニューで About Mewbell を選ぶ
- **THEN** ほかのアプリのウィンドウより前面に About パネルが開き、「Mewbell」と「0.5.0」が表示される
- **AND** Dock に Mewbell のアイコンは出ない

### Requirement: Releases ページを開く

右クリックのメニューの Mewbell Releases を選ぶと、アプリは既定のブラウザで `https://github.com/yshrsmz/mewbell/releases` を開かなければならない（SHALL）。開く URL はこの固定の URL だけでなければならず、API のレスポンスや設定の値から組み立ててはならない（MUST NOT）。

#### Scenario: Releases ページが開く

- **GIVEN** Mewbell が起動している
- **WHEN** ユーザーが右クリックのメニューで Mewbell Releases を選ぶ
- **THEN** 既定のブラウザで `https://github.com/yshrsmz/mewbell/releases` が開く

## MODIFIED Requirements

### Requirement: ポップオーバーの表示

メニューバーの猫アイコンをクリックすると、アプリはアイコンの下にポップオーバーを開き、アプリ名「Mewbell」と、設定ウィンドウを開く歯車のボタン（settings「設定ウィンドウを開く」）を表示しなければならない（SHALL）。ポップオーバーに終了のボタンを出してはならない（MUST NOT。終了は「アプリの終了」のとおり右クリックのメニューから行う）。歯車のボタンにはツールチップとアクセシビリティのラベルを付けなければならない（SHALL）。歯車のボタンは、全体の状態にかかわらず（案内画面を出しているときも）表示しなければならない（SHALL）。ポップオーバーの外をクリックすると閉じなければならない（SHALL）。

#### Scenario: アイコンをクリックするとポップオーバーが開く

- **GIVEN** Mewbell が起動していて、ポップオーバーは閉じている
- **WHEN** ユーザーがメニューバーの猫アイコンをクリックする
- **THEN** アイコンの下にポップオーバーが開く
- **AND** ポップオーバーに「Mewbell」と表示される
- **AND** ポップオーバーに歯車のボタンが表示され、Quit ボタンは表示されない

#### Scenario: 外側をクリックすると閉じる

- **GIVEN** ポップオーバーが開いている
- **WHEN** ユーザーがポップオーバーの外側をクリックする
- **THEN** ポップオーバーが閉じる
- **AND** メニューバーの猫アイコンは表示されたまま残る

#### Scenario: 案内画面でも設定を開ける

- **GIVEN** 全体の状態が「gh が見つからない」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 案内と一緒に歯車のボタンが表示される

### Requirement: アプリの終了

右クリックのメニューの Quit Mewbell を選ぶと、アプリは終了しなければならない（MUST）。終了後、メニューバーのアイコンは消えなければならない（MUST）。メニューを開いている間は、⌘Q でも Quit Mewbell を選べなければならない（SHALL）。

#### Scenario: Quit ボタンで終了する

- **GIVEN** 右クリックのメニューが開いている
- **WHEN** ユーザーが Quit Mewbell を選ぶ
- **THEN** Mewbell のプロセスが終了する
- **AND** メニューバーから猫アイコンが消える

#### Scenario: ⌘Q で終了する

- **GIVEN** 右クリックのメニューが開いている
- **WHEN** ユーザーが ⌘Q を押す
- **THEN** Mewbell のプロセスが終了する

### Requirement: 案内画面

全体の状態が「アカウントあり」以外のとき、ポップオーバーはアカウント一覧の代わりに、状態ごとに次の案内を表示しなければならない（SHALL）。案内に出すコマンドにはクリップボードへのコピーボタンを付けなければならない（SHALL）。Mewbell がターミナルを開いたり、案内のコマンドを代わりに実行したりしてはならない（MUST NOT）。gh や API のエラー出力をそのまま表示してはならない（MUST NOT）。

- 確認中: 進行中であることを示す表示
- gh が見つからない: gh のインストール方法（`brew install gh`）と、`https://cli.github.com/` をブラウザで開くボタン。設定で gh のパスを上書きしているときは、代わりに、上書きしたパスの gh を使えないことと、設定ウィンドウを開くボタン
- gh が古い: 検出したバージョン、必要なバージョン（2.40.0 以上）、更新方法（`brew upgrade gh`）

#### Scenario: gh が無いときの案内

- **GIVEN** 全体の状態が「gh が見つからない」で、gh のパスは上書きしていない
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** `brew install gh` とそのコピーボタン、`https://cli.github.com/` を開くボタンが表示される
- **AND** 「Mewbell」の表示と歯車のボタンは残っている

#### Scenario: 開くボタンは固定の URL だけを開く

- **GIVEN** 全体の状態が「gh が見つからない」で、gh のパスは上書きしていない
- **WHEN** ユーザーが `https://cli.github.com/` を開くボタンを押す
- **THEN** 既定のブラウザで `https://cli.github.com/` が開く

#### Scenario: 上書きした gh のパスが使えない

- **GIVEN** ユーザーが設定で gh のパスを `/Users/me/bin/gh` に上書きしていて、そのパスは使えない
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 設定で上書きした gh を使えないことと、設定ウィンドウを開くボタンが表示される
- **AND** `brew install gh` の案内は出ない

### Requirement: ポップオーバーの押せる要素のホバーの塗り

塗りは、システムの文字色を薄く重ねた角丸の塗りにし、独自の色を使ってはならない（MUST NOT）。これは「ポップオーバーの文字の読みやすさの色の指定と背景」が許すボタンの囲みの塗りであり、文字の色を変えてはならない（MUST NOT。すべて既読、すべて Done、リポジトリの Done の確認の文はアクセントカラーのまま）。マウスを外したら塗りを消さなければならない（SHALL）。押せないとき（再読み込み中の再読み込みのボタン、押せないすべて既読とすべて Done のボタン）と、折りたたみの操作を出さない見出しには、塗りを出してはならない（MUST NOT）。塗りを出しても、行と見出しの高さ、アイコンと文字の位置、件名の折り返しは変えてはならない（MUST NOT）。

システム標準の押しボタン（Open Settings…、Open cli.github.com など）は、macOS の標準の見た目のままにし、独自の塗りを付けてはならない（MUST NOT）。

#### Scenario: すべて既読の確認の表示

- **GIVEN** ユーザーが `alice` の「すべて既読」を 1 回押し、`Mark 3 as read?` の表示になっている
- **WHEN** ユーザーがそのボタンにマウスを載せる
- **THEN** 確認の文の後ろに角丸の薄い塗りが出て、文はアクセントカラーのまま

#### Scenario: 押せないボタン

- **GIVEN** `github.com/alice` の取得ができていて、未読が 0 件
- **WHEN** ユーザーが `alice` の見出しのすべて既読のボタンにマウスを載せる
- **THEN** 塗りは出ない

#### Scenario: 折りたたみの操作を出さない見出し

- **GIVEN** `ghe.example.com/dave` が「トークンを取れない」
- **WHEN** ユーザーが `dave` の見出しにマウスを載せる
- **THEN** 見出しに塗りは出ない

#### Scenario: 標準の押しボタン

- **GIVEN** 全体の状態が「gh が見つからない」で、gh のパスは上書きしていない
- **WHEN** ユーザーがポップオーバーの Open cli.github.com ボタンにマウスを載せる
- **THEN** Open cli.github.com ボタンは macOS の標準の押しボタンの見た目のままで、独自の塗りは出ない
