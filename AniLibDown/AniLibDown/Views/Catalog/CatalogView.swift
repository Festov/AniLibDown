import SwiftUI

@MainActor
final class CatalogViewModel: ObservableObject {
    @Published var releases: [ReleaseSummary] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    private var currentPage = 1
    private var totalPages = 1
    private var searchTask: Task<Void, Never>?

    var canLoadMore: Bool {
        currentPage < totalPages
    }

    func load(reset: Bool = true) async {
        if reset {
            guard !isLoading else { return }
            isLoading = true
            currentPage = 1
            releases = []
        } else {
            guard !isLoadingMore, canLoadMore else { return }
            isLoadingMore = true
        }

        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let response = try await APIClient.shared.getCatalog(
                page: currentPage,
                limit: 20,
                search: searchText.isEmpty ? nil : searchText
            )
            if reset {
                releases = response.data
            } else {
                releases.append(contentsOf: response.data)
            }
            totalPages = max(response.meta.pagination.totalPages, 1)
            currentPage += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
    }
}

struct CatalogView: View {
    @StateObject private var viewModel = CatalogViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.releases.isEmpty {
                    ProgressView("Загрузка каталога...")
                } else if viewModel.releases.isEmpty {
                    ContentUnavailableView(
                        "Каталог пуст",
                        systemImage: "books.vertical",
                        description: Text(viewModel.errorMessage ?? "Попробуйте изменить поиск")
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
                                    Task { await viewModel.load(reset: false) }
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
                }
            }
            .navigationTitle("Каталог")
            .searchable(text: $viewModel.searchText, prompt: "Поиск аниме")
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.scheduleSearch()
            }
            .navigationDestination(for: Int.self) { releaseId in
                ReleaseDetailView(releaseId: releaseId)
            }
            .refreshable {
                await viewModel.load(reset: true)
            }
            .task {
                await viewModel.load(reset: true)
            }
            .overlay(alignment: .top) {
                if let error = viewModel.errorMessage, !viewModel.releases.isEmpty {
                    ErrorBanner(message: error)
                        .padding()
                }
            }
        }
    }

    private func subtitle(for release: ReleaseSummary) -> String {
        let genres = release.genres?.map(\.name).prefix(2).joined(separator: ", ") ?? ""
        let type = release.type?.description ?? ""
        return [type, ReleaseFormatting.yearString(release.year), genres].filter { !$0.isEmpty }.joined(separator: " • ")
    }
}
