## MODIFIED Requirements

### Requirement: About パネル

右クリックのメニューの About Mewbell を選ぶと、アプリは macOS 標準の About パネルを前面に出し、アプリ名、バージョン（distribution「Debug ビルドのバージョンの表示」のとおり、Release では `CFBundleShortVersionString`、Debug ではその後ろに `-dev` を付けたもの）、著作権表示を表示しなければならない（SHALL）。About パネルを開いている間も、Dock に Mewbell のアイコンを出してはならない（MUST NOT）。

#### Scenario: バージョンを確かめる

- **GIVEN** バージョン 0.5.0 の Mewbell（Release 構成）が起動していて、ほかのアプリが前面にある
- **WHEN** ユーザーが右クリックのメニューで About Mewbell を選ぶ
- **THEN** ほかのアプリのウィンドウより前面に About パネルが開き、「Mewbell」と「0.5.0」が表示される
- **AND** Dock に Mewbell のアイコンは出ない

#### Scenario: Debug ビルドのバージョンを確かめる

- **GIVEN** バージョン 0.5.0 の Mewbell を Debug 構成でビルドして起動している
- **WHEN** ユーザーが右クリックのメニューで About Mewbell を選ぶ
- **THEN** About パネルに「0.5.0-dev」が表示される
