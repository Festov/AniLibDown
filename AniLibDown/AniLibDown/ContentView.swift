import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case catalog
    case collection
    case downloads
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .catalog: return L10n.catalog
        case .collection: return L10n.collection
        case .downloads: return L10n.downloads
        case .profile: return L10n.profile
        }
    }

    var icon: String {
        switch self {
        case .catalog: return "books.vertical"
        case .collection: return "heart.text.square"
        case .downloads: return "arrow.down.circle"
        case .profile: return "person.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var downloadManager: DownloadManager
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .catalog

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadLayout
            } else {
                phoneLayout
            }
        }
        .preferredColorScheme(appSettings.colorSchemePreference.colorScheme)
        .toastOverlay()
        .overlay(alignment: .top) {
            if !networkMonitor.isConnected {
                Text(L10n.offline)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(.top, 6)
            }
        }
        .onChange(of: networkMonitor.isOnWiFi) { _, _ in
            downloadManager.processDownloadQueue()
        }
        .task {
            await authService.restoreSession()
            await CollectionStatusStore.shared.refresh()
            ContinueWatchingStore.shared.reload()
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
                downloadManager.processDownloadQueue()
            }
        }
    }

    private var phoneLayout: some View {
        TabView {
            tabRoot(.catalog) { CatalogView() }
            tabRoot(.collection) { CollectionView() }
            tabRoot(.downloads) { DownloadsView() }
            tabRoot(.profile) { ProfileView() }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("AniLibDown")
        } detail: {
            switch selectedTab {
            case .catalog: CatalogView()
            case .collection: CollectionView()
            case .downloads: DownloadsView()
            case .profile: ProfileView()
            }
        }
    }

    private func tabRoot<V: View>(_ tab: AppTab, @ViewBuilder content: () -> V) -> some View {
        content()
            .tabItem {
                Label(tab.title, systemImage: tab.icon)
            }
    }
}
