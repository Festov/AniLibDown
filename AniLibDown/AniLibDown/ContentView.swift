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
            .accessibilityHidden(true)
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

/// Attaches a 3-tap gesture to `UITabBar` and fires only when the tap is in the Profile item zone.
/// Works on iOS 17/18 where tab items may not be plain `UIControl`s.
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
        context.coordinator.scheduleAttach(from: uiView)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTripleTap: () -> Void
        private weak var attachedTabBar: UITabBar?
        private var gesture: UITapGestureRecognizer?
        private var attachAttempts = 0
        private var profileTapTimes: [CFAbsoluteTime] = []

        init(onTripleTap: @escaping () -> Void) {
            self.onTripleTap = onTripleTap
        }

        func scheduleAttach(from view: UIView) {
            DispatchQueue.main.async { [weak self] in
                self?.attachIfNeeded(from: view)
            }
            // Tab bar may appear after first layout; retry a few times.
            if attachedTabBar == nil, attachAttempts < 12 {
                attachAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.attachIfNeeded(from: view)
                }
            }
        }

        func attachIfNeeded(from view: UIView) {
            guard let tabBar = findTabBar(startingFrom: view) else { return }
            if attachedTabBar === tabBar, gesture != nil { return }

            if let old = gesture, let oldBar = attachedTabBar {
                oldBar.removeGestureRecognizer(old)
            }

            // Count single taps ourselves — `numberOfTapsRequired = 3` often fails
            // because UITabBar buttons consume the first taps.
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.numberOfTapsRequired = 1
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            tabBar.addGestureRecognizer(tap)
            tabBar.isUserInteractionEnabled = true

            gesture = tap
            attachedTabBar = tabBar
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let tabBar = attachedTabBar else { return }
            let location = gesture.location(in: tabBar)
            guard isInProfileItem(location: location, tabBar: tabBar) else {
                profileTapTimes.removeAll()
                return
            }

            let now = CFAbsoluteTimeGetCurrent()
            profileTapTimes.append(now)
            profileTapTimes = profileTapTimes.filter { now - $0 < 1.0 }
            guard profileTapTimes.count >= 3 else { return }
            profileTapTimes.removeAll()
            DispatchQueue.main.async {
                self.onTripleTap()
            }
        }

        private func isInProfileItem(location: CGPoint, tabBar: UITabBar) -> Bool {
            let itemCount = tabBar.items?.count ?? AppTab.allCases.count
            guard itemCount > 0 else { return false }

            // Prefer real tab-button frames when available (varies by iOS version).
            let candidates = tabBar.subviews
                .filter { subview in
                    !subview.isHidden
                        && subview.alpha > 0.01
                        && subview.frame.width > 24
                        && subview.frame.height > 24
                        && !(subview is UIImageView)
                        && !(subview is UILabel)
                        && !(subview is UIVisualEffectView)
                }
                .sorted { $0.frame.minX < $1.frame.minX }

            if candidates.count >= itemCount {
                return candidates[itemCount - 1].frame.contains(location)
            }

            let width = max(tabBar.bounds.width, 1) / CGFloat(itemCount)
            let index = min(itemCount - 1, max(0, Int(location.x / width)))
            return index == itemCount - 1
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

            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows where !window.isHidden {
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
