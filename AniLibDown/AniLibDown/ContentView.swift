import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            CatalogView()
                .tabItem {
                    Label("Каталог", systemImage: "books.vertical")
                }

            CollectionView()
                .tabItem {
                    Label("Коллекция", systemImage: "heart.text.square")
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
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            Task { await CollectionStatusStore.shared.refresh() }
            if !isAuthenticated {
                CollectionStore.shared.invalidate()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await authService.refreshSessionIfNeeded() }
            }
        }
    }
}
