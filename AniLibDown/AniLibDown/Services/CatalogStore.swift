import Foundation

struct CatalogCacheEntry: Codable {
    let releases: [ReleaseSummary]
    let totalPages: Int
    let cachedAt: Date
}

@MainActor
final class CatalogStore: ObservableObject {
    static let shared = CatalogStore()

    @Published private(set) var releases: [ReleaseSummary] = []
    @Published var genres: [AnimeGenre] = []
    @Published var selectedGenreIds: Set<Int> = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    private var currentPage = 1
    private var totalPages = 1
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var pageCache: [String: CatalogCacheEntry] = [:]
    private var sessionKey = UUID().uuidString

    var canLoadMore: Bool { currentPage < totalPages }

    var hasActiveFilters: Bool {
        !searchText.isEmpty || !selectedGenreIds.isEmpty
    }

    private init() {}

    func loadGenresIfNeeded() async {
        guard genres.isEmpty else { return }
        do {
            genres = try await APIClient.shared.getCatalogGenres()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            // Optional for browsing.
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        currentPage = 1
        defer { isRefreshing = false }

        do {
            let response = try await APIClient.shared.getCatalog(
                page: 1,
                limit: 20,
                search: searchText.isEmpty ? nil : searchText,
                genreIds: Array(selectedGenreIds)
            )
            releases = response.data
            totalPages = max(response.meta.pagination.totalPages, 1)
            currentPage = 2
            storeCache(page: 1, releases: response.data, totalPages: totalPages)
        } catch {
            if !isIgnorable(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadInitialIfNeeded() async {
        guard releases.isEmpty else { return }
        await loadInitial(force: false)
    }

    func loadInitial(force: Bool = false) async {
        if !force, let cached = cachedFirstPage() {
            releases = cached.releases
            totalPages = cached.totalPages
            currentPage = 2
            return
        }

        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        currentPage = 1
        if force { releases = [] }
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.getCatalog(
                page: 1,
                limit: 20,
                search: searchText.isEmpty ? nil : searchText,
                genreIds: Array(selectedGenreIds)
            )
            releases = response.data
            totalPages = max(response.meta.pagination.totalPages, 1)
            currentPage = 2
            storeCache(page: 1, releases: response.data, totalPages: totalPages)
        } catch {
            if !isIgnorable(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore() async {
        guard !isLoadingMore, canLoadMore, !isLoading, !isRefreshing else { return }

        if let cached = cachedPage(currentPage) {
            releases.append(contentsOf: cached.releases)
            totalPages = cached.totalPages
            currentPage += 1
            return
        }

        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            let response = try await APIClient.shared.getCatalog(
                page: currentPage,
                limit: 20,
                search: searchText.isEmpty ? nil : searchText,
                genreIds: Array(selectedGenreIds)
            )
            releases.append(contentsOf: response.data)
            totalPages = max(response.meta.pagination.totalPages, 1)
            storeCache(page: currentPage, releases: response.data, totalPages: totalPages)
            currentPage += 1
        } catch {
            if !isIgnorable(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func applyFilters() {
        loadTask?.cancel()
        loadTask = Task { await loadInitial(force: true) }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await loadInitial(force: true)
        }
    }

    func toggleGenre(_ genreId: Int) {
        if selectedGenreIds.contains(genreId) {
            selectedGenreIds.remove(genreId)
        } else {
            selectedGenreIds.insert(genreId)
        }
        applyFilters()
    }

    func clearGenreFilters() {
        guard !selectedGenreIds.isEmpty else { return }
        selectedGenreIds.removeAll()
        applyFilters()
    }

    func clearSessionCache() {
        pageCache.removeAll()
        releases = []
        currentPage = 1
        totalPages = 1
        sessionKey = UUID().uuidString
    }

    private func cacheKey(page: Int) -> String {
        let genres = selectedGenreIds.sorted().map(String.init).joined(separator: ",")
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(sessionKey)|\(search)|\(genres)|\(page)"
    }

    private func cachedFirstPage() -> CatalogCacheEntry? {
        cachedPage(1)
    }

    private func cachedPage(_ page: Int) -> CatalogCacheEntry? {
        pageCache[cacheKey(page: page)]
    }

    private func storeCache(page: Int, releases: [ReleaseSummary], totalPages: Int) {
        pageCache[cacheKey(page: page)] = CatalogCacheEntry(
            releases: releases,
            totalPages: totalPages,
            cachedAt: Date()
        )
    }

    private func isIgnorable(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let message = error.localizedDescription.lowercased()
        return message.contains("cancel") || message.contains("отмен")
    }
}
