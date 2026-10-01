import Foundation
import UIKit
import CryptoKit

/// AsyncImage keeps nothing on disk, so every catalog scroll re-downloaded the
/// same posters. This store keeps them in Caches/Posters with a memory tier on top.
actor PosterImageStore {
    static let shared = PosterImageStore()

    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let directory: URL
    private let session: URLSession

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Posters", isDirectory: true)
        let config = URLSessionConfiguration.default
        // We manage our own cache, so keep URLSession out of the way.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func image(for url: URL) async -> UIImage? {
        let key = url as NSURL

        if let cached = memory.object(forKey: key) {
            return cached
        }

        let file = fileURL(for: url)
        if let image = UIImage(contentsOfFile: file.path) {
            memory.setObject(image, forKey: key)
            return image
        }

        if let existing = inFlight[url] {
            return await existing.value
        }

        let session = self.session
        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            let folder = file.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return UIImage(data: data)
        }
        inFlight[url] = task

        let image = await task.value
        inFlight[url] = nil
        if let image {
            memory.setObject(image, forKey: key)
        }
        return image
    }

    func clear() {
        memory.removeAllObjects()
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory
            .appendingPathComponent(name, isDirectory: false)
            .appendingPathExtension("img")
    }
}

enum PosterSource {
    /// Posters of downloaded releases are already on disk as file URLs.
    static func localImage(path: String?) -> UIImage? {
        guard let path, path.hasPrefix("file:"), let url = URL(string: path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Remote poster for catalog/collection rows. Nil for nil paths and local files.
    static func remoteURL(path: String?) -> URL? {
        guard let path, !path.hasPrefix("file:") else { return nil }
        return APIConfig.mediaURL(for: path)
    }
}