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

    func notifyNewEpisode(releaseTitle: String, episodeTitle: String, releaseId: Int) async {
        await requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Новая серия"
        content.body = "\(releaseTitle) — \(episodeTitle)"
        content.sound = .default
        content.userInfo = ["releaseId": releaseId]

        let request = UNNotificationRequest(
            identifier: "episode-\(releaseId)-\(episodeTitle.hashValue)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelPublishDayReminder(releaseId: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [publishDayIdentifier(releaseId)])
    }

    func reschedulePublishDayReminders(
        subscriptions: [EpisodeAlertSubscription],
        hour: Int,
        enabled: Bool
    ) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let oldIds = existing
            .map(\.identifier)
            .filter { $0.hasPrefix("publish-day-") }
        center.removePendingNotificationRequests(withIdentifiers: oldIds)

        guard enabled else { return }
        await requestAuthorizationIfNeeded()

        let clampedHour = min(max(hour, 0), 23)

        for subscription in subscriptions {
            guard let dayValue = subscription.publishDayValue,
                  (1...7).contains(dayValue) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "День выхода серии"
            let dayTitle = subscription.publishDayTitle ?? "сегодня"
            content.body = "\(subscription.title) — обычно выходит в \(dayTitle.lowercased())"
            content.sound = .default
            content.userInfo = ["releaseId": subscription.releaseId]

            var components = DateComponents()
            components.weekday = dayValue == 7 ? 1 : dayValue + 1
            components.hour = clampedHour
            components.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: publishDayIdentifier(subscription.releaseId),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    private func publishDayIdentifier(_ releaseId: Int) -> String {
        "publish-day-\(releaseId)"
    }
}
