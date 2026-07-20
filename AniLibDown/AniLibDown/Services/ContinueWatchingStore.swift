import Foundation

struct ContinueWatchingEntry: Codable, Identifiable, Hashable {
    var id: Int { releaseId }
    let releaseId: Int
    let releaseTitle: String
    let posterPath: String?
    let episodeId: String
    let episodeTitle: String
    let position: Double
    let duration: Int?
    let updatedAt: Date

    var progressFraction: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(1, max(0, position / Double(duration)))
    }
}

@MainActor
final class ContinueWatchingStore: ObservableObject {
    static let shared = ContinueWatchingStore()

    static let appGroupID = "group.top.aniliberty.AniLibDown"

    @Published private(set) var entries: [ContinueWatchingEntry] = []

    private let metadataKey = "continueWatchingMetadata"
    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard
        reload()
    }

    func reload() {
        let progressStore = WatchProgressStore.shared
        var metadata = loadMetadata()
        var result: [ContinueWatchingEntry] = []

        for (releaseIdString, episodeId) in progressStore.allLastEpisodes() {
            guard let releaseId = Int(releaseIdString),
                  let position = progressStore.position(for: episodeId),
                  position > 5 else { continue }

            let meta = metadata[releaseIdString]
            let entry = ContinueWatchingEntry(
                releaseId: releaseId,
                releaseTitle: meta?.releaseTitle ?? "Релиз #\(releaseId)",
                posterPath: meta?.posterPath,
                episodeId: episodeId,
                episodeTitle: meta?.episodeTitle ?? "Серия",
                position: position,
                duration: meta?.duration,
                updatedAt: meta?.updatedAt ?? Date()
            )
            result.append(entry)
        }

        entries = result.sorted { $0.updatedAt > $1.updatedAt }
    }

    func updateMetadata(
        releaseId: Int,
        releaseTitle: String,
        posterPath: String?,
        episodeId: String,
        episodeTitle: String,
        duration: Int?
    ) {
        var metadata = loadMetadata()
        metadata[String(releaseId)] = ContinueMetadata(
            releaseTitle: releaseTitle,
            posterPath: posterPath,
            episodeTitle: episodeTitle,
            duration: duration,
            updatedAt: Date()
        )
        saveMetadata(metadata)
        reload()
    }

    func remove(releaseId: Int) {
        var metadata = loadMetadata()
        metadata.removeValue(forKey: String(releaseId))
        saveMetadata(metadata)
        reload()
    }

    private struct ContinueMetadata: Codable {
        let releaseTitle: String
        let posterPath: String?
        let episodeTitle: String
        let duration: Int?
        let updatedAt: Date
    }

    private func loadMetadata() -> [String: ContinueMetadata] {
        guard let data = defaults.data(forKey: metadataKey),
              let decoded = try? JSONDecoder().decode([String: ContinueMetadata].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveMetadata(_ metadata: [String: ContinueMetadata]) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        defaults.set(data, forKey: metadataKey)
    }
}
