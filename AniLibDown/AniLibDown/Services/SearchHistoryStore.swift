import Foundation

@MainActor
final class SearchHistoryStore: ObservableObject {
    static let shared = SearchHistoryStore()

    @Published private(set) var queries: [String] = []

    private let storageKey = "catalogSearchHistory"
    private let maxItems = 12

    private init() {
        queries = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        queries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        queries.insert(trimmed, at: 0)
        if queries.count > maxItems {
            queries = Array(queries.prefix(maxItems))
        }
        UserDefaults.standard.set(queries, forKey: storageKey)
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
        UserDefaults.standard.set(queries, forKey: storageKey)
    }

    func clear() {
        queries = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
