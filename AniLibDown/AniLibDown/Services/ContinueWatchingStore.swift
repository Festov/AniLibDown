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

    @Published private(set) var entries: [ContinueWatchingEntry] = []

    /// Sideload не даёт App Groups — храним в стандартных UserDefaults.
    private let metadataKey = "continueWatchingMetadata"
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        let progressStore = WatchProgressStore.shared
        let metadata = loadMetadata()
        var result: [ContinueWatchingEntry] = []

        for (releaseIdString, episodeId) in progressStore.allLastEpisodes() {
            guard let releaseId = Int(releaseIdString),
                  let position = progressStore.position(for: episodeId),
                  position > 5 else { continue }

            guard let meta = metadata[releaseIdString] else { continue }

            let entry = ContinueWatchingEntry(
                releaseId: releaseId,
                releaseTitle: meta.releaseTitle,
                posterPath: meta.posterPath,
                episodeId: episodeId,
                episodeTitle: meta.episodeTitle,
                position: position,
                duration: meta.duration,
                updatedAt: meta.updatedAt
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
        let existing = metadata[String(releaseId)]
        metadata[String(releaseId)] = ContinueMetadata(
            releaseTitle: releaseTitle,
            posterPath: posterPath ?? existing?.posterPath,
            episodeTitle: episodeTitle,
            duration: duration ?? existing?.duration,
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
