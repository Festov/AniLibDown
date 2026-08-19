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

    @Published var publishDayRemindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(publishDayRemindersEnabled, forKey: "publishDayRemindersEnabled")
            Task { await EpisodeAlertStore.shared.rescheduleReminders() }
        }
    }

    @Published var notifyWatchingCollection: Bool {
        didSet {
            UserDefaults.standard.set(notifyWatchingCollection, forKey: "notifyWatchingCollection")
        }
    }

    @Published var publishDayReminderHour: Int {
        didSet {
            UserDefaults.standard.set(publishDayReminderHour, forKey: "publishDayReminderHour")
            Task { await EpisodeAlertStore.shared.rescheduleReminders() }
        }
    }

    @Published var hiddenCollectionTypes: Set<CollectionType> {
        didSet {
            let raw = hiddenCollectionTypes.map(\.rawValue)
            UserDefaults.standard.set(raw, forKey: "hiddenCollectionTypes")
        }
    }

    static var versionDisplay: String { AppVersion.display }

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
        if UserDefaults.standard.object(forKey: "publishDayRemindersEnabled") == nil {
            publishDayRemindersEnabled = true
        } else {
            publishDayRemindersEnabled = UserDefaults.standard.bool(forKey: "publishDayRemindersEnabled")
        }
        if UserDefaults.standard.object(forKey: "notifyWatchingCollection") == nil {
            notifyWatchingCollection = true
        } else {
            notifyWatchingCollection = UserDefaults.standard.bool(forKey: "notifyWatchingCollection")
        }
        let hour = UserDefaults.standard.object(forKey: "publishDayReminderHour") as? Int
        publishDayReminderHour = min(max(hour ?? 20, 0), 23)

        let hiddenRaw = UserDefaults.standard.stringArray(forKey: "hiddenCollectionTypes") ?? []
        hiddenCollectionTypes = Set(hiddenRaw.compactMap { CollectionType(rawValue: $0) })
    }
}
