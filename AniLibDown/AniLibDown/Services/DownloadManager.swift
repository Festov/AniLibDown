import Foundation
import AVFoundation

struct DownloadItem: Identifiable, Codable, Hashable {
    var id: String
    let episodeId: String
    let releaseId: Int?
    let releaseTitle: String
    let episodeTitle: String
    let episodeName: String?
    let episodeOrdinal: Double
    let quality: String
    let remoteURL: String
    var posterPath: String?
    var localBookmark: Data?
    var progress: Double
    var state: DownloadState
    var lastError: String?
    var createdAt: Date

    enum DownloadState: String, Codable {
        case queued
        case downloading
        case completed
        case failed
    }

    var groupingKey: String {
        if let releaseId {
            return "release:\(releaseId)"
        }
        return "title:\(releaseTitle)"
    }

    var displayEpisodeTitle: String {
        if let episodeName, !episodeName.isEmpty {
            return formattedEpisodeTitle(name: episodeName)
        }
        return episodeTitle
    }

    var playbackEpisodeName: String? {
        if let episodeName, !episodeName.isEmpty {
            return episodeName
        }
        guard episodeTitle.hasPrefix("Серия ") else { return nil }
        let parts = episodeTitle.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let name = parts[1].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func formattedEpisodeTitle(name: String) -> String {
        let ordinalText = ReleaseFormatting.displayEpisodeOrdinal(episodeOrdinal)
        return "Серия \(ordinalText): \(name)"
    }

    init(
        id: String,
        episodeId: String,
        releaseId: Int?,
        releaseTitle: String,
        episodeTitle: String,
        episodeName: String?,
        episodeOrdinal: Double,
        quality: String,
        remoteURL: String,
        posterPath: String? = nil,
        localBookmark: Data?,
        progress: Double,
        state: DownloadState,
        lastError: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.episodeId = episodeId
        self.releaseId = releaseId
        self.releaseTitle = releaseTitle
        self.episodeTitle = episodeTitle
        self.episodeName = episodeName
        self.episodeOrdinal = episodeOrdinal
        self.quality = quality
        self.remoteURL = remoteURL
        self.posterPath = posterPath
        self.localBookmark = localBookmark
        self.progress = progress
        self.state = state
        self.lastError = lastError
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        episodeId = try container.decode(String.self, forKey: .episodeId)
        releaseId = try container.decodeIfPresent(Int.self, forKey: .releaseId)
        releaseTitle = try container.decode(String.self, forKey: .releaseTitle)
        episodeTitle = try container.decode(String.self, forKey: .episodeTitle)
        episodeName = try container.decodeIfPresent(String.self, forKey: .episodeName)
        episodeOrdinal = try container.decodeIfPresent(Double.self, forKey: .episodeOrdinal) ?? 0
        quality = try container.decode(String.self, forKey: .quality)
        remoteURL = try container.decode(String.self, forKey: .remoteURL)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        localBookmark = try container.decodeIfPresent(Data.self, forKey: .localBookmark)
        progress = try container.decode(Double.self, forKey: .progress)
        state = try container.decode(DownloadState.self, forKey: .state)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(episodeId, forKey: .episodeId)
        try container.encodeIfPresent(releaseId, forKey: .releaseId)
        try container.encode(releaseTitle, forKey: .releaseTitle)
        try container.encode(episodeTitle, forKey: .episodeTitle)
        try container.encodeIfPresent(episodeName, forKey: .episodeName)
        try container.encode(episodeOrdinal, forKey: .episodeOrdinal)
        try container.encode(quality, forKey: .quality)
        try container.encode(remoteURL, forKey: .remoteURL)
        try container.encodeIfPresent(posterPath, forKey: .posterPath)
        try container.encodeIfPresent(localBookmark, forKey: .localBookmark)
        try container.encode(progress, forKey: .progress)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, episodeId, releaseId, releaseTitle, episodeTitle, episodeName, episodeOrdinal
        case quality, remoteURL, posterPath, localBookmark, progress, state, lastError, createdAt
    }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []

    private var session: AVAssetDownloadURLSession!
    private var activeTasks: [String: AVAssetDownloadTask] = [:]
    private var pendingDownloadURLs: [String: URL] = [:]
    private var canceledTaskIDs: Set<String> = []
    private var hasRestoredPendingTasks = false
    private let storageURL: URL
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

    private func applyPosterPath(_ posterPath: String, toReleaseId releaseId: Int, force: Bool = false) {
        var updated = false
        for index in items.indices where items[index].releaseId == releaseId {
            let current = items[index].posterPath
            let shouldReplace: Bool
            if force {
                shouldReplace = current != posterPath
            } else if let current {
                // Prefer local file over remote path.
                shouldReplace = !current.hasPrefix("file:") && posterPath.hasPrefix("file:")
            } else {
                shouldReplace = true
            }
            if shouldReplace {
                items[index].posterPath = posterPath
                updated = true
            }
        }
        if updated {
            saveIndex()
        }
    }

    private func posterFileURL(forReleaseId releaseId: Int) -> URL {
        storageURL
            .appendingPathComponent("posters", isDirectory: true)
            .appendingPathComponent("\(releaseId).jpg")
    }

    private func ensurePostersDirectory() {
        let postersDir = storageURL.appendingPathComponent("posters", isDirectory: true)
        try? FileManager.default.createDirectory(at: postersDir, withIntermediateDirectories: true)
    }

    func cachePosterLocally(path: String?, releaseId: Int) {
        Task {
            await cachePosterLocallyAsync(path: path, releaseId: releaseId)
        }
    }

    private func cachePosterLocallyAsync(path: String?, releaseId: Int) async {
        ensurePostersDirectory()
        let localURL = posterFileURL(forReleaseId: releaseId)

        if FileManager.default.fileExists(atPath: localURL.path) {
            applyPosterPath(localURL.absoluteString, toReleaseId: releaseId, force: true)
            return
        }

        let remotePath: String?
        if let path, path.hasPrefix("file:") {
            applyPosterPath(path, toReleaseId: releaseId, force: true)
            return
        } else {
            remotePath = path
        }

        guard let remoteURL = APIConfig.mediaURL(for: remotePath) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            try data.write(to: localURL, options: .atomic)
            applyPosterPath(localURL.absoluteString, toReleaseId: releaseId, force: true)
        } catch {
            if let remotePath {
                applyPosterPath(remotePath, toReleaseId: releaseId)
            }
        }
    }

    func backfillPostersIfNeeded() async {
        ensurePostersDirectory()

        let groupsNeedingPosters = groupedReleases.filter { group in
            guard let releaseId = group.releaseId else { return false }
            let localURL = posterFileURL(forReleaseId: releaseId)
            if FileManager.default.fileExists(atPath: localURL.path) {
                return group.posterPath?.hasPrefix("file:") != true
            }
            return true
        }

        for group in groupsNeedingPosters {
            guard let releaseId = group.releaseId else { continue }
            let localURL = posterFileURL(forReleaseId: releaseId)

            if FileManager.default.fileExists(atPath: localURL.path) {
                applyPosterPath(localURL.absoluteString, toReleaseId: releaseId, force: true)
                continue
            }

            if let existing = group.posterPath, !existing.hasPrefix("file:") {
                await cachePosterLocallyAsync(path: existing, releaseId: releaseId)
                continue
            }

            guard let release = try? await APIClient.shared.getRelease(idOrAlias: String(releaseId)),
                  let posterPath = release.poster?.displayURL else {
                continue
            }
            await cachePosterLocallyAsync(path: posterPath, releaseId: releaseId)
        }
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

    func enqueue(
        episode: Episode,
        releaseId: Int,
        releaseTitle: String,
        quality: VideoQuality,
        posterPath: String? = nil
    ) {
        guard let streamURL = quality.streamURL(for: episode) else { return }

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

        let asset = AVURLAsset(url: streamURL)
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: "\(releaseTitle) - \(episode.displayTitle)",
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: preferredBitrate(for: quality)]
        ) else {
            items.removeAll { $0.id == placeholderId }
            saveIndex()
            return
        }

        let taskId = task.taskIdentifier.description
        if let index = items.firstIndex(where: { $0.id == placeholderId }) {
            items[index].id = taskId
            items[index].state = .downloading
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
            episodesTotal: episodes.count
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

    func deleteCompleted(in group: DownloadReleaseGroup) {
        for item in group.items where item.state == .completed {
            delete(item: item)
        }
    }

    func retry(item: DownloadItem) {
        guard item.state == .failed else { return }
        guard let releaseId = item.releaseId else { return }
        guard let streamURL = URL(string: item.remoteURL) else { return }
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

        let asset = AVURLAsset(url: streamURL)
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: "\(item.releaseTitle) - \(item.displayEpisodeTitle)",
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: preferredBitrate(for: quality)]
        ) else {
            if let index = items.firstIndex(where: { $0.id == placeholderId }) {
                items[index].state = .failed
                items[index].lastError = "Не удалось начать загрузку"
            }
            saveIndex()
            return
        }

        let taskId = task.taskIdentifier.description
        if let index = items.firstIndex(where: { $0.id == placeholderId }) {
            items[index].id = taskId
            items[index].state = .downloading
        }
        activeTasks[taskId] = task
        saveIndex()
        task.resume()
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

    private func updateItem(id: String, update: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        update(&items[index])
        saveIndex()
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func saveIndex() {
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

    private func savePendingURLs() {
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

    private func removeItemIfExists(at url: URL) {
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

extension DownloadManager: AVAssetDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        Task { @MainActor in
            let id = assetDownloadTask.taskIdentifier.description
            self.pendingDownloadURLs[id] = location
            self.savePendingURLs()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        let expected = CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        guard expected > 0 else { return }
        var loaded: Double = 0
        for value in loadedTimeRanges {
            loaded += CMTimeGetSeconds(value.timeRangeValue.duration)
        }
        let progress = min(loaded / expected, 1)

        Task { @MainActor in
            let id = assetDownloadTask.taskIdentifier.description
            self.updateItem(id: id) { $0.progress = progress }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            let id = assetDownloadTask.taskIdentifier.description
            self.pendingDownloadURLs.removeValue(forKey: id)
            self.savePendingURLs()

            if self.canceledTaskIDs.contains(id) {
                self.canceledTaskIDs.remove(id)
                self.removeItemIfExists(at: location)
                self.activeTasks.removeValue(forKey: id)
                self.purgeOrphanedDownloadCache()
                return
            }

            if let bookmark = try? location.bookmarkData() {
                self.updateItem(id: id) {
                    $0.localBookmark = bookmark
                    $0.progress = 1
                    $0.state = .completed
                }
            } else {
                self.updateItem(id: id) {
                    $0.state = .failed
                    $0.lastError = "Не удалось сохранить файл"
                }
            }
            self.activeTasks.removeValue(forKey: id)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            let id = task.taskIdentifier.description
            if let error {
                if self.canceledTaskIDs.contains(id) {
                    self.canceledTaskIDs.remove(id)
                    self.activeTasks.removeValue(forKey: id)
                    return
                }

                if let pendingURL = self.pendingDownloadURLs[id] {
                    self.removeItemIfExists(at: pendingURL)
                    self.pendingDownloadURLs.removeValue(forKey: id)
                    self.savePendingURLs()
                }

                let message = error.localizedDescription
                if self.items.contains(where: { $0.id == id }) {
                    self.updateItem(id: id) {
                        $0.state = .failed
                        $0.progress = 0
                        $0.localBookmark = nil
                        $0.lastError = message
                    }
                }
                self.activeTasks.removeValue(forKey: id)
                self.purgeOrphanedDownloadCache()
            }
        }
    }
}
