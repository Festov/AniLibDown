import Foundation

struct WatchProgress: Codable {
    let episodeId: String
    let position: Double
    let updatedAt: Date
}

@MainActor
final class WatchProgressStore {
    static let shared = WatchProgressStore()

    private let defaults: UserDefaults
    private let progressKey = "watchProgressByEpisode"
    private let lastEpisodeKey = "lastWatchedEpisodeByRelease"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func position(for episodeId: String) -> Double? {
        loadProgress()[episodeId]?.position
    }

    func lastEpisodeId(for releaseId: Int) -> String? {
        loadLastEpisodes()[String(releaseId)]
    }

    func save(
        position: Double,
        episodeId: String,
        releaseId: Int,
        releaseTitle: String? = nil,
        posterPath: String? = nil,
        episodeTitle: String? = nil,
        duration: Int? = nil
    ) {
        guard position > 5 else { return }

        var progress = loadProgress()
        progress[episodeId] = WatchProgress(
            episodeId: episodeId,
            position: position,
            updatedAt: Date()
        )
        storeProgress(progress)

        var lastEpisodes = loadLastEpisodes()
        lastEpisodes[String(releaseId)] = episodeId
        defaults.set(lastEpisodes, forKey: lastEpisodeKey)

        if let releaseTitle, let episodeTitle {
            ContinueWatchingStore.shared.updateMetadata(
                releaseId: releaseId,
                releaseTitle: releaseTitle,
                posterPath: posterPath,
                episodeId: episodeId,
                episodeTitle: episodeTitle,
                duration: duration
            )
        } else {
            ContinueWatchingStore.shared.reload()
        }
    }

    func clearPosition(for episodeId: String) {
        var progress = loadProgress()
        progress.removeValue(forKey: episodeId)
        storeProgress(progress)
    }

    func progressFraction(for episodeId: String, duration: Int?) -> Double {
        guard let position = position(for: episodeId),
              let duration,
              duration > 0 else {
            return 0
        }
        return min(1, max(0, position / Double(duration)))
    }

    func clearAll() {
        defaults.removeObject(forKey: progressKey)
        defaults.removeObject(forKey: lastEpisodeKey)
        ContinueWatchingStore.shared.reload()
    }

    func allLastEpisodes() -> [String: String] {
        loadLastEpisodes()
    }

    private func loadProgress() -> [String: WatchProgress] {
        guard let data = defaults.data(forKey: progressKey),
              let decoded = try? JSONDecoder().decode([String: WatchProgress].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func storeProgress(_ progress: [String: WatchProgress]) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: progressKey)
    }

    private func loadLastEpisodes() -> [String: String] {
        defaults.dictionary(forKey: lastEpisodeKey) as? [String: String] ?? [:]
    }
}
