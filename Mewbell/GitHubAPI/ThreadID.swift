/// 通知のスレッド ID の検証。API の URL のパスに入れる前と、macOS の通知から戻ってきた値に使う。
enum ThreadID {
    /// 1〜20 桁の ASCII の数字か。
    static func isValid(_ id: String) -> Bool {
        (1...20).contains(id.utf8.count) && id.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    }
}
