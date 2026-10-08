import Foundation
import Testing

struct MewbellTests {
    @Test func hostAppIsLoaded() {
        #expect(Bundle.main.bundleIdentifier == "com.codingfeline.mewbell")
    }
}
