import SwiftUI

@MainActor
final class CollectionStatusStore: ObservableObject {
    static let shared = CollectionStatusStore()

    @Published private(set) var memberships: [Int: CollectionType] = [:]

    private init() {}

    func refresh() async {
        guard AuthService.shared.isAuthenticated else {
            memberships = [:]
            return
        }

        do {
            let entries = try await APIClient.shared.getCollectionIds()
            var map: [Int: CollectionType] = [:]
            for entry in entries {
                map[entry.releaseId] = entry.type
            }
            memberships = map
        } catch {
            memberships = [:]
        }
    }

    func status(for releaseId: Int) -> CollectionType? {
        memberships[releaseId]
    }

    func setStatus(releaseId: Int, type: CollectionType?) async throws {
        if let type {
            try await APIClient.shared.addToCollection(releaseId: releaseId, type: type)
            memberships[releaseId] = type
        } else if memberships[releaseId] != nil {
            try await APIClient.shared.removeFromCollection(releaseId: releaseId)
            memberships.removeValue(forKey: releaseId)
        }
    }
}
