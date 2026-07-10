import SwiftUI

struct CatalogView: View {
    @ObservedObject private var store = CatalogStore.shared
    @State private var showGenreFilter = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if store.isLoading && store.releases.isEmpty {
                    List {
                        ForEach(0..<8, id: \.self) { _ in
                            ReleaseRowSkeletonView()
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                } else if store.releases.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "books.vertical",
                        description: Text(emptyDescription)
                    )
                } else {
                    List {
                        ForEach(store.releases) { release in
                            NavigationLink(value: release.id) {
                                ReleaseRowView(
                                    title: release.name.main,
                                    subtitle: subtitle(for: release),
                                    posterPath: release.poster?.displayURL,
                                    status: release.broadcastStatus
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
            .navigationTitle("Каталог")
            .searchable(text: $store.searchText, prompt: "Поиск аниме")
            .onChange(of: store.searchText) { _, _ in
                store.scheduleSearch()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGenreFilter = true
                    } label: {
                        Label("Жанры", systemImage: store.selectedGenreIds.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await openRandomRelease() }
                    } label: {
                        Label("Случайное", systemImage: "dice")
                    }
                }
            }
            .sheet(isPresented: $showGenreFilter) {
                GenreFilterView(
                    genres: store.genres,
                    selectedGenreIds: store.selectedGenreIds,
                    onToggle: store.toggleGenre,
                    onClear: store.clearGenreFilters
                )
            }
            .navigationDestination(for: Int.self) { releaseId in
                ReleaseDetailView(releaseId: releaseId)
            }
            .refreshable {
                await store.refresh()
            }
            .task {
                await store.loadGenresIfNeeded()
                await store.loadInitialIfNeeded()
            }
            .overlay(alignment: .top) {
                if let error = store.errorMessage, !store.releases.isEmpty {
                    ErrorBanner(message: error)
                        .padding()
                }
            }
        }
    }

    private var emptyTitle: String {
        store.hasActiveFilters || store.errorMessage != nil ? "Ничего не найдено" : "Каталог пуст"
    }

    private var emptyDescription: String {
        if let error = store.errorMessage, !error.isEmpty {
            return error
        }
        if store.hasActiveFilters {
            return "Попробуйте изменить поиск или сбросить жанры"
        }
        return "Потяните вниз для обновления"
    }

    private func subtitle(for release: ReleaseSummary) -> String {
        let genres = release.genres?.map(\.name).prefix(2).joined(separator: ", ") ?? ""
        let type = release.type?.description ?? ""
        return [type, ReleaseFormatting.yearString(release.year), genres].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private func openRandomRelease() async {
        do {
            let releases = try await APIClient.shared.getRandomReleases(limit: 1)
            if let release = releases.first {
                navigationPath.append(release.id)
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

private struct GenreFilterView: View {
    let genres: [AnimeGenre]
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
                    List {
                        ForEach(genres, id: \.id) { genre in
                            Button {
                                onToggle(genre.id)
                            } label: {
                                HStack {
                                    Text(genre.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedGenreIds.contains(genre.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
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
