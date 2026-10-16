import Foundation

/// 1 つのリポジトリのスレッド。
struct RepositoryGroup: Identifiable, Equatable, Sendable {
    let repository: RepositoryName
    /// 更新日時が新しい順
    let threads: [NotificationThread]

    var id: String { repository.description }

    /// リポジトリごとにまとめる。リポジトリは最新のスレッドの更新日時が新しい順、スレッドは更新日時が新しい順。
    static func groups(from threads: [NotificationThread]) -> [RepositoryGroup] {
        Dictionary(grouping: threads, by: \.repository)
            .map { repository, threads in
                RepositoryGroup(repository: repository, threads: threads.sorted(by: NotificationThread.isNewer))
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.threads[0].updatedAt
                let rhsDate = rhs.threads[0].updatedAt
                return lhsDate != rhsDate ? lhsDate > rhsDate : lhs.id < rhs.id
            }
    }
}
