import AppKit
import SwiftUI

struct MenuBarContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mewbell")
                .font(.headline)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 240, alignment: .leading)
    }
}

#Preview {
    MenuBarContentView()
}
