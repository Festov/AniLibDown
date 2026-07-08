import Foundation

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var profile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {}

    func restoreSession() async {
        guard let token = KeychainHelper.loadToken() else { return }
        await APIClient.shared.setAccessToken(token)
        do {
            profile = try await APIClient.shared.getProfile()
            isAuthenticated = true
            await CollectionStatusStore.shared.refresh()
        } catch let error as APIError {
            if case .unauthorized = error {
                KeychainHelper.deleteToken()
                await APIClient.shared.setAccessToken(nil)
                isAuthenticated = false
                profile = nil
            }
        } catch {
            // Keep token on transient network/decoding errors
        }
    }

    func refreshSessionIfNeeded() async {
        guard KeychainHelper.loadToken() != nil else { return }
        if isAuthenticated {
            do {
                profile = try await APIClient.shared.getProfile()
            } catch let error as APIError {
                if case .unauthorized = error {
                    KeychainHelper.deleteToken()
                    await APIClient.shared.setAccessToken(nil)
                    isAuthenticated = false
                    profile = nil
                }
            } catch {
                // Ignore transient errors
            }
        } else {
            await restoreSession()
        }
    }

    func login(login: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let token = try await APIClient.shared.login(login: login, password: password)
            KeychainHelper.saveToken(token)
            profile = try await APIClient.shared.getProfile()
            isAuthenticated = true
            await CollectionStatusStore.shared.refresh()
        } catch {
            errorMessage = error.localizedDescription
            isAuthenticated = false
            profile = nil
        }
    }

    func logout() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await APIClient.shared.logout()
        } catch {
            // Ignore network errors on logout
        }
        KeychainHelper.deleteToken()
        await APIClient.shared.setAccessToken(nil)
        isAuthenticated = false
        profile = nil
        await CollectionStatusStore.shared.refresh()
    }
}
