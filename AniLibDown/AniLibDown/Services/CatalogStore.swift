import Foundation

struct CatalogCacheEntry: Codable {
    let releases: [ReleaseSummary]
    let totalPages: Int
    let cachedAt: Date
}

private struct PersistedCatalogCache: Codable {
    var version: Int
    var entries: [String: CatalogCacheEntry]
    /// Last successful unfiltered first page — restored immediately on launch.
    var browseSnapshot: CatalogCacheEntry?
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
    @Published var sorting: CatalogSorting = .freshAtDesc
    @Published var filterYear: Int?

    private var currentPage = 1
    private var totalPages = 1
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var pageCache: [String: CatalogCacheEntry] = [:]
    private var browseSnapshot: CatalogCacheEntry?
    private var lastRequestedQueryKey: String?

    /// Pages older than this are ignored and refetched.
    private let cacheTTL: TimeInterval = 60 * 60 * 24
    private let cacheVersion = 2
    private let cacheFileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalog-page-cache.json")
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    var canLoadMore: Bool { currentPage < totalPages }

    var hasActiveFilters: Bool {
        !normalizedSearch.isEmpty || !selectedGenreIds.isEmpty || filterYear != nil || sorting != .freshAtDesc
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private init() {
        loadPersistedCache()
        restoreVisibleCatalogIfPossible()
    }

    func loadGenresIfNeeded() async {
        guard genres.isEmpty else { return }
        do {
            genres = try await APIClient.shared.getCatalogGenres()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            // Optional for browsing — keep previous genres if any.
            if genres.isEmpty {
                AppLog.api.error("Genres load failed: \(error.localizedDescription)")
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            let response = try await APIClient.shared.getCatalog(
                page: 1,
                limit: 20,
                search: normalizedSearch.isEmpty ? nil : normalizedSearch,
                genreIds: Array(selectedGenreIds),
                sorting: sorting,
                year: filterYear
            )
            applyFirstPage(response.data, totalPages: response.meta.pagination.totalPages)
            storeCache(page: 1, releases: response.data, totalPages: totalPages)
            if !normalizedSearch.isEmpty {
                SearchHistoryStore.shared.record(normalizedSearch)
            }
        } catch {
            if !isIgnorable(error) {
                errorMessage = error.localizedDescription
            }
            // Keep current list on refresh failure.
        }
    }

    func loadInitialIfNeeded() async {
        if !releases.isEmpty { return }
        await loadInitial(force: false)
    }

    func loadInitial(force: Bool = false) async {
        let queryKey = cacheKey(page: 1)

        if !force, let cached = cachedPage(1) {
            applyFirstPage(cached.releases, totalPages: cached.totalPages)
            lastRequestedQueryKey = queryKey
            return
        }

        if !force,
           !hasActiveFilters,
           let snapshot = browseSnapshot,
           isFresh(snapshot) {
            applyFirstPage(snapshot.releases, totalPages: snapshot.totalPages)
            lastRequestedQueryKey = queryKey
            return
        }

        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        // Do not wipe the list before a successful response — avoids empty catalog on failed reload.
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.getCatalog(
                page: 1,
                limit: 20,
                search: normalizedSearch.isEmpty ? nil : normalizedSearch,
                genreIds: Array(selectedGenreIds),
                sorting: sorting,
                year: filterYear
            )
            applyFirstPage(response.data, totalPages: response.meta.pagination.totalPages)
            storeCache(page: 1, releases: response.data, totalPages: totalPages)
            if !normalizedSearch.isEmpty {
                SearchHistoryStore.shared.record(normalizedSearch)
            }
            lastRequestedQueryKey = queryKey
        } catch {
            if !isIgnorable(error) {
                errorMessage = error.localizedDescription
            }
            if releases.isEmpty {
                if let cached = cachedPage(1) {
                    applyFirstPage(cached.releases, totalPages: cached.totalPages)
                } else if !hasActiveFilters, let snapshot = browseSnapshot, isFresh(snapshot) {
                    applyFirstPage(snapshot.releases, totalPages: snapshot.totalPages)
                }
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
                search: normalizedSearch.isEmpty ? nil : normalizedSearch,
                genreIds: Array(selectedGenreIds),
                sorting: sorting,
                year: filterYear
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
        let queryKey = cacheKey(page: 1)
        // searchable can fire onChange when the view appears with the same empty text
        if queryKey == lastRequestedQueryKey, !releases.isEmpty {
            return
        }

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

    func applySorting(_ newSorting: CatalogSorting) {
        guard sorting != newSorting else { return }
        sorting = newSorting
        applyFilters()
    }

    func applyYearFilter(_ year: Int?) {
        guard filterYear != year else { return }
        filterYear = year
        applyFilters()
    }

    func clearSessionCache() {
        pageCache.removeAll()
        browseSnapshot = nil
        releases = []
        currentPage = 1
        totalPages = 1
        lastRequestedQueryKey = nil
        try? FileManager.default.removeItem(at: cacheFileURL)
    }

    private func applyFirstPage(_ pageReleases: [ReleaseSummary], totalPages: Int) {
        releases = pageReleases
        self.totalPages = max(totalPages, 1)
        currentPage = 2
    }

    private func restoreVisibleCatalogIfPossible() {
        if let cached = cachedPage(1) {
            applyFirstPage(cached.releases, totalPages: cached.totalPages)
            lastRequestedQueryKey = cacheKey(page: 1)
            return
        }
        if let snapshot = browseSnapshot, isFresh(snapshot) {
            applyFirstPage(snapshot.releases, totalPages: snapshot.totalPages)
            lastRequestedQueryKey = cacheKey(page: 1)
        }
    }

    private func cacheKey(page: Int) -> String {
        let genres = selectedGenreIds.sorted().map(String.init).joined(separator: ",")
        let year = filterYear.map(String.init) ?? ""
        return "\(normalizedSearch)|\(genres)|\(sorting.rawValue)|\(year)|\(page)"
    }

    private func cachedPage(_ page: Int) -> CatalogCacheEntry? {
        guard let entry = pageCache[cacheKey(page: page)], isFresh(entry) else {
            if pageCache[cacheKey(page: page)] != nil {
                pageCache.removeValue(forKey: cacheKey(page: page))
                persistCache()
            }
            return nil
        }
        return entry
    }

    private func isFresh(_ entry: CatalogCacheEntry) -> Bool {
        Date().timeIntervalSince(entry.cachedAt) <= cacheTTL
    }

    private func storeCache(page: Int, releases: [ReleaseSummary], totalPages: Int) {
        let entry = CatalogCacheEntry(
            releases: releases,
            totalPages: totalPages,
            cachedAt: Date()
        )
        pageCache[cacheKey(page: page)] = entry
        if page == 1 && !hasActiveFilters {
            browseSnapshot = entry
        }
        persistCache()
    }

    private func loadPersistedCache() {
        guard let data = try? Data(contentsOf: cacheFileURL) else { return }

        if let decoded = try? decoder.decode(PersistedCatalogCache.self, from: data),
           decoded.version == cacheVersion {
            let now = Date()
            pageCache = decoded.entries.filter { _, entry in
                now.timeIntervalSince(entry.cachedAt) <= cacheTTL
            }
            if let snapshot = decoded.browseSnapshot, now.timeIntervalSince(snapshot.cachedAt) <= cacheTTL {
                browseSnapshot = snapshot
            }
            return
        }

        // Migrate from v1 (no version / no snapshot / different date strategy).
        struct LegacyCache: Codable {
            var entries: [String: CatalogCacheEntry]
        }
        let legacyDecoder = JSONDecoder()
        if let legacy = try? legacyDecoder.decode(LegacyCache.self, from: data) {
            let now = Date()
            pageCache = legacy.entries.filter { _, entry in
                now.timeIntervalSince(entry.cachedAt) <= cacheTTL
            }
            if let first = pageCache["||1"] {
                browseSnapshot = first
            }
            persistCache()
        }
    }

    private func persistCache() {
        let payload = PersistedCatalogCache(
            version: cacheVersion,
            entries: pageCache,
            browseSnapshot: browseSnapshot
        )
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: cacheFileURL, options: .atomic)
    }

    private func isIgnorable(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let message = error.localizedDescription.lowercased()
        return message.contains("cancel") || message.contains("отмен")
    }
}
