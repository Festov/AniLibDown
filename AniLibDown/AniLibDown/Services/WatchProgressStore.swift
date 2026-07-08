import Foundation

struct WatchProgress: Codable {
    let episodeId: String
    let position: Double
    let updatedAt: Date
}

@MainActor
final class WatchProgressStore {
    static let shared = WatchProgressStore()

    private let defaults = UserDefaults.standard
    private let progressKey = "watchProgressByEpisode"
    private let lastEpisodeKey = "lastWatchedEpisodeByRelease"

    private init() {}

    func position(for episodeId: String) -> Double? {
        loadProgress()[episodeId]?.position
    }

    func lastEpisodeId(for releaseId: Int) -> String? {
        loadLastEpisodes()[String(releaseId)]
    }

    func save(position: Double, episodeId: String, releaseId: Int) {
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
    }

    func clearPosition(for episodeId: String) {
        var progress = loadProgress()
        progress.removeValue(forKey: episodeId)
        storeProgress(progress)
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
