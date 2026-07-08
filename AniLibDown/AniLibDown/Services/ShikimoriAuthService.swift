import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class ShikimoriAuthService: NSObject, ObservableObject {
    static let shared = ShikimoriAuthService()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var profile: ShikimoriUserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var authSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
    }

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
        } catch ShikimoriError.notAuthenticated {
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
        } catch {
            // Keep tokens on transient errors
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

        var components = URLComponents(string: "https://shikimori.one/oauth/authorize")!
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
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
        } catch ShikimoriError.notAuthenticated {
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
        try await withCheckedThrowingContinuation { continuation in
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
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            session.start()
        }
    }

    private func authorizationCode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
    }
}

extension ShikimoriAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) {
                return window
            }
            return scenes.flatMap(\.windows).first ?? UIWindow()
        }
    }
}
