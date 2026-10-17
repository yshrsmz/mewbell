## MODIFIED Requirements

### Requirement: ポップオーバーの表示

メニューバーの猫アイコンをクリックすると、アプリはアイコンの下にポップオーバーを開き、表示用のアプリ名（distribution「Debug ビルドの表示用のアプリ名とバージョン」。Release では「Mewbell」、Debug では「Mewbell (dev)」）と、設定ウィンドウを開く歯車のボタン（settings「設定ウィンドウを開く」）を表示しなければならない（SHALL）。ポップオーバーに終了のボタンを出してはならない（MUST NOT。終了は「アプリの終了」のとおり右クリックのメニューから行う）。歯車のボタンにはツールチップとアクセシビリティのラベルを付けなければならない（SHALL）。歯車のボタンは、全体の状態にかかわらず（案内画面を出しているときも）表示しなければならない（SHALL）。ポップオーバーの外をクリックすると閉じなければならない（SHALL）。

#### Scenario: アイコンをクリックするとポップオーバーが開く

- **GIVEN** Mewbell（Release 構成）が起動していて、ポップオーバーは閉じている
- **WHEN** ユーザーがメニューバーの猫アイコンをクリックする
- **THEN** アイコンの下にポップオーバーが開く
- **AND** ポップオーバーに「Mewbell」と表示される
- **AND** ポップオーバーに歯車のボタンが表示され、Quit ボタンは表示されない

#### Scenario: Debug ビルドのポップオーバー

- **GIVEN** Debug 構成でビルドした Mewbell が起動している
- **WHEN** ユーザーがメニューバーの猫アイコンをクリックする
- **THEN** ポップオーバーに「Mewbell (dev)」と表示される

#### Scenario: 外側をクリックすると閉じる

- **GIVEN** ポップオーバーが開いている
- **WHEN** ユーザーがポップオーバーの外側をクリックする
- **THEN** ポップオーバーが閉じる
- **AND** メニューバーの猫アイコンは表示されたまま残る

#### Scenario: 案内画面でも設定を開ける

- **GIVEN** 全体の状態が「gh が見つからない」
- **WHEN** ユーザーがポップオーバーを開く
- **THEN** 案内と一緒に歯車のボタンが表示される

### Requirement: About パネル

右クリックのメニューの About Mewbell を選ぶと、アプリは macOS 標準の About パネルを前面に出し、アプリ名、表示用のバージョン（distribution「Debug ビルドの表示用のアプリ名とバージョン」。Release では `CFBundleShortVersionString`、Debug ではその後ろに `-dev` を付けたもの）、著作権表示を表示しなければならない（SHALL）。About パネルのアプリ名は、Debug でも `Mewbell` のままでよい（MAY）。About パネルを開いている間も、Dock に Mewbell のアイコンを出してはならない（MUST NOT）。

#### Scenario: バージョンを確かめる

- **GIVEN** バージョン 0.5.0 の Mewbell（Release 構成）が起動していて、ほかのアプリが前面にある
- **WHEN** ユーザーが右クリックのメニューで About Mewbell を選ぶ
- **THEN** ほかのアプリのウィンドウより前面に About パネルが開き、「Mewbell」と「0.5.0」が表示される
- **AND** Dock に Mewbell のアイコンは出ない

#### Scenario: Debug ビルドのバージョンを確かめる

- **GIVEN** バージョン 0.5.0 の Mewbell を Debug 構成でビルドして起動している
- **WHEN** ユーザーが右クリックのメニューで About Mewbell を選ぶ
- **THEN** About パネルに「0.5.0-dev」が表示される
