import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct WatchProgress: Codable {
    let episodeId: String
    let position: Double
    let updatedAt: Date
}

@MainActor
final class WatchProgressStore {
    static let shared = WatchProgressStore()

    /// Состояние, целиком сохраняемое в один JSON-файл.
    struct PersistedState: Codable {
        var progress: [String: WatchProgress] = [:]
        var lastEpisodes: [String: String] = [:]
    }

    /// Ключи старого хранилища в UserDefaults — оставлены только для миграции.
    private let legacyProgressKey = "watchProgressByEpisode"
    private let legacyLastEpisodeKey = "lastWatchedEpisodeByRelease"

    private let defaults: UserDefaults
    private let fileURL: URL
    private let persistDebounceNanos: UInt64

    private var state: PersistedState
    private var persistTask: Task<Void, Never>?
    private var backgroundObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - defaults: используется только для чтения/очистки устаревших ключей при миграции.
    ///   - directory: каталог для файла состояния (по умолчанию Application Support/AniLibDown).
    ///   - debounce: задержка отложенной записи на диск в секундах.
    init(
        defaults: UserDefaults = .standard,
        directory: URL? = nil,
        debounce: TimeInterval = 1.0
    ) {
        self.defaults = defaults
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniLibDown", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("watch-progress.json")
        self.persistDebounceNanos = UInt64(max(0, debounce) * 1_000_000_000)

        if let persisted = Self.loadState(from: fileURL) {
            self.state = persisted
        } else if let migrated = Self.migrateLegacy(
            defaults: defaults,
            progressKey: legacyProgressKey,
            lastEpisodeKey: legacyLastEpisodeKey
        ) {
            // Переносим данные из UserDefaults и сразу фиксируем на диске.
            self.state = migrated
            persistNow()
        } else {
            self.state = PersistedState()
        }

        #if canImport(UIKit)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.flush()
            }
        }
        #endif
    }

    deinit {
        persistTask?.cancel()
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    // MARK: - Публичный API

    func position(for episodeId: String) -> Double? {
        state.progress[episodeId]?.position
    }

    func lastEpisodeId(for releaseId: Int) -> String? {
        state.lastEpisodes[String(releaseId)]
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

        state.progress[episodeId] = WatchProgress(
            episodeId: episodeId,
            position: position,
            updatedAt: Date()
        )
        state.lastEpisodes[String(releaseId)] = episodeId
        schedulePersist()

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

    func clearRelease(releaseId: Int) {
        let key = String(releaseId)
        if let episodeId = state.lastEpisodes[key] {
            state.progress.removeValue(forKey: episodeId)
        }
        state.lastEpisodes.removeValue(forKey: key)
        schedulePersist()
        ContinueWatchingStore.shared.remove(releaseId: releaseId)
        ContinueWatchingStore.shared.reload()
    }

    func clearPosition(for episodeId: String) {
        state.progress.removeValue(forKey: episodeId)

        // Drop continue-watching card if this was the last episode for a release.
        let affected = state.lastEpisodes.filter { $0.value == episodeId }.map(\.key)
        for key in affected {
            state.lastEpisodes.removeValue(forKey: key)
            if let releaseId = Int(key) {
                ContinueWatchingStore.shared.remove(releaseId: releaseId)
            }
        }
        schedulePersist()
        ContinueWatchingStore.shared.reload()
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
        state = PersistedState()
        defaults.removeObject(forKey: legacyProgressKey)
        defaults.removeObject(forKey: legacyLastEpisodeKey)
        flush()
        ContinueWatchingStore.shared.reload()
    }

    func allLastEpisodes() -> [String: String] {
        state.lastEpisodes
    }

    /// Немедленно записывает состояние на диск, отменяя отложенную запись.
    /// Вызывается автоматически при уходе приложения в фон.
    func flush() {
        persistTask?.cancel()
        persistTask = nil
        persistNow()
    }

    // MARK: - Персистентность

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self, debounce = persistDebounceNanos] in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    private func persistNow() {
        do {
            let data = try JSONEncoder().encode(state)
            // .atomic: запись идёт во временный файл с последующим rename,
            // поэтому внезапное завершение приложения не портит файл.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("WatchProgressStore: не удалось сохранить состояние: \(error)")
        }
    }

    private static func loadState(from url: URL) -> PersistedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            // Файл повреждён: не затираем его молча, а откладываем рядом для диагностики.
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("watch-progress.corrupted-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }

    private static func migrateLegacy(
        defaults: UserDefaults,
        progressKey: String,
        lastEpisodeKey: String
    ) -> PersistedState? {
        let progressData = defaults.data(forKey: progressKey)
        let lastEpisodes = defaults.dictionary(forKey: lastEpisodeKey) as? [String: String]
        guard progressData != nil || lastEpisodes != nil else { return nil }

        var migrated = PersistedState()
        if let progressData,
           let decoded = try? JSONDecoder().decode([String: WatchProgress].self, from: progressData) {
            migrated.progress = decoded
        }
        migrated.lastEpisodes = lastEpisodes ?? [:]

        defaults.removeObject(forKey: progressKey)
        defaults.removeObject(forKey: lastEpisodeKey)
        return migrated
    }
}
