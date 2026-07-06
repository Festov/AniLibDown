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

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appColorScheme") ?? AppColorScheme.system.rawValue
        colorSchemePreference = AppColorScheme(rawValue: raw) ?? .system
    }
}
