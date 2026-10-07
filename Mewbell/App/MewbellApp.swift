import SwiftUI

@main
struct MewbellApp: App {
    var body: some Scene {
        MenuBarExtra("Mewbell", systemImage: "cat.fill") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
