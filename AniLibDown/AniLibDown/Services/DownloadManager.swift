import Foundation
import AVFoundation

struct DownloadItem: Identifiable, Codable, Hashable {
    let id: String
    let episodeId: String
    let releaseTitle: String
    let episodeTitle: String
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
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []

    private var session: AVAssetDownloadURLSession!
    private var activeTasks: [String: AVAssetDownloadTask] = [:]
    private let storageURL: URL
    private let indexURL: URL

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
        releaseTitle: String,
        quality: VideoQuality
    ) {
        guard let streamURL = quality.streamURL(for: episode) else { return }

        if isDownloaded(episodeId: episode.id, quality: quality) {
            return
        }

        if let existing = downloadItem(for: episode.id, quality: quality),
           existing.state == .downloading || existing.state == .queued {
            return
        }

        let asset = AVURLAsset(url: streamURL)
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: "\(releaseTitle) - \(episode.displayTitle)",
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: preferredBitrate(for: quality)]
        ) else {
            return
        }

        let item = DownloadItem(
            id: task.taskIdentifier.description,
            episodeId: episode.id,
            releaseTitle: releaseTitle,
            episodeTitle: episode.displayTitle,
            quality: quality.rawValue,
            remoteURL: streamURL.absoluteString,
            localBookmark: nil,
            progress: 0,
            state: .queued,
            createdAt: Date()
        )

        items.insert(item, at: 0)
        activeTasks[item.id] = task
        saveIndex()
        task.resume()
        updateItem(id: item.id) { $0.state = .downloading }
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
                                episodeId: "unknown",
                                releaseTitle: downloadTask.urlAsset.url.lastPathComponent,
                                episodeTitle: "Загрузка",
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
