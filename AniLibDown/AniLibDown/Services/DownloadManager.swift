import Foundation
import AVFoundation

struct DownloadItem: Identifiable, Codable, Hashable {
    var id: String
    let episodeId: String
    let releaseId: Int?
    let releaseTitle: String
    let episodeTitle: String
    let episodeOrdinal: Double
    let quality: String
    let remoteURL: String
    var localBookmark: Data?
    var progress: Double
    var state: DownloadState
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

    init(
        id: String,
        episodeId: String,
        releaseId: Int?,
        releaseTitle: String,
        episodeTitle: String,
        episodeOrdinal: Double,
        quality: String,
        remoteURL: String,
        localBookmark: Data?,
        progress: Double,
        state: DownloadState,
        createdAt: Date
    ) {
        self.id = id
        self.episodeId = episodeId
        self.releaseId = releaseId
        self.releaseTitle = releaseTitle
        self.episodeTitle = episodeTitle
        self.episodeOrdinal = episodeOrdinal
        self.quality = quality
        self.remoteURL = remoteURL
        self.localBookmark = localBookmark
        self.progress = progress
        self.state = state
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        episodeId = try container.decode(String.self, forKey: .episodeId)
        releaseId = try container.decodeIfPresent(Int.self, forKey: .releaseId)
        releaseTitle = try container.decode(String.self, forKey: .releaseTitle)
        episodeTitle = try container.decode(String.self, forKey: .episodeTitle)
        episodeOrdinal = try container.decodeIfPresent(Double.self, forKey: .episodeOrdinal) ?? 0
        quality = try container.decode(String.self, forKey: .quality)
        remoteURL = try container.decode(String.self, forKey: .remoteURL)
        localBookmark = try container.decodeIfPresent(Data.self, forKey: .localBookmark)
        progress = try container.decode(Double.self, forKey: .progress)
        state = try container.decode(DownloadState.self, forKey: .state)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, episodeId, releaseId, releaseTitle, episodeTitle, episodeOrdinal
        case quality, remoteURL, localBookmark, progress, state, createdAt
    }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []

    private var session: AVAssetDownloadURLSession!
    private var activeTasks: [String: AVAssetDownloadTask] = [:]
    private let storageURL: URL
    private let indexURL: URL

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
                items: sorted
            )
        }
        .sorted { $0.releaseTitle.localizedCaseInsensitiveCompare($1.releaseTitle) == .orderedAscending }
    }

    private override init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = documents.appendingPathComponent("Downloads", isDirectory: true)
        indexURL = documents.appendingPathComponent("downloads-index.json")
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "top.aniliberty.AniLibDown.downloads")
        session = AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: nil)
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        loadIndex()
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
        quality: VideoQuality
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
            episodeOrdinal: episode.ordinal,
            quality: quality.rawValue,
            remoteURL: streamURL.absoluteString,
            localBookmark: nil,
            progress: 0,
            state: .queued,
            createdAt: Date()
        )
        items.insert(placeholder, at: 0)
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

    func enqueueAll(episodes: [Episode], releaseId: Int, releaseTitle: String, quality: VideoQuality) {
        for episode in episodes {
            enqueue(episode: episode, releaseId: releaseId, releaseTitle: releaseTitle, quality: quality)
        }
    }

    func cancel(item: DownloadItem) {
        if let task = activeTasks[item.id] {
            task.cancel()
            activeTasks.removeValue(forKey: item.id)
        }
        items.removeAll { $0.id == item.id }
        saveIndex()
    }

    func delete(item: DownloadItem) {
        if let url = localPlaybackURL(for: item.episodeId, quality: VideoQuality(rawValue: item.quality) ?? .p720) {
            try? FileManager.default.removeItem(at: url)
        }
        cancel(item: item)
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
                                episodeOrdinal: 0,
                                quality: VideoQuality.p720.rawValue,
                                remoteURL: downloadTask.urlAsset.url.absoluteString,
                                progress: 0,
                                state: .downloading,
                                createdAt: Date()
                            ),
                            at: 0
                        )
                    }
                }
                self.saveIndex()
            }
        }
    }
}

extension DownloadManager: AVAssetDownloadDelegate {
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
            if let bookmark = try? location.bookmarkData() {
                self.updateItem(id: id) {
                    $0.localBookmark = bookmark
                    $0.progress = 1
                    $0.state = .completed
                }
            } else {
                self.updateItem(id: id) { $0.state = .failed }
            }
            self.activeTasks.removeValue(forKey: id)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            let id = task.taskIdentifier.description
            self.updateItem(id: id) {
                $0.state = .failed
                $0.progress = 0
            }
            self.activeTasks.removeValue(forKey: id)
            _ = error.localizedDescription
        }
    }
}
