import Foundation
import Testing

@testable import Mewbell

/// Debug ビルドの印。テストはスキームの Test 構成（Debug）で動く前提で、Release の側は手元の Release ビルドで確かめる。
struct AppInfoTests {
    @Test func marksTheNameAndVersionOfDebugBuilds() throws {
        let shortVersion = try #require(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        #expect(AppInfo.name == "Mewbell (dev)")
        #expect(AppInfo.version == "\(shortVersion)-dev")
    }
}
