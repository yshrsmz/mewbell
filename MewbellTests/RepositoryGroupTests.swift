import Foundation
import Testing

@testable import Mewbell

private func thread(id: String, repository: String, updatedAt: TimeInterval) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: updatedAt), title: "Thread \(id)",
        kind: .pullRequest, subjectURL: nil, repository: try #require(RepositoryName(fullName: repository)),
        detailsSubject: nil, details: nil
    )
}

struct RepositoryGroupTests {
    @Test func ordersRepositoriesAndThreadsByTheNewestUpdate() throws {
        let groups = RepositoryGroup.groups(from: [
            try thread(id: "1", repository: "octo/app", updatedAt: 100),
            try thread(id: "2", repository: "octo/lib", updatedAt: 300),
            try thread(id: "3", repository: "octo/app", updatedAt: 200),
            try thread(id: "4", repository: "acme/web", updatedAt: 50),
        ])
        #expect(groups.map(\.id) == ["octo/lib", "octo/app", "acme/web"])
        #expect(groups[1].threads.map(\.id) == ["3", "1"])
    }
}
