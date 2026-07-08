import Foundation

@MainActor
final class ShikimoriLinkStore: ObservableObject {
    static let shared = ShikimoriLinkStore()

    @Published private(set) var links: [Int: ShikimoriLink] = [:]

    private let storageKey = "shikimoriLinksByRelease"

    private init() {
        load()
    }

    func link(for releaseId: Int) -> ShikimoriLink? {
        links[releaseId]
    }

    func setLink(_ link: ShikimoriLink?, for releaseId: Int) {
        if let link {
            links[releaseId] = link
        } else {
            links.removeValue(forKey: releaseId)
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: ShikimoriLink].self, from: data) else {
            links = [:]
            return
        }
        links = decoded.reduce(into: [:]) { result, entry in
            if let releaseId = Int(entry.key) {
                result[releaseId] = entry.value
            }
        }
    }

    private func save() {
        let encoded = links.reduce(into: [String: ShikimoriLink]()) { result, entry in
            result[String(entry.key)] = entry.value
        }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
