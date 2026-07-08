import SwiftUI

@main
struct AniLibDownApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authService = AuthService.shared
    @StateObject private var downloadManager = DownloadManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(downloadManager)
                .task {
                    await ShikimoriAuthService.shared.restoreSession()
                }
        }
    }
}
