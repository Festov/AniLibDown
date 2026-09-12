import Foundation

struct EpisodeAlertSubscription: Codable, Hashable, Identifiable {
    var id: Int { releaseId }

    let releaseId: Int
    let title: String
    let posterPath: String?
    let publishDayValue: Int?
    let publishDayTitle: String?
    var nextEpisodeNumber: Int?
}

@MainActor
final class EpisodeAlertStore: ObservableObject {
    static let shared = EpisodeAlertStore()

    @Published private(set) var subscriptions: [EpisodeAlertSubscription] = []

    private enum Keys {
        static let subscriptions = "episodeAlertSubscriptions"
    }

    private init() {
        load()
    }

    func isSubscribed(releaseId: Int) -> Bool {
        subscriptions.contains { $0.releaseId == releaseId }
    }

    func toggleSubscription(for item: ScheduleItem) {
        if isSubscribed(releaseId: item.release.id) {
            unsubscribe(releaseId: item.release.id)
        } else {
            subscribe(
                releaseId: item.release.id,
                title: item.release.name.main,
                posterPath: item.release.poster?.displayURL,
                publishDay: item.release.publishDay,
                nextEpisodeNumber: item.nextReleaseEpisodeNumber,
                seedEpisodeId: item.publishedReleaseEpisode?.id
            )
        }
    }

    func toggleSubscription(
        releaseId: Int,
        title: String,
        posterPath: String?,
        publishDay: PublishDay?,
        nextEpisodeNumber: Int? = nil,
        _ seedEpisodeId: String? = nil
    ) {
        if isSubscribed(releaseId: releaseId) {
            unsubscribe(releaseId: releaseId)
        } else {
            subscribe(
                releaseId: releaseId,
                title: title,
                posterPath: posterPath,
                publishDay: publishDay,
                nextEpisodeNumber: nextEpisodeNumber,
                seedEpisodeId: seedEpisodeId
            )
        }
    }

    func subscribe(
        releaseId: Int,
        title: String,
        posterPath: String?,
        publishDay: PublishDay?,
        nextEpisodeNumber: Int?,
        _ seedEpisodeId: String?
    ) {
        guard !isSubscribed(releaseId: releaseId) else { return }

        let entry = EpisodeAlertSubscription(
            releaseId: releaseId,
            title: title,
            posterPath: posterPath,
            publishDayValue: publishDay?.value,
            publishDayTitle: publishDay?.description,
            nextEpisodeNumber: nextEpisodeNumber
        )
        subscriptions.append(entry)
        subscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        persist()
        Task {
            await NotificationManager.shared.requestAuthorizationIfNeeded()
            await rescheduleReminders()
        }
    }

    func unsubscribe(releaseId: Int) {
        subscriptions.removeAll { $0.releaseId == releaseId }
        persist()
        NotificationManager.shared.cancelPublishDayReminder(releaseId: releaseId)
        Task { await rescheduleReminders() }
    }

    func rescheduleReminders() async {
        await NotificationManager.shared.reschedulePublishDayReminders(
            subscriptions: subscriptions,
            hour: AppSettings.shared.episodeNotificationHour,
            enabled: AppSettings.shared.episodeNotificationsEnabled
        )
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Keys.subscriptions),
           let decoded = try? JSONDecoder().decode([EpisodeAlertSubscription].self, from: data) {
            subscriptions = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(subscriptions) {
            UserDefaults.standard.set(data, forKey: Keys.subscriptions)
        }
    }
}
