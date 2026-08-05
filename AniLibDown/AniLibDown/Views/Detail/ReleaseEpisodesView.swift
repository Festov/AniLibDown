import SwiftUI

struct ReleaseEpisodesView: View {
    let release: ReleaseDetail

    @EnvironmentObject private var downloadManager: DownloadManager
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var selectedEpisodeRangeIndex = 0
    @State private var playerSession: PlayerSession?

    private let episodeRangeSize = 50

    private var selectedQuality: VideoQuality {
        appSettings.defaultVideoQuality
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                downloadAllButton
                episodesSection
            }
            .padding()
        }
        .navigationTitle("Все серии")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playerSession) { session in
            VideoPlayerView(session: session)
        }
    }

    @ViewBuilder
    private var downloadAllButton: some View {
        let downloadable = release.episodes.filter { selectedQuality.streamURL(for: $0) != nil }
        if !downloadable.isEmpty {
            Button {
                downloadManager.enqueueAll(
                    episodes: downloadable,
                    releaseId: release.id,
                    releaseTitle: release.name.main,
                    quality: selectedQuality,
                    posterPath: release.poster?.displayURL
                )
            } label: {
                Label(
                    "Скачать все серии (\(downloadable.count))",
                    systemImage: "arrow.down.circle.fill"
                )
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
        }
    }

    @ViewBuilder
    private var episodesSection: some View {
        let ranges = episodeRanges(for: release.episodes.count)
        let visibleEpisodes = episodes(in: release.episodes, rangeIndex: selectedEpisodeRangeIndex, ranges: ranges)

        VStack(alignment: .leading, spacing: 8) {
            if release.episodes.isEmpty {
                ContentUnavailableView(
                    "Серий пока нет",
                    systemImage: "film",
                    description: Text("Список появится, когда выйдут серии")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                Text(ReleaseFormatting.episodesCountLabel(release.episodes.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if ranges.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                                Button(range.label) {
                                    selectedEpisodeRangeIndex = index
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedEpisodeRangeIndex == index ? Color.accentColor : .secondary)
                            }
                        }
                    }
                }

                LazyVStack(spacing: 8) {
                    ForEach(visibleEpisodes) { episode in
                        EpisodeRow(
                            episode: episode,
                            quality: selectedQuality,
                            downloadItem: downloadManager.downloadItem(for: episode.id, quality: selectedQuality),
                            watchProgress: WatchProgressStore.shared.progressFraction(
                                for: episode.id,
                                duration: episode.duration
                            ),
                            onPlay: { play(episode: episode) },
                            onDownload: {
                                downloadManager.enqueue(
                                    episode: episode,
                                    releaseId: release.id,
                                    releaseTitle: release.name.main,
                                    quality: selectedQuality,
                                    posterPath: release.poster?.displayURL
                                )
                            },
                            onCancelDownload: {
                                if let item = downloadManager.downloadItem(for: episode.id, quality: selectedQuality) {
                                    downloadManager.cancel(item: item)
                                }
                            },
                            onDeleteDownload: {
                                if let item = downloadManager.downloadItem(for: episode.id, quality: selectedQuality) {
                                    downloadManager.delete(item: item)
                                }
                            },
                            onRetryDownload: {
                                if let item = downloadManager.downloadItem(for: episode.id, quality: selectedQuality) {
                                    downloadManager.retry(item: item)
                                }
                            }
                        )
                        .equatable()
                    }
                }
            }
        }
    }

    private func play(episode: Episode) {
        ContinueWatchingStore.shared.updateMetadata(
            releaseId: release.id,
            releaseTitle: release.name.main,
            posterPath: release.poster?.displayURL,
            episodeId: episode.id,
            episodeTitle: episode.displayTitle,
            duration: episode.duration
        )
        playerSession = PlayerSession(
            releaseId: release.id,
            releaseTitle: release.name.main,
            episodes: release.episodes,
            startEpisodeId: episode.id,
            quality: selectedQuality,
            preferOffline: true,
            episodesTotal: release.episodesTotal,
            posterPath: release.poster?.displayURL
        )
    }

    private struct EpisodeRange {
        let start: Int
        let end: Int

        var label: String { "\(start)-\(end)" }
    }

    private func episodeRanges(for count: Int) -> [EpisodeRange] {
        guard count > 100 else {
            return count > 0 ? [EpisodeRange(start: 1, end: count)] : []
        }

        var ranges: [EpisodeRange] = []
        var start = 1
        while start <= count {
            let end = min(start + episodeRangeSize - 1, count)
            ranges.append(EpisodeRange(start: start, end: end))
            start = end + 1
        }
        return ranges
    }

    private func episodes(in allEpisodes: [Episode], rangeIndex: Int, ranges: [EpisodeRange]) -> [Episode] {
        guard ranges.indices.contains(rangeIndex) else { return allEpisodes }
        let range = ranges[rangeIndex]
        return allEpisodes.filter { episode in
            let number = Int(episode.ordinal.rounded(.towardZero))
            return number >= range.start && number <= range.end
        }
    }
}
