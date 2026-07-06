import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var playerContext: PlayerContext?

    var body: some View {
        NavigationStack {
            Group {
                if downloadManager.items.isEmpty {
                    ContentUnavailableView(
                        "Нет загрузок",
                        systemImage: "arrow.down.circle",
                        description: Text("Скачайте серии на странице аниме для офлайн-просмотра")
                    )
                } else {
                    List {
                        ForEach(downloadManager.items) { item in
                            DownloadRow(item: item) {
                                play(item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    downloadManager.delete(item: item)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Загрузки")
            .fullScreenCover(item: $playerContext) { context in
                VideoPlayerView(
                    title: context.title,
                    streamURL: context.streamURL,
                    isOffline: true
                )
            }
        }
    }

    private func play(_ item: DownloadItem) {
        guard item.state == .completed,
              let quality = VideoQuality(rawValue: item.quality),
              let url = downloadManager.localPlaybackURL(for: item.episodeId, quality: quality) else {
            return
        }
        playerContext = PlayerContext(
            title: "\(item.releaseTitle) — \(item.episodeTitle)",
            streamURL: url,
            isOffline: true
        )
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    let onPlay: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.releaseTitle)
                    .font(.headline)
                Text(item.episodeTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(item.quality)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                    statusView
                }
            }

            Spacer()

            if item.state == .completed {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.state {
        case .queued:
            Text("В очереди")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading:
            HStack(spacing: 6) {
                ProgressView(value: item.progress)
                    .frame(width: 60)
                Text("\(Int(item.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .completed:
            Label("Готово", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Label("Ошибка", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
