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
    }
}
