import SwiftUI

/// 一覧の字下げ。見出しの山形の幅と、山形と中身の間隔から決まる。
enum ListLayout {
    /// 見出しの山形の幅
    static let chevronWidth: CGFloat = 16
    /// 山形と見出しの中身の間隔
    static let spacing: CGFloat = 6
    /// 見出しの下に置く中身の字下げ（山形の幅と間隔の分）
    static let contentIndent = chevronWidth + spacing
    /// 案内の文とコマンドの行など、区画の補足の文の中の行の間隔
    static let noteSpacing: CGFloat = 6
}

extension View {
    /// 区画の中の補足の文（トークンと取得の状態、未読が無いこと、操作の失敗、案内とコマンドの行）の体裁。
    /// 文字の大きさを揃え（コマンドの行は自分の等幅の書体のまま）、見出しの中身の字下げに合わせ、幅に合わせて折り返す
    func sectionNote() -> some View {
        font(.subheadline)
            .padding(.leading, ListLayout.contentIndent)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 1 行に収め、収まらないときは省略して、全体をツールチップで出す（見出しのユーザー名・ホスト名・リポジトリ名）。
/// 「…」も入らない幅まで縮むと省略記号の無い切れた字が残るので、「…」が 1 つ入る幅は残す
private struct OneLineTruncation: ViewModifier {
    let fullText: String
    let mode: Text.TruncationMode
    /// 省略記号「…」が 1 つ入る幅。文字の大きさに合わせて変わる
    @ScaledMetric(relativeTo: .subheadline) private var ellipsisWidth: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .lineLimit(1)
            .truncationMode(mode)
            .frame(minWidth: ellipsisWidth, alignment: .leading)
            .help(fullText)
    }
}

extension View {
    /// 1 行に収め、収まらないときは `mode` で省略して、`fullText` をツールチップで出す
    func truncatedToOneLine(_ fullText: String, mode: Text.TruncationMode) -> some View {
        modifier(OneLineTruncation(fullText: fullText, mode: mode))
    }

    /// 見出しに添える小さなカプセル型のバッジ（「active」、折りたたんだときの件数）。幅が足りなくても省略しない。
    func capsuleBadge(_ fill: some ShapeStyle) -> some View {
        fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fill, in: Capsule())
    }
}
