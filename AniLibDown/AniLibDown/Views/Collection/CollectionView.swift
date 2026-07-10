import SwiftUI

@MainActor
final class CollectionStore: ObservableObject {
    static let shared = CollectionStore()

    @Published private(set) var releases: [ReleaseSummary] = []
    @Published var selectedType: CollectionType = .watching
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?

    private var loadedTypes: Set<CollectionType> = []

    private init() {}

    func loadIfNeeded(type: CollectionType) async {
        guard !loadedTypes.contains(type) || releases.isEmpty else { return }
        await load(type: type, force: false)
    }

    func refresh(type: CollectionType) async {
        await load(type: type, force: true, refreshing: true)
    }

    func load(type: CollectionType, force: Bool = false, refreshing: Bool = false) async {
        if !force, loadedTypes.contains(type), selectedType == type, !releases.isEmpty {
            return
        }

        if refreshing {
            isRefreshing = true
        } else if releases.isEmpty || selectedType != type {
            isLoading = true
        }
        errorMessage = nil
        selectedType = type
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let response = try await APIClient.shared.getCollection(type: type, page: 1, limit: 50)
            releases = response.data
            loadedTypes.insert(type)
        } catch {
            if force || releases.isEmpty {
                errorMessage = error.localizedDescription
                releases = []
            }
        }
    }

    func invalidate() {
        loadedTypes.removeAll()
        releases = []
    }
}

struct CollectionView: View {
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var store = CollectionStore.shared
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            Group {
                if authService.isAuthenticated {
                    collectionContent
                } else {
                    guestContent
                }
            }
            .navigationTitle("Коллекция")
            .navigationDestination(for: Int.self) { releaseId in
                ReleaseDetailView(releaseId: releaseId)
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
            .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    Task { await store.loadIfNeeded(type: store.selectedType) }
                } else {
                    store.invalidate()
                }
            }
        }
    }

    private var guestContent: some View {
        ContentUnavailableView {
            Label("Войдите в аккаунт", systemImage: "heart.text.square")
        } description: {
            Text("Коллекция AniLiberty доступна после авторизации")
        } actions: {
            Button("Войти") { showLogin = true }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var collectionContent: some View {
        VStack(spacing: 0) {
            Picker("Тип", selection: Binding(
                get: { store.selectedType },
                set: { newType in
                    Task { await store.load(type: newType) }
                }
            )) {
                ForEach(CollectionType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Group {
                if store.isLoading && store.releases.isEmpty {
                    List {
                        ForEach(0..<6, id: \.self) { _ in
                            ReleaseRowSkeletonView()
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                } else if store.releases.isEmpty {
                    ContentUnavailableView(
                        "Коллекция пуста",
                        systemImage: "heart",
                        description: Text(store.errorMessage ?? "Добавьте аниме из карточки релиза")
                    )
                } else {
                    List(store.releases) { release in
                        NavigationLink(value: release.id) {
                            ReleaseRowView(
                                title: release.name.main,
                                subtitle: ReleaseFormatting.yearString(release.year),
                                posterPath: release.poster?.displayURL,
                                status: release.broadcastStatus
                            )
                        }
                    }
                    .listStyle(.plain)
                    .overlay {
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.regular)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .task {
            await store.loadIfNeeded(type: store.selectedType)
        }
        .refreshable {
            await store.refresh(type: store.selectedType)
        }
    }
}
