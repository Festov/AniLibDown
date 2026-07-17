import SwiftUI

@MainActor
final class CollectionStore: ObservableObject {
    static let shared = CollectionStore()

    private let pageSize = 10

    @Published private(set) var releases: [ReleaseSummary] = []
    @Published var selectedType: CollectionType = .watching
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?

    private struct TypeCache {
        var releases: [ReleaseSummary]
        var nextPage: Int
        var totalPages: Int
    }

    private var caches: [CollectionType: TypeCache] = [:]

    var canLoadMore: Bool {
        guard let cache = caches[selectedType] else { return false }
        return cache.nextPage <= cache.totalPages
    }

    private init() {}

    func loadIfNeeded(type: CollectionType) async {
        if caches[type] != nil {
            selectedType = type
            releases = caches[type]?.releases ?? []
            return
        }
        await loadInitial(type: type, refreshing: false)
    }

    func refresh(type: CollectionType) async {
        guard !isRefreshing else { return }
        await loadInitial(type: type, refreshing: true)
    }

    func selectType(_ type: CollectionType) async {
        selectedType = type
        if let cache = caches[type] {
            releases = cache.releases
            errorMessage = nil
            return
        }
        releases = []
        await loadInitial(type: type, refreshing: false)
    }

    func load(type: CollectionType, force: Bool = false, refreshing: Bool = false) async {
        if force {
            caches.removeValue(forKey: type)
            if selectedType == type {
                releases = []
            }
            await loadInitial(type: type, refreshing: refreshing)
            return
        }
        await selectType(type)
    }

    func loadMore() async {
        guard !isLoadingMore, !isLoading, !isRefreshing, canLoadMore else { return }
        guard var cache = caches[selectedType] else { return }

        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            let response = try await APIClient.shared.getCollection(
                type: selectedType,
                page: cache.nextPage,
                limit: pageSize
            )
            cache.releases.append(contentsOf: response.data)
            cache.nextPage += 1
            cache.totalPages = max(response.meta.pagination.totalPages, cache.totalPages)
            caches[selectedType] = cache
            releases = cache.releases
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func invalidate() {
        caches.removeAll()
        releases = []
    }

    private func loadInitial(type: CollectionType, refreshing: Bool) async {
        if refreshing {
            isRefreshing = true
        } else if caches[type] == nil {
            isLoading = true
        }
        selectedType = type
        errorMessage = nil
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let response = try await APIClient.shared.getCollection(type: type, page: 1, limit: pageSize)
            let totalPages = max(response.meta.pagination.totalPages, 1)
            caches[type] = TypeCache(
                releases: response.data,
                nextPage: 2,
                totalPages: totalPages
            )
            releases = response.data
        } catch {
            if refreshing {
                errorMessage = error.localizedDescription
            } else if releases.isEmpty {
                errorMessage = error.localizedDescription
                releases = []
            }
        }
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
                    Task { await store.selectType(newType) }
                }
            )) {
                ForEach(CollectionType.allCases) { type in
                    Text(type.shortTitle).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .font(.caption)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Group {
                if (store.isLoading || store.isRefreshing) && store.releases.isEmpty {
                    List {
                        ForEach(0..<6, id: \.self) { _ in
                            ReleaseRowSkeletonView()
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                } else if store.releases.isEmpty {
                    ScrollView {
                        ContentUnavailableView(
                            "Коллекция пуста",
                            systemImage: "heart",
                            description: Text(store.errorMessage ?? "Добавьте аниме из карточки релиза")
                        )
                        .frame(maxWidth: .infinity, minHeight: 360)
                    }
                } else {
                    List {
                        ForEach(store.releases) { release in
                            NavigationLink(value: release.id) {
                                ReleaseRowView(
                                    title: release.name.main,
                                    subtitle: ReleaseFormatting.yearString(release.year),
                                    posterPath: release.poster?.displayURL
                                )
                            }
                            .onAppear {
                                if release.id == store.releases.last?.id {
                                    Task { await store.loadMore() }
                                }
                            }
                        }

                        if store.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
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
