import Foundation

// Poster caching: keeps a local copy of every downloaded release's poster in
// Documents/Downloads/posters so the library renders without any network access.
extension DownloadManager {
    func applyPosterPath(_ posterPath: String, toReleaseId releaseId: Int, force: Bool = false) {
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

    func posterFileURL(forReleaseId releaseId: Int) -> URL {
        storageURL
            .appendingPathComponent("posters", isDirectory: true)
            .appendingPathComponent("\(releaseId).jpg")
    }

    func ensurePostersDirectory() {
        let postersDir = storageURL.appendingPathComponent("posters", isDirectory: true)
        try? FileManager.default.createDirectory(at: postersDir, withIntermediateDirectories: true)
    }

    func cachePosterLocally(path: String?, releaseId: Int) {
        Task {
            await cachePosterLocallyAsync(path: path, releaseId: releaseId)
        }
    }

    func cachePosterLocallyAsync(path: String?, releaseId: Int) async {
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
}