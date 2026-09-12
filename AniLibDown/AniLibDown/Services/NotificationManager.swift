import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// Шаблоны тел уведомлений (плейсхолдеры: {title}, {ep}).
    static let episodeBodyTemplates: [String] = [
        "{title} — {ep}. Бегом смотреть!",
        "{title}: вышла {ep}. Самое время",
        "Новый эпик: {title} — {ep}. Не проспи",
        "{title} дропнул {ep}. Залетай",
        "Эй, сенпай: у «{title}» уже {ep}",
        "{title} — {ep}. Залетай, пока не заспойлерили",
        "Свежий дроп: {title}, {ep}",
        "Накама, подъём: {title} — {ep}",
        "{title}: {ep} на месте. Можно включать",
        "Пора к экрану, сенпай: {title} — {ep}",
    ]

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

    func cancelPublishDayReminder(releaseId: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [publishDayIdentifier(releaseId)])
    }

    /// Планирует локальные напоминания на день выхода (день недели) в выбранный час.
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
            content.title = "Сегодня новая серия!"
            let episodeLabel: String = {
                if let number = subscription.nextEpisodeNumber {
                    return "Серия \(number)"
                }
                return "новая серия"
            }()
            content.body = episodeNotificationBody(title: subscription.title, episodeNumber: episodeLabel)
            content.sound = .default
            content.userInfo = ["releaseId": subscription.releaseId]

            var components = DateComponents()
            components.weekday = PublishDay.calendarWeekday(fromAniLibertyDay: dayValue)
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

    /// Removes all pending publish-day reminders.
    func clearPublishDayReminders() async {
        await reschedulePublishDayReminders(subscriptions: [], hour: 18, enabled: false)
    }

    func episodeNotificationBody(title: String, episodeNumber: String) -> String {
        let template = Self.episodeBodyTemplates.randomElement() ?? Self.episodeBodyTemplates[0]
        return template
            .replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{ep}", with: episodeNumber)
    }

    private func publishDayIdentifier(_ releaseId: Int) -> String {
        "publish-day-\(releaseId)"
    }
}
