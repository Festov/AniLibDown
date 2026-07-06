import SwiftUI

@main
struct AniLibDownApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var downloadManager = DownloadManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(downloadManager)
        }
    }
}
