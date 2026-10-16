import SwiftUI

/// 一覧の寸法（見出しの字下げと、区画の中の文の行の間隔）。
enum ListLayout {
    /// アイコンの列の幅。見出しの山形、アカウントの見出しのトークンの状態、スレッドの行の種類のアイコンを、この幅の列の中央に置く。
    /// 記号は書体の大きさのまま描くので、どの記号の配置の枠も倍率 1 と 2 の画面で収まる幅にする（`IconColumnTests`）
    static let iconColumnWidth: CGFloat = 24
    /// アイコンの列と、見出しや行の中身の間隔
    static let spacing: CGFloat = 6
    /// 見出しの下に置く中身の字下げ（アイコンの列の幅と間隔の分）
    static let contentIndent = iconColumnWidth + spacing
    /// アカウントとリポジトリの見出しの高さの下限（開閉の押せる範囲の高さ）。macOS のサイドバーの小さい行と同じ。
    /// 中身がこれより高いときは中身に合わせる
    static let headingHeight: CGFloat = 24
    /// 区画の中の文（取得とトークンの状態、未読が無いこと、操作の失敗、案内とコマンドの行）の、行と行の間隔
    static let noteSpacing: CGFloat = 6
    /// スレッドの行とリポジトリ・アカウントの見出しの、アイコンのボタンの枠の大きさ（`ActionIcon`）
    static let actionIconSize: CGFloat = 22
}

/// スレッドの行とリポジトリ・アカウントの見出しの、アイコンのボタンの記号。
/// 記号を `ListLayout.actionIconSize` 四方の枠の中央に置き、どのボタンも同じ大きさと押せる範囲にする
struct ActionIcon: View {
    let systemName: String

    init(_ systemName: String) {
        self.systemName = systemName
    }

    var body: some View {
        Image(systemName: systemName)
            .frame(width: ListLayout.actionIconSize, height: ListLayout.actionIconSize)
    }
}

extension View {
    /// 区画の中の文（取得とトークンの状態、未読が無いこと、操作の失敗、案内とコマンドの行）の体裁。
    /// 薄い色にしてよい「補足の情報」とは別で、色はここでは決めない。
    /// 文字の大きさを揃え（コマンドの行は自分の等幅の書体のまま）、見出しの中身の字下げに合わせ、幅に合わせて折り返す。
    /// 行の間隔は付けない。複数の行を並べるときは、呼び出し側で `ListLayout.noteSpacing` の `VStack` に入れる
    func sectionNote() -> some View {
        font(.subheadline)
            .padding(.leading, ListLayout.contentIndent)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 見出しの名前（ユーザー名・ホスト名・リポジトリ名）を 1 行で出す。全体が入るときはそのまま出し、
/// 入らないときだけ `truncation` で省略して、全体をツールチップで出す（macOS の文字欄が省略したときだけ全体を出すのと同じ）。
/// 「…」も入らない幅まで縮むと省略記号の無い切れた字が残るので、同じ書体の「…」の幅は残す
struct OneLineText: View {
    let text: String
    let truncation: Text.TruncationMode

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .fixedSize()
            // 見えない「…」を重ねて、同じ書体の省略記号の幅より狭くならないようにする
            ZStack(alignment: .leading) {
                Text("…").fixedSize().hidden()
                Text(text)
                    .lineLimit(1)
                    .truncationMode(truncation)
            }
            .help(text)
        }
    }
}

extension View {
    /// 見出しに添える小さなカプセル型のバッジ（「active」、折りたたんだときの件数）。幅が足りなくても省略しない。
    func capsuleBadge(_ fill: some ShapeStyle) -> some View {
        fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fill, in: Capsule())
    }
}
