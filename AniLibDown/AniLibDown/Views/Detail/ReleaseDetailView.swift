import SwiftUI

@MainActor
final class ReleaseDetailViewModel: ObservableObject {
    @Published var release: ReleaseDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(id: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            release = try await APIClient.shared.getRelease(idOrAlias: String(id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ReleaseDetailView: View {
    let releaseId: Int

    @StateObject private var viewModel = ReleaseDetailViewModel()
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var selectedEpisode: Episode?
    @State private var selectedQuality: VideoQuality = .p720
    @State private var playerContext: PlayerContext?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.release == nil {
                ProgressView("Загрузка...")
            } else if let release = viewModel.release {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(for: release)
                        descriptionSection(for: release)
                        qualityPicker
                        episodesSection(for: release)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Не удалось загрузить",
                    systemImage: "exclamationmark.triangle",
                    description: Text(viewModel.errorMessage ?? "Попробуйте позже")
                )
            }
        }
        .navigationTitle(viewModel.release?.name.main ?? "Аниме")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(id: releaseId)
        }
        .fullScreenCover(item: $playerContext) { context in
            VideoPlayerView(
                title: context.title,
                streamURL: context.streamURL,
                isOffline: context.isOffline
            )
        }
    }

    @ViewBuilder
    private func header(for release: ReleaseDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            PosterImage(path: release.poster?.displayURL, cornerRadius: 12)
                .frame(width: 120, height: 170)

            VStack(alignment: .leading, spacing: 6) {
                if let english = release.name.english, !english.isEmpty {
                    Text(english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(release.year) • \(release.type?.description ?? "Аниме")")
                    .font(.subheadline)
                if let rating = release.ageRating?.label {
                    Text(rating)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
                if let genres = release.genres, !genres.isEmpty {
                    Text(genres.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(release.episodes.count) / \(release.episodesTotal ?? release.episodes.count) серий")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func descriptionSection(for release: ReleaseDetail) -> some View {
        if let description = release.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Описание")
                    .font(.headline)
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Качество")
                .font(.headline)
            Picker("Качество", selection: $selectedQuality) {
                ForEach(VideoQuality.allCases) { quality in
                    Text(quality.rawValue).tag(quality)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func episodesSection(for release: ReleaseDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Серии")
                .font(.headline)

            ForEach(release.episodes) { episode in
                EpisodeRow(
                    episode: episode,
                    quality: selectedQuality,
                    releaseTitle: release.name.main,
                    onPlay: { play(episode: episode, releaseTitle: release.name.main) },
                    onDownload: {
                        downloadManager.enqueue(
                            episode: episode,
                            releaseTitle: release.name.main,
                            quality: selectedQuality
                        )
                    }
                )
            }
        }
    }

    private func play(episode: Episode, releaseTitle: String) {
        if let offlineURL = downloadManager.localPlaybackURL(for: episode.id, quality: selectedQuality) {
            playerContext = PlayerContext(
                title: "\(releaseTitle) — \(episode.displayTitle)",
                streamURL: offlineURL,
                isOffline: true
            )
            return
        }

        guard let streamURL = selectedQuality.streamURL(for: episode) else { return }
        playerContext = PlayerContext(
            title: "\(releaseTitle) — \(episode.displayTitle)",
            streamURL: streamURL,
            isOffline: false
        )
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let quality: VideoQuality
    let releaseTitle: String
    let onPlay: () -> Void
    let onDownload: () -> Void

    @EnvironmentObject private var downloadManager: DownloadManager

    private var downloadState: DownloadItem.DownloadState? {
        downloadManager.downloadItem(for: episode.id, quality: quality)?.state
    }

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: episode.preview?.thumbnail ?? episode.preview?.displayURL, cornerRadius: 6)
                .frame(width: 72, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.displayTitle)
                    .font(.subheadline.weight(.medium))
                Text(durationString(episode.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if downloadManager.isDownloaded(episodeId: episode.id, quality: quality) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let state = downloadState {
                switch state {
                case .downloading, .queued:
                    if let item = downloadManager.downloadItem(for: episode.id, quality: quality) {
                        ProgressView(value: item.progress)
                            .frame(width: 28)
                    }
                case .failed:
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(quality.streamURL(for: episode) == nil && !downloadManager.isDownloaded(episodeId: episode.id, quality: quality))

            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(
                quality.streamURL(for: episode) == nil
                || downloadManager.isDownloaded(episodeId: episode.id, quality: quality)
                || downloadState == .downloading
                || downloadState == .queued
            )
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func durationString(_ seconds: Int?) -> String {
        guard let seconds else { return "—" }
        let minutes = seconds / 60
        return "\(minutes) мин"
    }
}

struct PlayerContext: Identifiable {
    let id = UUID()
    let title: String
    let streamURL: URL
    let isOffline: Bool
}
