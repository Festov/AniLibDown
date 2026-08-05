import AuthenticationServices
import Combine
import UIKit

private final class ShikimoriPresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
            ?? UIWindow()
    }
}

@MainActor
final class ShikimoriAuthService: ObservableObject {
    static let shared = ShikimoriAuthService()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var profile: ShikimoriUserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let presentationAnchorProvider = ShikimoriPresentationAnchorProvider()
    private let expiresAtKey = "shikimoriAccessExpiresAt"
    /// Refresh a bit before the server-side expiry.
    private let expirySkew: TimeInterval = 60

    private init() {}

    func restoreSession() async {
        guard ShikimoriConfig.isConfigured,
              KeychainHelper.loadShikimoriAccessToken() != nil else {
            isAuthenticated = false
            profile = nil
            return
        }

        do {
            let user = try await fetchProfile()
            profile = user
            isAuthenticated = true
        } catch {
            disconnect()
        }
    }

    func connect() async {
        guard ShikimoriConfig.isConfigured else {
            errorMessage = ShikimoriConfig.configurationHint
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var components = URLComponents(url: ShikimoriConfig.oauthAuthorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: ShikimoriConfig.clientId),
            URLQueryItem(name: "redirect_uri", value: ShikimoriConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: ShikimoriConfig.oauthScope)
        ]

        guard let authURL = components.url else {
            errorMessage = "Не удалось открыть страницу авторизации"
            return
        }

        do {
            let callbackURL = try await startAuthSession(url: authURL)
            guard let code = authorizationCode(from: callbackURL) else {
                errorMessage = ShikimoriError.invalidCallback.errorDescription
                return
            }

            let tokens = try await ShikimoriAPIClient.shared.exchangeAuthorizationCode(code)
            persistTokens(tokens)
            let user = try await ShikimoriAPIClient.shared.whoami(accessToken: tokens.accessToken)
            profile = user
            isAuthenticated = true
        } catch {
            if isCanceledLogin(error) {
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func disconnect() {
        KeychainHelper.deleteShikimoriTokens()
        UserDefaults.standard.removeObject(forKey: expiresAtKey)
        isAuthenticated = false
        profile = nil
        errorMessage = nil
    }

    /// Returns a usable access token, refreshing when `expiresIn` says it is stale.
    /// Does not call `whoami` on every use — only when validating a legacy session without expiry.
    func accessToken() async throws -> String {
        guard ShikimoriConfig.isConfigured else {
            throw ShikimoriError.notConfigured
        }
        guard KeychainHelper.loadShikimoriAccessToken() != nil else {
            throw ShikimoriError.notAuthenticated
        }

        if isAccessTokenFresh {
            return KeychainHelper.loadShikimoriAccessToken()!
        }

        if let refresh = KeychainHelper.loadShikimoriRefreshToken() {
            do {
                try await refreshTokens(using: refresh)
                guard let refreshed = KeychainHelper.loadShikimoriAccessToken() else {
                    throw ShikimoriError.notAuthenticated
                }
                return refreshed
            } catch {
                if hasStoredExpiry || isNotAuthenticated(error) {
                    if isNotAuthenticated(error) {
                        disconnect()
                        throw ShikimoriError.notAuthenticated
                    }
                    throw error
                }
                // Legacy session without expiry: keep going and validate below.
            }
        } else if hasStoredExpiry {
            disconnect()
            throw ShikimoriError.notAuthenticated
        }

        guard let token = KeychainHelper.loadShikimoriAccessToken() else {
            throw ShikimoriError.notAuthenticated
        }

        // One-time validation for sessions that predate expiry tracking.
        do {
            _ = try await ShikimoriAPIClient.shared.whoami(accessToken: token)
            cacheExpiry(secondsFromNow: 6 * 60 * 60)
            return token
        } catch {
            if isNotAuthenticated(error) {
                disconnect()
                throw ShikimoriError.notAuthenticated
            }
            throw error
        }
    }

    func userRate(for animeId: Int) async throws -> ShikimoriUserRate? {
        let token = try await accessToken()
        let userId = try await ensureUserId(accessToken: token)
        return try await ShikimoriAPIClient.shared.userRate(userId: userId, animeId: animeId, accessToken: token)
    }

    func setStatus(_ status: ShikimoriListStatus, animeId: Int) async throws -> ShikimoriUserRate {
        let token = try await accessToken()
        let userId = try await ensureUserId(accessToken: token)

        if let existing = try await ShikimoriAPIClient.shared.userRate(
            userId: userId,
            animeId: animeId,
            accessToken: token
        ) {
            return try await ShikimoriAPIClient.shared.updateUserRate(
                rateId: existing.id,
                status: status,
                accessToken: token
            )
        }

        return try await ShikimoriAPIClient.shared.createUserRate(
            userId: userId,
            animeId: animeId,
            status: status,
            accessToken: token
        )
    }

    func syncEpisodeCount(animeId: Int, episodeOrdinal: Int) async {
        guard episodeOrdinal > 0 else { return }
        do {
            let token = try await accessToken()
            let userId = try await ensureUserId(accessToken: token)
            guard let existing = try await ShikimoriAPIClient.shared.userRate(
                userId: userId,
                animeId: animeId,
                accessToken: token
            ) else { return }

            guard episodeOrdinal > (existing.episodes ?? 0) else { return }

            _ = try await ShikimoriAPIClient.shared.updateUserRateEpisodes(
                rateId: existing.id,
                episodes: episodeOrdinal,
                accessToken: token
            )
            AppLog.shikimori.info("Synced episode \(episodeOrdinal) for anime \(animeId)")
        } catch {
            AppLog.shikimori.error("Episode sync failed: \(error.localizedDescription)")
        }
    }

    private var isAccessTokenFresh: Bool {
        guard let expiresAt = UserDefaults.standard.object(forKey: expiresAtKey) as? Date else {
            return false
        }
        return expiresAt.timeIntervalSinceNow > expirySkew
    }

    private var hasStoredExpiry: Bool {
        UserDefaults.standard.object(forKey: expiresAtKey) != nil
    }

    private func persistTokens(_ tokens: ShikimoriTokenResponse) {
        KeychainHelper.saveShikimoriTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
        cacheExpiry(secondsFromNow: TimeInterval(max(tokens.expiresIn, 0)))
    }

    private func cacheExpiry(secondsFromNow: TimeInterval) {
        UserDefaults.standard.set(Date().addingTimeInterval(secondsFromNow), forKey: expiresAtKey)
    }

    private func fetchProfile() async throws -> ShikimoriUserProfile {
        let token = try await accessToken()
        return try await ensureProfile(accessToken: token)
    }

    private func ensureUserId(accessToken: String) async throws -> Int {
        try await ensureProfile(accessToken: accessToken).id
    }

    private func ensureProfile(accessToken: String) async throws -> ShikimoriUserProfile {
        if let profile {
            return profile
        }
        let user = try await ShikimoriAPIClient.shared.whoami(accessToken: accessToken)
        profile = user
        return user
    }

    private func refreshTokens(using refreshToken: String) async throws {
        let tokens = try await ShikimoriAPIClient.shared.refreshTokens(refreshToken: refreshToken)
        persistTokens(tokens)
    }

    private func startAuthSession(url: URL) async throws -> URL {
        let presentationAnchorProvider = presentationAnchorProvider
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: ShikimoriConfig.callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: ShikimoriError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = presentationAnchorProvider
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func authorizationCode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
    }

    private func isNotAuthenticated(_ error: Error) -> Bool {
        if case ShikimoriError.notAuthenticated = error {
            return true
        }
        return false
    }

    private func isCanceledLogin(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASWebAuthenticationSessionError.errorDomain
            && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }
}
