import Foundation

enum ShikimoriConfig {
    static let baseURL = URL(string: "https://shikimori.one")!
    static let userAgent = "AniLibDown/1.0.1 (iOS)"
    static let redirectURI = "anilibdown://shikimori/callback"
    static let callbackScheme = "anilibdown"
    static let oauthScope = "user_rates"

    /// Заполните в ShikimoriSecrets.plist (см. ShikimoriSecrets.plist.example).
    static var clientId: String { secretValue(forKey: "ClientId") }
    static var clientSecret: String { secretValue(forKey: "ClientSecret") }

    static var isConfigured: Bool {
        !clientId.isEmpty && !clientSecret.isEmpty
    }

    static var configurationHint: String {
        "Создайте OAuth-приложение на shikimori.one/oauth/applications и скопируйте ShikimoriSecrets.plist.example в ShikimoriSecrets.plist с вашими ClientId и ClientSecret. Redirect URI: \(redirectURI)"
    }

    private static func secretValue(forKey key: String) -> String {
        guard let url = Bundle.main.url(forResource: "ShikimoriSecrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let value = dict[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.hasPrefix("YOUR_") else {
            return ""
        }
        return value
    }
}
