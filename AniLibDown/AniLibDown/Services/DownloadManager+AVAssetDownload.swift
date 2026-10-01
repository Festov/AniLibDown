import Foundation
import AVFoundation

// Background-session callbacks. Everything here is driven by AVFoundation on
// arbitrary queues, so each hop hops back to the main actor before touching state.
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
            self.updateProgress(id: id, progress: progress)
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
                if let completedItem = self.items.first(where: { $0.id == id }) {
                    NotificationManager.shared.notifyDownloadCompleted(
                        releaseTitle: completedItem.releaseTitle,
                        episodeTitle: completedItem.displayEpisodeTitle
                    )
                }
            } else {
                self.updateItem(id: id) {
                    $0.state = .failed
                    $0.lastError = "Не удалось сохранить файл"
                }
            }
            self.activeTasks.removeValue(forKey: id)
            self.processDownloadQueue()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            let id = task.taskIdentifier.description
            if let error {
                // User cancel / system cancel: remove quietly, never show as a failed download.
                if self.canceledTaskIDs.contains(id) || Self.isCancellationError(error) {
                    self.canceledTaskIDs.remove(id)
                    if let pendingURL = self.pendingDownloadURLs[id] {
                        self.removeItemIfExists(at: pendingURL)
                        self.pendingDownloadURLs.removeValue(forKey: id)
                        self.savePendingURLs()
                    }
                    self.items.removeAll { $0.id == id }
                    self.saveIndex()
                    self.activeTasks.removeValue(forKey: id)
                    self.purgeOrphanedDownloadCache()
                    return
                }

                if let pendingURL = self.pendingDownloadURLs[id] {
                    self.removeItemIfExists(at: pendingURL)
                    self.pendingDownloadURLs.removeValue(forKey: id)
                    self.savePendingURLs()
                }

                let message = Self.userFacingDownloadError(error)
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
            self.processDownloadQueue()
        }
    }

    private nonisolated static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("cancel") || message.contains("отмен")
    }

    private nonisolated static func userFacingDownloadError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Нет соединения с интернетом"
            case .timedOut:
                return "Время ожидания истекло"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Не удалось подключиться к серверу"
            default:
                break
            }
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Не удалось скачать серию" : message
    }
}