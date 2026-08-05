import Foundation
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected = true
    @Published private(set) var isOnWiFi = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "top.aniliberty.network-monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let connected = path.status == .satisfied
                let onWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                if self.isConnected != connected {
                    self.isConnected = connected
                }
                if self.isOnWiFi != onWiFi {
                    self.isOnWiFi = onWiFi
                }
            }
        }
        monitor.start(queue: queue)
    }

    var canDownload: Bool {
        guard isConnected else { return false }
        if DownloadSettings.shared.wifiOnlyDownloads {
            return isOnWiFi
        }
        return true
    }

    var downloadBlockedReason: String? {
        guard isConnected else { return "Нет подключения к интернету" }
        if DownloadSettings.shared.wifiOnlyDownloads && !isOnWiFi {
            return "Загрузки разрешены только по Wi‑Fi"
        }
        return nil
    }
}
