import Foundation

enum AppVersion {
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.3"
    }

    static var profileLabel: String {
        "\(short) • AniLibDown"
    }

    static var userAgent: String {
        "AniLibDown/\(short) (iOS)"
    }
}
