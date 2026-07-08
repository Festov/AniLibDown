import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            LatestView()
                .tabItem {
                    Label("Новинки", systemImage: "sparkles")
                }

            CatalogView()
                .tabItem {
                    Label("Каталог", systemImage: "books.vertical")
                }

            DownloadsView()
                .tabItem {
                    Label("Загрузки", systemImage: "arrow.down.circle")
                }

            ProfileView()
                .tabItem {
                    Label("Профиль", systemImage: "person.circle")
                }
        }
        .preferredColorScheme(appSettings.colorSchemePreference.colorScheme)
        .task {
            await authService.restoreSession()
            await CollectionStatusStore.shared.refresh()
        }
        .onChange(of: authService.isAuthenticated) { _, _ in
            Task { await CollectionStatusStore.shared.refresh() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await authService.refreshSessionIfNeeded() }
            }
        }
    }
}
