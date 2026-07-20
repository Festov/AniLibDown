import SwiftUI

@MainActor
final class DownloadSettings: ObservableObject {
    static let shared = DownloadSettings()

    @Published var wifiOnlyDownloads: Bool {
        didSet { UserDefaults.standard.set(wifiOnlyDownloads, forKey: "wifiOnlyDownloads") }
    }

    @Published var maxConcurrentDownloads: Int {
        didSet {
            let clamped = min(5, max(1, maxConcurrentDownloads))
            if clamped != maxConcurrentDownloads {
                maxConcurrentDownloads = clamped
                return
            }
            UserDefaults.standard.set(maxConcurrentDownloads, forKey: "maxConcurrentDownloads")
        }
    }

    static let concurrentOptions = [1, 2, 3, 4, 5]

    private init() {
        if UserDefaults.standard.object(forKey: "wifiOnlyDownloads") == nil {
            wifiOnlyDownloads = false
        } else {
            wifiOnlyDownloads = UserDefaults.standard.bool(forKey: "wifiOnlyDownloads")
        }
        let saved = UserDefaults.standard.integer(forKey: "maxConcurrentDownloads")
        maxConcurrentDownloads = saved > 0 ? min(5, saved) : 2
    }
}
