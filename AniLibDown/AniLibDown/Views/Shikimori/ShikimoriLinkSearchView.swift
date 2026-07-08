import SwiftUI

struct ShikimoriLinkSearchView: View {
    let releaseTitle: String
    let onSelect: (ShikimoriAnime) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ShikimoriAnime] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                ForEach(results) { anime in
                    Button {
                        onSelect(anime)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            shikimoriPoster(for: anime)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(anime.displayTitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if anime.displayTitle != anime.name {
                                    Text(anime.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                if let kind = anime.kind {
                                    Text(kind.uppercased())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if results.isEmpty && !query.isEmpty {
                    ContentUnavailableView(
                        "Ничего не найдено",
                        systemImage: "magnifyingglass",
                        description: Text("Попробуйте другое название")
                    )
                }
            }
            .navigationTitle("Привязка к Shikimori")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Название аниме")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .onChange(of: query) { _, newValue in
                guard newValue.count >= 2 else {
                    results = []
                    return
                }
                Task { await searchDebounced() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .onAppear {
            query = releaseTitle
            Task { await search() }
        }
    }

    @ViewBuilder
    private func shikimoriPoster(for anime: ShikimoriAnime) -> some View {
        if let url = anime.previewURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    SkeletonPoster(cornerRadius: 6)
                }
            }
            .frame(width: 44, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            SkeletonPoster(cornerRadius: 6)
                .frame(width: 44, height: 62)
        }
    }

    @State private var searchTask: Task<Void, Never>?

    private func searchDebounced() async {
        searchTask?.cancel()
        let currentQuery = query
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, currentQuery == query else { return }
            await search()
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            results = try await ShikimoriAPIClient.shared.searchAnimes(query: trimmed)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }
}
