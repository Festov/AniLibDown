import Foundation
import AVFoundation

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published internal(set) var items: [DownloadItem] = []

    private var session: AVAssetDownloadURLSession!
    var activeTasks: [String: AVAssetDownloadTask] = [:]
    var pendingDownloadURLs: [String: URL] = [:]
    var canceledTaskIDs: Set<String> = []
    private var hasRestoredPendingTasks = false
    private var lastProgressPersistAt: Date?
    private let progressPersistInterval: TimeInterval = 1.0
    let storageURL: URL
    private let indexURL: URL
    private let pendingURLsIndexURL: URL

    var groupedReleases: [DownloadReleaseGroup] {
        let grouped = Dictionary(grouping: items, by: \.groupingKey)
        return grouped.map { key, groupItems in
            let sorted = groupItems.sorted { lhs, rhs in
                if lhs.episodeOrdinal == rhs.episodeOrdinal {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.episodeOrdinal < rhs.episodeOrdinal
            }
            return DownloadReleaseGroup(
                id: key,
                releaseId: sorted.first?.releaseId,
                releaseTitle: sorted.first?.releaseTitle ?? "Без названия",
                posterPath: sorted.compactMap(\.posterPath).first,
                items: sorted
            )
        }
        .sorted { $0.releaseTitle.localizedCaseInsensitiveCompare($1.releaseTitle) == .orderedAscending }
    }

    private override init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = documents.appendingPathComponent("Downloads", isDirectory: true)
        indexURL = documents.appendingPathComponent("downloads-index.json")
        pendingURLsIndexURL = documents.appendingPathComponent("downloads-pending-urls.json")
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "top.aniliberty.AniLibDown.downloads")
        session = AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: nil)
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        loadIndex()
        loadPendingURLs()
        restorePendingTasks()
    }

    func isDownloaded(episodeId: String, quality: VideoQuality) -> Bool {
        items.contains { $0.episodeId == episodeId && $0.quality == quality.rawValue && $0.state == .completed }
    }

    func downloadItem(for episodeId: String, quality: VideoQuality) -> DownloadItem? {
        items.first { $0.episodeId == episodeId && $0.quality == quality.rawValue }
    }

    func localPlaybackURL(for episodeId: String, quality: VideoQuality) -> URL? {
        guard let item = downloadItem(for: episodeId, quality: quality),
              item.state == .completed,
              let bookmark = item.localBookmark else {
            return nil
        }
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
    }

    /// Any completed offline quality for the episode (preferred order: requested, then highest).
    func anyLocalPlaybackURL(for episodeId: String, preferred: VideoQuality? = nil) -> (url: URL, quality: VideoQuality)? {
        let order: [VideoQuality]
        if let preferred {
            order = [preferred] + VideoQuality.allCases.filter { $0 != preferred }
        } else {
            order = [.p1080, .p720, .p480]
        }
        for quality in order {
            if let url = localPlaybackURL(for: episodeId, quality: quality) {
                return (url, quality)
            }
        }
        return nil
    }

    func enqueue(
        episode: Episode,
        releaseId: Int,
        releaseTitle: String,
        quality: VideoQuality,
        posterPath: String? = nil
    ) {
        guard let streamURL = quality.streamURL(for: episode) else {
            ToastCenter.shared.show("Нет ссылки для качества \(quality.rawValue)", isError: true)
            return
        }

        if let reason = NetworkMonitor.shared.downloadBlockedReason {
            ToastCenter.shared.show(reason, isError: true)
            return
        }

        items.removeAll {
            $0.episodeId == episode.id &&
            $0.quality == quality.rawValue &&
            $0.state == .failed
        }

        if items.contains(where: {
            $0.episodeId == episode.id &&
            $0.quality == quality.rawValue &&
            ($0.state == .completed || $0.state == .downloading || $0.state == .queued)
        }) {
            return
        }

        let placeholderId = UUID().uuidString
        let placeholder = DownloadItem(
            id: placeholderId,
            episodeId: episode.id,
            releaseId: releaseId,
            releaseTitle: releaseTitle,
            episodeTitle: episode.displayTitle,
            episodeName: episode.name,
            episodeOrdinal: episode.ordinal,
            quality: quality.rawValue,
            remoteURL: streamURL.absoluteString,
            posterPath: posterPath,
            localBookmark: nil,
            progress: 0,
            state: .queued,
            lastError: nil,
            createdAt: Date()
        )
        items.insert(placeholder, at: 0)
        if let posterPath {
            applyPosterPath(posterPath, toReleaseId: releaseId)
            cachePosterLocally(path: posterPath, releaseId: releaseId)
        }
        saveIndex()
        processDownloadQueue()
    }

    func processDownloadQueue() {
        guard NetworkMonitor.shared.canDownload else { return }

        let limit = DownloadSettings.shared.maxConcurrentDownloads
        while activeTasks.count < limit {
            guard let index = items.firstIndex(where: { $0.state == .queued }) else { break }
            startQueuedDownload(at: index)
        }
    }

    private func startQueuedDownload(at index: Int) {
        let item = items[index]
        guard let streamURL = URL(string: item.remoteURL) else {
            updateItem(id: item.id) {
                $0.state = .failed
                $0.lastError = "Некорректный URL"
            }
            return
        }

        let quality = VideoQuality(rawValue: item.quality) ?? .p720
        let asset = AVURLAsset(url: streamURL)
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: "\(item.releaseTitle) - \(item.displayEpisodeTitle)",
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: preferredBitrate(for: quality)]
        ) else {
            updateItem(id: item.id) {
                $0.state = .failed
                $0.lastError = "Не удалось начать загрузку"
            }
            return
        }

        let taskId = task.taskIdentifier.description
        if let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
            items[currentIndex].id = taskId
            items[currentIndex].state = .downloading
            items[currentIndex].lastError = nil
        }
        activeTasks[taskId] = task
        saveIndex()
        task.resume()
    }

    func enqueueAll(
        episodes: [Episode],
        releaseId: Int,
        releaseTitle: String,
        quality: VideoQuality,
        posterPath: String? = nil
    ) {
        for episode in episodes {
            enqueue(
                episode: episode,
                releaseId: releaseId,
                releaseTitle: releaseTitle,
                quality: quality,
                posterPath: posterPath
            )
        }
    }

    func playerSession(for group: DownloadReleaseGroup) -> PlayerSession? {
        let completed = group.items
            .filter { $0.state == .completed }
            .sorted { $0.episodeOrdinal < $1.episodeOrdinal }
        guard !completed.isEmpty else { return nil }

        let episodes = completed.map { item in
            Episode(
                id: item.episodeId,
                name: item.playbackEpisodeName,
                ordinal: item.episodeOrdinal,
                releaseId: item.releaseId
            )
        }

        let preferredQuality = VideoQuality(rawValue: completed.last?.quality ?? VideoQuality.p720.rawValue) ?? .p720
        let startEpisodeId: String
        if let releaseId = group.releaseId,
           let lastId = WatchProgressStore.shared.lastEpisodeId(for: releaseId),
           episodes.contains(where: { $0.id == lastId }) {
            startEpisodeId = lastId
        } else {
            startEpisodeId = episodes[0].id
        }

        return PlayerSession(
            releaseId: group.releaseId ?? 0,
            releaseTitle: group.releaseTitle,
            episodes: episodes,
            startEpisodeId: startEpisodeId,
            quality: preferredQuality,
            preferOffline: true,
            episodesTotal: episodes.count,
            posterPath: group.posterPath
        )
    }

    func cancel(item: DownloadItem) {
        removeDownloadEntry(item, markCanceled: true)
    }

    func delete(item: DownloadItem) {
        removeDownloadEntry(item, markCanceled: true)
    }

    private func removeDownloadEntry(_ item: DownloadItem, markCanceled: Bool) {
        if markCanceled {
            canceledTaskIDs.insert(item.id)
        }
        if let task = activeTasks[item.id] {
            task.cancel()
            activeTasks.removeValue(forKey: item.id)
        }
        removeFiles(for: item)
        pendingDownloadURLs.removeValue(forKey: item.id)
        savePendingURLs()
        items.removeAll { $0.id == item.id }
        saveIndex()
        purgeOrphanedDownloadCache()
    }

    func deleteRelease(group: DownloadReleaseGroup) {
        for item in group.items {
            delete(item: item)
        }
    }

    func retry(item: DownloadItem) {
        guard item.state == .failed else { return }
        guard let releaseId = item.releaseId else { return }
        guard let streamURL = URL(string: item.remoteURL) else { return }

        if let reason = NetworkMonitor.shared.downloadBlockedReason {
            ToastCenter.shared.show(reason, isError: true)
            return
        }

        let quality = VideoQuality(rawValue: item.quality) ?? .p720

        removeDownloadEntry(item, markCanceled: false)

        let placeholderId = UUID().uuidString
        let placeholder = DownloadItem(
            id: placeholderId,
            episodeId: item.episodeId,
            releaseId: releaseId,
            releaseTitle: item.releaseTitle,
            episodeTitle: item.episodeTitle,
            episodeName: item.episodeName,
            episodeOrdinal: item.episodeOrdinal,
            quality: quality.rawValue,
            remoteURL: streamURL.absoluteString,
            posterPath: item.posterPath,
            localBookmark: nil,
            progress: 0,
            state: .queued,
            lastError: nil,
            createdAt: Date()
        )
        items.insert(placeholder, at: 0)
        saveIndex()
        processDownloadQueue()
    }

    func retryFailed(in group: DownloadReleaseGroup) {
        for item in group.items where item.state == .failed {
            retry(item: item)
        }
    }

    func purgeOrphanedDownloadCache() {
        guard hasRestoredPendingTasks else { return }

        let referencedPaths = Set(
            items.compactMap { item -> String? in
                guard let bookmark = item.localBookmark,
                      let url = resolveBookmark(bookmark) else {
                    return nil
                }
                return url.standardizedFileURL.path
            }
            + pendingDownloadURLs.values.map { $0.standardizedFileURL.path }
        )

        for directory in downloadStorageDirectories() {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                let path = url.standardizedFileURL.path
                if url.lastPathComponent == "posters" { continue }
                if referencedPaths.contains(path) { continue }
                removeItemIfExists(at: url)
            }
        }

        let activeIds = Set(items.map(\.id))
        pendingDownloadURLs = pendingDownloadURLs.filter { activeIds.contains($0.key) }
        savePendingURLs()

        items.removeAll { item in
            guard item.state == .completed, let bookmark = item.localBookmark else { return false }
            guard let url = resolveBookmark(bookmark) else { return true }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        saveIndex()
    }

    func purgeAllDownloadData() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()

        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }

        for item in items {
            removeFiles(for: item)
        }

        for url in pendingDownloadURLs.values {
            removeItemIfExists(at: url)
        }
        pendingDownloadURLs.removeAll()
        savePendingURLs()

        for directory in downloadStorageDirectories() {
            wipeDirectoryContents(directory)
        }

        items.removeAll()
        saveIndex()
    }

    private func preferredBitrate(for quality: VideoQuality) -> Int {
        switch quality {
        case .p1080: return 5_000_000
        case .p720: return 2_500_000
        case .p480: return 1_000_000
        }
    }

    func updateItem(id: String, persist: Bool = true, update: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        update(&items[index])
        if persist {
            saveIndex()
        }
    }

    func updateProgress(id: String, progress: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let previous = items[index].progress
        // Avoid republishing for sub-percent noise while still updating UI about every 1%.
        if abs(previous - progress) < 0.01, progress < 0.999 {
            return
        }
        items[index].progress = progress
        let now = Date()
        if let last = lastProgressPersistAt, now.timeIntervalSince(last) < progressPersistInterval {
            return
        }
        lastProgressPersistAt = now
        saveIndex()
    }

    func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            return
        }
        items = decoded
    }

    func saveIndex() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func loadPendingURLs() {
        guard let data = try? Data(contentsOf: pendingURLsIndexURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        pendingDownloadURLs = decoded.compactMapValues { URL(string: $0) }
    }

    func savePendingURLs() {
        let encoded = pendingDownloadURLs.mapValues(\.absoluteString)
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? data.write(to: pendingURLsIndexURL, options: .atomic)
    }

    private func resolveBookmark(_ bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: .withoutImplicitStartAccessing,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func removeFiles(for item: DownloadItem) {
        if let bookmark = item.localBookmark, let url = resolveBookmark(bookmark) {
            removeItemIfExists(at: url)
        }
        if let pendingURL = pendingDownloadURLs[item.id] {
            removeItemIfExists(at: pendingURL)
        }
        removeItemsMatching(remoteURL: item.remoteURL)
    }

    private func removeItemsMatching(remoteURL: String) {
        guard let remote = URL(string: remoteURL) else { return }
        let marker = remote.lastPathComponent
        guard !marker.isEmpty else { return }

        for directory in downloadStorageDirectories() {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.lastPathComponent.contains(marker) || url.path.contains(marker) {
                removeItemIfExists(at: url)
            }
        }
    }

    func removeItemIfExists(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func wipeDirectoryContents(_ directory: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            removeItemIfExists(at: url)
        }
    }

    private func downloadStorageDirectories() -> [URL] {
        var directories = [storageURL]

        if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first,
           let managedAssets = try? FileManager.default.contentsOfDirectory(
               at: library,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ).first(where: { $0.lastPathComponent.hasPrefix("com.apple.UserManagedAssets") }) {
            directories.append(managedAssets)
        }

        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let sessionCache = caches
                .appendingPathComponent("com.apple.nsurlsessiond/Downloads/top.aniliberty.AniLibDown.downloads", isDirectory: true)
            directories.append(sessionCache)
        }

        return directories
    }

    private func restorePendingTasks() {
        session.getAllTasks { tasks in
            Task { @MainActor in
                for task in tasks {
                    guard let downloadTask = task as? AVAssetDownloadTask else { continue }
                    let id = downloadTask.taskIdentifier.description
                    self.activeTasks[id] = downloadTask
                    if !self.items.contains(where: { $0.id == id }) {
                        self.items.insert(
                            DownloadItem(
                                id: id,
                                episodeId: "unknown-\(id)",
                                releaseId: nil,
                                releaseTitle: "Восстановленная загрузка",
                                episodeTitle: downloadTask.urlAsset.url.lastPathComponent,
                                episodeName: nil,
                                episodeOrdinal: 0,
                                quality: VideoQuality.p720.rawValue,
                                remoteURL: downloadTask.urlAsset.url.absoluteString,
                                localBookmark: nil,
                                progress: 0,
                                state: .downloading,
                                createdAt: Date()
                            ),
                            at: 0
                        )
                    }
                }
                self.hasRestoredPendingTasks = true
                self.saveIndex()
                self.purgeOrphanedDownloadCache()
            }
        }
    }
}