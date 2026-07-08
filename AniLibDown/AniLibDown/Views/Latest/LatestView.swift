import SwiftUI

@MainActor
final class ReleaseListViewModel: ObservableObject {
    @Published var releases: [ReleaseLatest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            releases = try await APIClient.shared.getLatestReleases(limit: 30)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LatestView: View {
    @StateObject private var viewModel = ReleaseListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.releases.isEmpty {
                    List {
                        ForEach(0..<8, id: \.self) { _ in
                            ReleaseRowSkeletonView()
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                } else if viewModel.releases.isEmpty {
                    ContentUnavailableView(
                        "Нет данных",
                        systemImage: "sparkles",
                        description: Text(viewModel.errorMessage ?? "Потяните вниз для обновления")
                    )
                } else {
                    List(viewModel.releases) { release in
                        NavigationLink(value: release.id) {
                            ReleaseRowView(
                                title: release.name.main,
                                subtitle: subtitle(for: release),
                                posterPath: release.poster?.displayURL,
                                status: release.broadcastStatus
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Новинки")
            .navigationDestination(for: Int.self) { releaseId in
                ReleaseDetailView(releaseId: releaseId)
            }
            .refreshable {
                await viewModel.load()
            }
            .task {
                await viewModel.load()
            }
            .overlay(alignment: .top) {
                if let error = viewModel.errorMessage, !viewModel.releases.isEmpty {
                    ErrorBanner(message: error)
                        .padding()
                }
            }
        }
    }

    private func subtitle(for release: ReleaseLatest) -> String {
        let genres = release.genres?.map(\.name).prefix(2).joined(separator: ", ") ?? ""
        let episode = "Серия \(release.latestEpisode.ordinalFormatted)"
        return [episode, ReleaseFormatting.yearString(release.year), genres].filter { !$0.isEmpty }.joined(separator: " • ")
    }
}
