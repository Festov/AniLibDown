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
        Task {
            await requestAuthorizationIfNeeded()
            let content = UNMutableNotificationContent()
            content.title = "Загрузка завершена"
            content.body = "\(releaseTitle) — \(episodeTitle)"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "download-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    func notifyNewEpisode(releaseTitle: String, episodeNumber: String, releaseId: Int) async {
        await requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Сегодня новая серия!"
        content.body = episodeNotificationBody(title: releaseTitle, episodeNumber: episodeNumber)
        content.sound = .default
        content.userInfo = ["releaseId": releaseId]

        let request = UNNotificationRequest(
            identifier: "episode-\(releaseId)-\(episodeNumber)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelPublishDayReminder(releaseId: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [publishDayIdentifier(releaseId)])
    }

    /// Clears legacy calendar "publish day" reminders (feature removed in 1.1.3).
    func clearPublishDayReminders() async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let oldIds = existing
            .map(\.identifier)
            .filter { $0.hasPrefix("publish-day-") }
        center.removePendingNotificationRequests(withIdentifiers: oldIds)
    }

    private func episodeNotificationBody(title: String, episodeNumber: String) -> String {
        "\(title) - \(episodeNumber). Бегом смотреть!"
    }

    private func publishDayIdentifier(_ releaseId: Int) -> String {
        "publish-day-\(releaseId)"
    }
}
