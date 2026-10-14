import AppKit
import SwiftUI

/// ユーザーがターミナルで実行するコマンドと、クリップボードへのコピーボタン。
/// Mewbell がコマンドを代わりに実行することはない。
struct CommandRow: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    // 記号を替えても、押せる範囲の高さが変わらないように（コピーの記号の高さにそろえる）
                    .frame(width: 16, height: 18)
            }
            .buttonStyle(HoverHighlightButtonStyle(outset: 3))
            .help("Copy to clipboard")
            .accessibilityLabel("Copy \(command)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: command) { copied = false }
    }
}

#Preview {
    CommandRow(command: "gh auth login --hostname ghe.example.com")
        .padding()
        .frame(width: 320)
}
