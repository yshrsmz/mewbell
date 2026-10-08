import os

extension Logger {
    /// Mewbell のサブシステムで、`category` に分けたロガー。
    init(category: String) {
        self.init(subsystem: "com.codingfeline.mewbell", category: category)
    }
}
