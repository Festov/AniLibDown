import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notifyDownloadCompleted(releaseTitle: String, episodeTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "Загрузка завершена"
        content.body = "\(releaseTitle) — \(episodeTitle)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "download-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
