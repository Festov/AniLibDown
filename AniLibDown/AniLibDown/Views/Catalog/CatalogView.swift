import SwiftUI

@MainActor
final class CatalogViewModel: ObservableObject {
    @Published var releases: [ReleaseSummary] = []
    @Published var genres: [Genre] = []
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

    var canLoadMore: Bool {
        currentPage < totalPages
    }

    var hasActiveFilters: Bool {
        !searchText.isEmpty || !selectedGenreIds.isEmpty
    }

    func loadGenresIfNeeded() async {
        guard genres.isEmpty else { return }
        do {
            genres = try await APIClient.shared.getCatalogGenres()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            // Genre list is optional for browsing.
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
        } catch {
            if !isIgnorable(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        currentPage = 1
        releases = []
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
        } catch {
            if !isIgnorable(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore() async {
        guard !isLoadingMore, canLoadMore, !isLoading, !isRefreshing else { return }
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
            currentPage += 1
        } catch {
            if !isIgnorable(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func applyFilters() {
        loadTask?.cancel()
        loadTask = Task {
            await loadInitial()
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await loadInitial()
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

    private func isIgnorable(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let message = error.localizedDescription.lowercased()
        return message.contains("cancel") || message.contains("отмен")
    }
}

struct CatalogView: View {
    @StateObject private var viewModel = CatalogViewModel()
    @State private var showGenreFilter = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.releases.isEmpty {
                    ProgressView("Загрузка каталога...")
                } else if viewModel.releases.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "books.vertical",
                        description: Text(emptyDescription)
                    )
                } else {
                    List {
                        ForEach(viewModel.releases) { release in
                            NavigationLink(value: release.id) {
                                ReleaseRowView(
                                    title: release.name.main,
                                    subtitle: subtitle(for: release),
                                    posterPath: release.poster?.displayURL,
                                    status: release.broadcastStatus
                                )
                            }
                            .onAppear {
                                if release.id == viewModel.releases.last?.id {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                        }

                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .overlay {
                        if viewModel.isRefreshing {
                            ProgressView()
                                .controlSize(.regular)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .navigationTitle("Каталог")
            .searchable(text: $viewModel.searchText, prompt: "Поиск аниме")
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.scheduleSearch()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGenreFilter = true
                    } label: {
                        Label("Жанры", systemImage: viewModel.selectedGenreIds.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showGenreFilter) {
                GenreFilterView(
                    genres: viewModel.genres,
                    selectedGenreIds: viewModel.selectedGenreIds,
                    onToggle: viewModel.toggleGenre,
                    onClear: viewModel.clearGenreFilters
                )
            }
            .navigationDestination(for: Int.self) { releaseId in
                ReleaseDetailView(releaseId: releaseId)
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadGenresIfNeeded()
                await viewModel.loadInitial()
            }
            .overlay(alignment: .top) {
                if let error = viewModel.errorMessage, !viewModel.releases.isEmpty {
                    ErrorBanner(message: error)
                        .padding()
                }
            }
        }
    }

    private var emptyTitle: String {
        viewModel.hasActiveFilters || viewModel.errorMessage != nil ? "Ничего не найдено" : "Каталог пуст"
    }

    private var emptyDescription: String {
        if let error = viewModel.errorMessage, !error.isEmpty {
            return error
        }
        if viewModel.hasActiveFilters {
            return "Попробуйте изменить поиск или сбросить жанры"
        }
        return "Потяните вниз для обновления"
    }

    private func subtitle(for release: ReleaseSummary) -> String {
        let genres = release.genres?.map(\.name).prefix(2).joined(separator: ", ") ?? ""
        let type = release.type?.description ?? ""
        return [type, ReleaseFormatting.yearString(release.year), genres].filter { !$0.isEmpty }.joined(separator: " • ")
    }
}

private struct GenreFilterView: View {
    let genres: [Genre]
    let selectedGenreIds: Set<Int>
    let onToggle: (Int) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if genres.isEmpty {
                    ContentUnavailableView(
                        "Жанры недоступны",
                        systemImage: "tag",
                        description: Text("Не удалось загрузить список жанров")
                    )
                } else {
                    List(genres) { genre in
                        Button {
                            onToggle(genre.id)
                        } label: {
                            HStack {
                                Text(genre.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedGenreIds.contains(genre.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accent)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Жанры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !selectedGenreIds.isEmpty {
                        Button("Сбросить", action: onClear)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
