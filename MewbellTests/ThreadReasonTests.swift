import Testing

@testable import Mewbell

struct ThreadReasonTests {
    /// 表にある値は表の名前、知らない値は `_` を空白にして先頭を大文字にする。
    @Test(arguments: [("review_requested", "Review requested"), ("approval_requested", "Approval requested")])
    func namesReasons(_ reason: String, _ text: String) {
        #expect(ThreadReason.text(reason) == text)
    }
}
