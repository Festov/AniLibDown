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

    private var lastNotifiedEpisodeIds: [Int: String] = [:]
    private var isChecking = false

    private enum Keys {
        static let subscriptions = "episodeAlertSubscriptions"
        static let lastNotified = "episodeAlertLastNotified"
        static let seeded = "episodeAlertSeeded"
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
        seedEpisodeId: String? = nil
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
        seedEpisodeId: String?
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

        if let seedEpisodeId {
            lastNotifiedEpisodeIds[releaseId] = seedEpisodeId
        }

        persist()
        Task {
            await NotificationManager.shared.requestAuthorizationIfNeeded()
            await NotificationManager.shared.reschedulePublishDayReminders(
                subscriptions: subscriptions,
                hour: AppSettings.shared.publishDayReminderHour,
                enabled: AppSettings.shared.episodeNotificationsEnabled
                    && AppSettings.shared.publishDayRemindersEnabled
            )
        }
    }

    func unsubscribe(releaseId: Int) {
        subscriptions.removeAll { $0.releaseId == releaseId }
        lastNotifiedEpisodeIds.removeValue(forKey: releaseId)
        persist()
        NotificationManager.shared.cancelPublishDayReminder(releaseId: releaseId)
    }

    func rescheduleReminders() async {
        await NotificationManager.shared.reschedulePublishDayReminders(
            subscriptions: subscriptions,
            hour: AppSettings.shared.publishDayReminderHour,
            enabled: AppSettings.shared.episodeNotificationsEnabled
                && AppSettings.shared.publishDayRemindersEnabled
        )
    }

    /// Checks schedule for newly published episodes among subscriptions / «Смотрю».
    func checkForNewEpisodes() async {
        guard AppSettings.shared.episodeNotificationsEnabled else { return }
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let schedule = try await APIClient.shared.getScheduleNow()
            let relevant = relevantItems(from: schedule)
            let didUpdateNumbers = updateNextEpisodeNumbers(from: schedule)

            if !UserDefaults.standard.bool(forKey: Keys.seeded) {
                for item in relevant {
                    if let episode = item.publishedReleaseEpisode {
                        lastNotifiedEpisodeIds[item.release.id] = episode.id
                    }
                }
                UserDefaults.standard.set(true, forKey: Keys.seeded)
                persist()
                if didUpdateNumbers {
                    await rescheduleReminders()
                }
                return
            }

            var didNotify = false
            for item in relevant {
                guard let episode = item.publishedReleaseEpisode else { continue }
                if lastNotifiedEpisodeIds[item.release.id] == episode.id { continue }

                await NotificationManager.shared.notifyNewEpisode(
                    releaseTitle: item.release.name.main,
                    episodeNumber: episode.ordinalFormatted,
                    releaseId: item.release.id
                )
                lastNotifiedEpisodeIds[item.release.id] = episode.id
                if let index = subscriptions.firstIndex(where: { $0.releaseId == item.release.id }) {
                    let next = item.nextReleaseEpisodeNumber
                        ?? Int(episode.ordinal.rounded(.towardZero)) + 1
                    if subscriptions[index].nextEpisodeNumber != next {
                        subscriptions[index].nextEpisodeNumber = next
                    }
                }
                didNotify = true
            }

            if didNotify || didUpdateNumbers {
                persist()
            }
            if didUpdateNumbers {
                await rescheduleReminders()
            }
        } catch {
            AppLog.api.error("Episode alert check failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func updateNextEpisodeNumbers(from schedule: ScheduleNowResponse) -> Bool {
        var byId: [Int: Int] = [:]
        for item in schedule.allItems {
            if let next = item.nextReleaseEpisodeNumber {
                byId[item.release.id] = next
            } else if let published = item.publishedReleaseEpisode {
                byId[item.release.id] = Int(published.ordinal.rounded(.towardZero)) + 1
            }
        }

        var changed = false
        for index in subscriptions.indices {
            guard let next = byId[subscriptions[index].releaseId] else { continue }
            if subscriptions[index].nextEpisodeNumber != next {
                subscriptions[index].nextEpisodeNumber = next
                changed = true
            }
        }
        return changed
    }

    private func relevantItems(from schedule: ScheduleNowResponse) -> [ScheduleItem] {
        let subscribed = Set(subscriptions.map(\.releaseId))
        var ids = subscribed

        if AppSettings.shared.notifyWatchingCollection {
            for (releaseId, type) in CollectionStatusStore.shared.memberships where type == .watching {
                ids.insert(releaseId)
            }
        }

        guard !ids.isEmpty else { return [] }
        // Prefer today/yesterday (fresh publishes); tomorrow rarely has published episode.
        return (schedule.today + schedule.yesterday + schedule.tomorrow)
            .filter { ids.contains($0.release.id) }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Keys.subscriptions),
           let decoded = try? JSONDecoder().decode([EpisodeAlertSubscription].self, from: data) {
            subscriptions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Keys.lastNotified),
           let decoded = try? JSONDecoder().decode([Int: String].self, from: data) {
            lastNotifiedEpisodeIds = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(subscriptions) {
            UserDefaults.standard.set(data, forKey: Keys.subscriptions)
        }
        if let data = try? JSONEncoder().encode(lastNotifiedEpisodeIds) {
            UserDefaults.standard.set(data, forKey: Keys.lastNotified)
        }
    }
}
