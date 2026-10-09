import Foundation

/// 一覧のスレッドへの操作。
enum ThreadAction: Sendable, Equatable {
    /// 既読にする（`PATCH /notifications/threads/{id}`）
    case read(threadID: String)
    /// Done にする（`DELETE /notifications/threads/{id}`）
    case done(threadID: String)

    var threadID: String {
        switch self {
        case .read(let threadID), .done(let threadID): threadID
        }
    }
}
