import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService

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
        .task {
            await authService.restoreSession()
        }
    }
}
