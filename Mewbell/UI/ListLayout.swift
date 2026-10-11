import SwiftUI

/// 一覧の字下げ。見出しの山形の幅と、山形と中身の間隔から決まる。
enum ListLayout {
    /// 見出しの山形の幅
    static let chevronWidth: CGFloat = 16
    /// 山形と見出しの中身の間隔
    static let spacing: CGFloat = 6
    /// 見出しの下に置く中身の字下げ（山形の幅と間隔の分）
    static let contentIndent = chevronWidth + spacing
    /// 区画の中の文（取得とトークンの状態、未読が無いこと、操作の失敗、案内とコマンドの行）の、行と行の間隔
    static let noteSpacing: CGFloat = 6
}

extension View {
    /// 区画の中の文（取得とトークンの状態、未読が無いこと、操作の失敗、案内とコマンドの行）の体裁。
    /// 薄い色にしてよい「補足の情報」とは別で、色はここでは決めない。
    /// 文字の大きさを揃え（コマンドの行は自分の等幅の書体のまま）、見出しの中身の字下げに合わせ、幅に合わせて折り返す
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
