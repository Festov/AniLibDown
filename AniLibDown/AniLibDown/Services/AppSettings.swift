import SwiftUI

enum AppColorScheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var colorSchemePreference: AppColorScheme {
        didSet {
            UserDefaults.standard.set(colorSchemePreference.rawValue, forKey: "appColorScheme")
        }
    }

    @Published var isSplashEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSplashEnabled, forKey: "isSplashEnabled")
        }
    }

    @Published var showShikimoriOnReleaseCard: Bool {
        didSet {
            UserDefaults.standard.set(showShikimoriOnReleaseCard, forKey: "showShikimoriOnReleaseCard")
        }
    }

    @Published var defaultVideoQuality: VideoQuality {
        didSet {
            UserDefaults.standard.set(defaultVideoQuality.rawValue, forKey: "defaultVideoQuality")
        }
    }

    @Published var episodeNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(episodeNotificationsEnabled, forKey: "episodeNotificationsEnabled")
            Task { await EpisodeAlertStore.shared.rescheduleReminders() }
        }
    }

    /// Час (0…23) локального напоминания в день выхода. По умолчанию 18:00.
    @Published var episodeNotificationHour: Int {
        didSet {
            let clamped = min(max(episodeNotificationHour, 0), 23)
            if clamped != episodeNotificationHour {
                episodeNotificationHour = clamped
                return
            }
            UserDefaults.standard.set(episodeNotificationHour, forKey: "episodeNotificationHour")
            Task { await EpisodeAlertStore.shared.rescheduleReminders() }
        }
    }

    @Published var hiddenCollectionTypes: Set<CollectionType> {
        didSet {
            let raw = hiddenCollectionTypes.map(\.rawValue)
            UserDefaults.standard.set(raw, forKey: "hiddenCollectionTypes")
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appColorScheme") ?? AppColorScheme.system.rawValue
        colorSchemePreference = AppColorScheme(rawValue: raw) ?? .system
        if UserDefaults.standard.object(forKey: "isSplashEnabled") == nil {
            isSplashEnabled = true
        } else {
            isSplashEnabled = UserDefaults.standard.bool(forKey: "isSplashEnabled")
        }
        if UserDefaults.standard.object(forKey: "showShikimoriOnReleaseCard") == nil {
            showShikimoriOnReleaseCard = true
        } else {
            showShikimoriOnReleaseCard = UserDefaults.standard.bool(forKey: "showShikimoriOnReleaseCard")
        }
        let qualityRaw = UserDefaults.standard.string(forKey: "defaultVideoQuality") ?? VideoQuality.p720.rawValue
        defaultVideoQuality = VideoQuality(rawValue: qualityRaw) ?? .p720

        if UserDefaults.standard.object(forKey: "episodeNotificationsEnabled") == nil {
            episodeNotificationsEnabled = false
        } else {
            episodeNotificationsEnabled = UserDefaults.standard.bool(forKey: "episodeNotificationsEnabled")
        }

        let hiddenRaw = UserDefaults.standard.stringArray(forKey: "hiddenCollectionTypes") ?? []
        hiddenCollectionTypes = Set(hiddenRaw.compactMap { CollectionType(rawValue: $0) })

        if UserDefaults.standard.object(forKey: "episodeNotificationHour") == nil {
            if UserDefaults.standard.object(forKey: "publishDayReminderHour") != nil {
                episodeNotificationHour = UserDefaults.standard.integer(forKey: "publishDayReminderHour")
            } else {
                episodeNotificationHour = 18
            }
        } else {
            episodeNotificationHour = UserDefaults.standard.integer(forKey: "episodeNotificationHour")
        }
        episodeNotificationHour = min(max(episodeNotificationHour, 0), 23)

        // Obsolete keys from older notification modes.
        UserDefaults.standard.removeObject(forKey: "publishDayRemindersEnabled")
        UserDefaults.standard.removeObject(forKey: "notifyWatchingCollection")
        UserDefaults.standard.removeObject(forKey: "publishDayReminderHour")
        UserDefaults.standard.removeObject(forKey: "episodeAlertLastNotified")
        UserDefaults.standard.removeObject(forKey: "episodeAlertSeeded")

        Task { await EpisodeAlertStore.shared.rescheduleReminders() }
    }
}
