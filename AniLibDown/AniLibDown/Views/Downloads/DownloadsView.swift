import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var playerSession: PlayerSession?

    var body: some View {
        NavigationStack {
            Group {
                if downloadManager.groupedReleases.isEmpty {
                    ContentUnavailableView(
                        "Нет загрузок",
                        systemImage: "arrow.down.circle",
                        description: Text("Скачайте серии на странице аниме для офлайн-просмотра")
                    )
                } else {
                    List {
                        ForEach(downloadManager.groupedReleases) { group in
                            NavigationLink(value: group.id) {
                                DownloadGroupRow(group: group)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Загрузки")
            .navigationDestination(for: String.self) { groupId in
                if let group = downloadManager.groupedReleases.first(where: { $0.id == groupId }) {
                    DownloadReleaseDetailView(group: group) { session in
                        playerSession = session
                    }
                }
            }
            .fullScreenCover(item: $playerSession) { session in
                VideoPlayerView(session: session)
            }
        }
    }
}

private struct DownloadGroupRow: View {
    let group: DownloadReleaseGroup

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.releaseTitle)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts: [String] = ["\(group.items.count) серий"]
        if group.completedCount > 0 {
            parts.append("готово: \(group.completedCount)")
        }
        if group.activeCount > 0 {
            parts.append("загружается: \(group.activeCount)")
        }
        return parts.joined(separator: " • ")
    }
}

struct DownloadReleaseDetailView: View {
    let group: DownloadReleaseGroup
    let onPlay: (PlayerSession) -> Void

    @EnvironmentObject private var downloadManager: DownloadManager

    var body: some View {
        List {
            if group.completedCount > 0 {
                Section {
                    Button("Удалить все скачанные серии", role: .destructive) {
                        downloadManager.deleteCompleted(in: group)
                    }
                }
            }

            Section("Серии") {
                ForEach(group.items) { item in
                    DownloadEpisodeRow(item: item) {
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
        }
        .navigationTitle(group.releaseTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !group.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Удалить всё", role: .destructive) {
                        downloadManager.deleteRelease(group: group)
                    }
                }
            }
        }
    }

    private func play(_ item: DownloadItem) {
        guard item.state == .completed,
              let quality = VideoQuality(rawValue: item.quality),
              let url = downloadManager.localPlaybackURL(for: item.episodeId, quality: quality) else {
            return
        }

        let episodes = group.items
            .filter { $0.state == .completed }
            .sorted { $0.episodeOrdinal < $1.episodeOrdinal }
            .map { downloadItem in
                Episode(
                    id: downloadItem.episodeId,
                    name: downloadItem.episodeTitle,
                    ordinal: downloadItem.episodeOrdinal,
                    opening: nil,
                    ending: nil,
                    preview: nil,
                    hls480: nil,
                    hls720: nil,
                    hls1080: nil,
                    duration: nil,
                    releaseId: downloadItem.releaseId
                )
            }

        guard !episodes.isEmpty else { return }

        _ = url
        onPlay(
            PlayerSession(
                releaseId: group.releaseId ?? 0,
                releaseTitle: group.releaseTitle,
                episodes: episodes,
                startEpisodeId: item.episodeId,
                quality: quality,
                preferOffline: true
            )
        )
    }
}

private struct DownloadEpisodeRow: View {
    let item: DownloadItem
    let onPlay: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.episodeTitle)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(item.quality)
                        .font(.caption2)
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
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.state {
        case .queued:
            Text("В очереди").font(.caption).foregroundStyle(.secondary)
        case .downloading:
            HStack(spacing: 6) {
                ProgressView(value: item.progress).frame(width: 60)
                Text("\(Int(item.progress * 100))%").font(.caption).foregroundStyle(.secondary)
            }
        case .completed:
            Label("Готово", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .failed:
            Label("Ошибка", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
        }
    }
}
