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

    private init() {}

    func restoreSession() async {
        guard ShikimoriConfig.isConfigured,
              KeychainHelper.loadShikimoriAccessToken() != nil else {
            isAuthenticated = false
            profile = nil
            return
        }

        do {
            let user = try await validAccessTokenProfile()
            profile = user
            isAuthenticated = true
        } catch {
            if isNotAuthenticated(error) {
                if let refresh = KeychainHelper.loadShikimoriRefreshToken() {
                    do {
                        try await refreshTokens(using: refresh)
                        let user = try await validAccessTokenProfile()
                        profile = user
                        isAuthenticated = true
                        return
                    } catch {
                        disconnect()
                    }
                } else {
                    disconnect()
                }
            }
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
            KeychainHelper.saveShikimoriTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
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
        isAuthenticated = false
        profile = nil
        errorMessage = nil
    }

    func accessToken() async throws -> String {
        guard ShikimoriConfig.isConfigured else {
            throw ShikimoriError.notConfigured
        }
        guard let token = KeychainHelper.loadShikimoriAccessToken() else {
            throw ShikimoriError.notAuthenticated
        }

        do {
            _ = try await ShikimoriAPIClient.shared.whoami(accessToken: token)
            return token
        } catch {
            if isNotAuthenticated(error) {
                guard let refresh = KeychainHelper.loadShikimoriRefreshToken() else {
                    disconnect()
                    throw ShikimoriError.notAuthenticated
                }
                try await refreshTokens(using: refresh)
                guard let refreshed = KeychainHelper.loadShikimoriAccessToken() else {
                    throw ShikimoriError.notAuthenticated
                }
                return refreshed
            }
            throw error
        }
    }

    func userRate(for animeId: Int) async throws -> ShikimoriUserRate? {
        let token = try await accessToken()
        guard let userId = profile?.id else {
            let user = try await ShikimoriAPIClient.shared.whoami(accessToken: token)
            profile = user
            return try await ShikimoriAPIClient.shared.userRate(userId: user.id, animeId: animeId, accessToken: token)
        }
        return try await ShikimoriAPIClient.shared.userRate(userId: userId, animeId: animeId, accessToken: token)
    }

    func setStatus(_ status: ShikimoriListStatus, animeId: Int) async throws -> ShikimoriUserRate {
        let token = try await accessToken()
        let userId: Int
        if let profile {
            userId = profile.id
        } else {
            let user = try await ShikimoriAPIClient.shared.whoami(accessToken: token)
            profile = user
            userId = user.id
        }

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
            let userId = profile?.id ?? (try await ShikimoriAPIClient.shared.whoami(accessToken: token)).id
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

    private func validAccessTokenProfile() async throws -> ShikimoriUserProfile {
        guard let token = KeychainHelper.loadShikimoriAccessToken() else {
            throw ShikimoriError.notAuthenticated
        }
        return try await ShikimoriAPIClient.shared.whoami(accessToken: token)
    }

    private func refreshTokens(using refreshToken: String) async throws {
        let tokens = try await ShikimoriAPIClient.shared.refreshTokens(refreshToken: refreshToken)
        KeychainHelper.saveShikimoriTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
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
