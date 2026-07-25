import Combine
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

    func exportJSON() throws -> Data {
        let encoded = links.reduce(into: [String: ShikimoriLink]()) { result, entry in
            result[String(entry.key)] = entry.value
        }
        let export = ShikimoriLinksExport(version: 1, links: encoded, exportedAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    func importJSON(_ data: Data, merge: Bool = true) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ShikimoriLinksExport.self, from: data)
        var imported = 0
        if !merge {
            links.removeAll()
        }
        for (key, link) in payload.links {
            guard let releaseId = Int(key) else { continue }
            links[releaseId] = link
            imported += 1
        }
        save()
        return imported
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

struct ShikimoriLinksExport: Codable {
    let version: Int
    let links: [String: ShikimoriLink]
    let exportedAt: Date
}
