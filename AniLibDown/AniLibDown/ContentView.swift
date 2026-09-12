import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case catalog
    case schedule
    case collection
    case downloads
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .catalog: return L10n.catalog
        case .schedule: return L10n.schedule
        case .collection: return L10n.collection
        case .downloads: return L10n.downloads
        case .profile: return L10n.profile
        }
    }

    var icon: String {
        switch self {
        case .catalog: return "books.vertical"
        case .schedule: return "calendar"
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
    @State private var showVersionOverlay = false
    @State private var profileTapTimestamps: [Date] = []

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
        .overlay {
            if showVersionOverlay {
                versionOverlay
            }
        }
        .background(
            ProfileTabTripleTapInstaller {
                showVersionOverlay = true
            }
            .frame(width: 0, height: 0)
        )
        .onChange(of: networkMonitor.isOnWiFi) { _, _ in
            downloadManager.processDownloadQueue()
        }
        .task {
            ContinueWatchingStore.shared.reload()
            await EpisodeAlertStore.shared.rescheduleReminders()
            guard authService.isAuthenticated else { return }
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
                downloadManager.processDownloadQueue()
            }
        }
    }

    private var versionOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showVersionOverlay = false }

            Text(AppVersion.profileLabel)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture { showVersionOverlay = false }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: showVersionOverlay)
        .accessibilityAddTraits(.isModal)
    }

    private var phoneLayout: some View {
        TabView(selection: $selectedTab) {
            tabRoot(.catalog) { CatalogView() }
            tabRoot(.schedule) { ScheduleView() }
            tabRoot(.collection) { CollectionView() }
            tabRoot(.downloads) { DownloadsView() }
            tabRoot(.profile) { ProfileView() }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        if tab == .profile {
                            registerProfileSidebarTap()
                        }
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : .primary)
                    }
                }
            }
            .navigationTitle("AniLibDown")
        } detail: {
            switch selectedTab {
            case .catalog: CatalogView()
            case .schedule: ScheduleView()
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
            .tag(tab)
    }

    private func registerProfileSidebarTap() {
        let now = Date()
        profileTapTimestamps.append(now)
        profileTapTimestamps = profileTapTimestamps.filter { now.timeIntervalSince($0) < 1.0 }
        if profileTapTimestamps.count >= 3 {
            profileTapTimestamps.removeAll()
            showVersionOverlay = true
        }
    }
}

// MARK: - Profile tab triple-tap

/// Listens for three quick taps on the Profile UITabBar item.
private struct ProfileTabTripleTapInstaller: UIViewRepresentable {
    var onTripleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTripleTap: onTripleTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTripleTap = onTripleTap
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    final class Coordinator {
        var onTripleTap: () -> Void
        private weak var observedButton: UIControl?
        private var tapTimes: [CFAbsoluteTime] = []

        init(onTripleTap: @escaping () -> Void) {
            self.onTripleTap = onTripleTap
        }

        func attachIfNeeded(from view: UIView) {
            guard let tabBar = findTabBar(startingFrom: view) else { return }
            let buttons = tabBar.subviews
                .compactMap { $0 as? UIControl }
                .sorted { $0.frame.minX < $1.frame.minX }
            guard let profileButton = buttons.last else { return }
            if observedButton === profileButton { return }

            observedButton?.removeTarget(self, action: #selector(profileTapped), for: .touchUpInside)
            profileButton.addTarget(self, action: #selector(profileTapped), for: .touchUpInside)
            observedButton = profileButton
        }

        @objc private func profileTapped() {
            let now = CFAbsoluteTimeGetCurrent()
            tapTimes.append(now)
            tapTimes = tapTimes.filter { now - $0 < 1.0 }
            guard tapTimes.count >= 3 else { return }
            tapTimes.removeAll()
            DispatchQueue.main.async {
                self.onTripleTap()
            }
        }

        private func findTabBar(startingFrom view: UIView) -> UITabBar? {
            var responder: UIResponder? = view
            while let current = responder {
                if let vc = current as? UIViewController,
                   let tabBar = vc.tabBarController?.tabBar {
                    return tabBar
                }
                responder = current.next
            }

            if let tabBar = findTabBar(inHierarchyOf: view) {
                return tabBar
            }

            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    if let tabBar = findTabBar(inHierarchyOf: window) {
                        return tabBar
                    }
                }
            }
            return nil
        }

        private func findTabBar(inHierarchyOf view: UIView) -> UITabBar? {
            if let tabBar = view as? UITabBar { return tabBar }
            for child in view.subviews {
                if let tabBar = findTabBar(inHierarchyOf: child) {
                    return tabBar
                }
            }
            return nil
        }
    }
}
