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

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.2"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
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
    }
}
