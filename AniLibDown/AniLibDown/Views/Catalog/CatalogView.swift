import SwiftUI

struct CatalogView: View {
    @ObservedObject private var store = CatalogStore.shared
    @ObservedObject private var searchHistory = SearchHistoryStore.shared
    @ObservedObject private var continueWatching = ContinueWatchingStore.shared
    @State private var showGenreFilter = false
    @State private var showCatalogFilters = false
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
                    ScrollView {
                        ContentUnavailableView {
                            Label(emptyTitle, systemImage: emptySystemImage)
                        } description: {
                            Text(emptyDescription)
                        } actions: {
                            if store.errorMessage != nil {
                                Button("Повторить") {
                                    Task { await store.loadInitial(force: true) }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 420)
                    }
                } else {
                    List {
                        if store.searchText.isEmpty {
                            Section {
                                ContinueWatchingSection { entry in
                                    navigationPath.append(entry.releaseId)
                                }
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }

                        if store.searchText.isEmpty, !searchHistory.queries.isEmpty {
                            Section(L10n.searchHistory) {
                                ForEach(searchHistory.queries, id: \.self) { query in
                                    Button(query) {
                                        store.searchText = query
                                        store.scheduleSearch()
                                    }
                                    .accessibilityLabel("Поиск: \(query)")
                                    .accessibilityHint("Свайп влево для удаления")
                                }
                                .onDelete { indexSet in
                                    indexSet.map { searchHistory.queries[$0] }.forEach(searchHistory.remove)
                                }
                            }
                        }

                        ForEach(store.releases) { release in
                            NavigationLink(value: release.id) {
                                ReleaseRowView(
                                    title: release.name.main,
                                    subtitle: subtitle(for: release),
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
            .navigationTitle(L10n.catalog)
            .searchable(text: $store.searchText, prompt: "Поиск аниме")
            .onChange(of: store.searchText) { _, _ in
                store.scheduleSearch()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCatalogFilters = true
                    } label: {
                        Label("Фильтры", systemImage: hasAdvancedFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGenreFilter = true
                    } label: {
                        Label("Жанры", systemImage: store.selectedGenreIds.isEmpty ? "tag" : "tag.fill")
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
            .sheet(isPresented: $showCatalogFilters) {
                CatalogFiltersView(
                    sorting: store.sorting,
                    filterYear: store.filterYear,
                    onApplySorting: store.applySorting,
                    onApplyYear: store.applyYearFilter
                )
            }
            .navigationDestination(for: Int.self) { releaseId in
                ReleaseDetailView(releaseId: releaseId)
            }
            .refreshable {
                await store.refresh()
                continueWatching.reload()
            }
            .task {
                await store.loadGenresIfNeeded()
                await store.loadInitialIfNeeded()
                continueWatching.reload()
            }
            .overlay(alignment: .top) {
                if let error = store.errorMessage, !store.releases.isEmpty {
                    ErrorBanner(message: error)
                        .padding()
                }
            }
        }
    }

    private var hasAdvancedFilters: Bool {
        store.sorting != .freshAtDesc || store.filterYear != nil
    }

    private var emptyTitle: String {
        if store.errorMessage != nil, !store.hasActiveFilters {
            return "Не удалось загрузить"
        }
        if store.hasActiveFilters || store.errorMessage != nil {
            return "Ничего не найдено"
        }
        return "Каталог пуст"
    }

    private var emptySystemImage: String {
        store.errorMessage != nil && !store.hasActiveFilters ? "wifi.exclamationmark" : "books.vertical"
    }

    private var emptyDescription: String {
        if let error = store.errorMessage, !error.isEmpty {
            return error
        }
        if store.hasActiveFilters {
            return "Попробуйте изменить поиск или сбросить фильтры"
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
            ToastCenter.shared.show(error.localizedDescription, isError: true)
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
                            .accessibilityLabel(genre.name)
                            .accessibilityAddTraits(selectedGenreIds.contains(genre.id) ? .isSelected : [])
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

private struct CatalogFiltersView: View {
    let sorting: CatalogSorting
    let filterYear: Int?
    let onApplySorting: (CatalogSorting) -> Void
    let onApplyYear: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var yearText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Сортировка") {
                    Picker("Сортировка", selection: Binding(
                        get: { sorting },
                        set: { onApplySorting($0) }
                    )) {
                        ForEach(CatalogSorting.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Год выпуска") {
                    TextField("Например, 2024", text: $yearText)
                        .keyboardType(.numberPad)
                    Button("Применить год") {
                        guard let year = validatedYear else { return }
                        onApplyYear(year)
                        dismiss()
                    }
                    .disabled(validatedYear == nil)
                    if filterYear != nil {
                        Button("Сбросить год", role: .destructive) {
                            yearText = ""
                            onApplyYear(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .onAppear {
                if let filterYear {
                    yearText = String(filterYear)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var validatedYear: Int? {
        let trimmed = yearText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let year = Int(trimmed) else { return nil }
        let maxYear = Calendar.current.component(.year, from: Date()) + 1
        guard (1960...maxYear).contains(year) else { return nil }
        return year
    }
}
