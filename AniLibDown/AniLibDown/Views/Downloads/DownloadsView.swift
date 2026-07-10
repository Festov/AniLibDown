import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var playerSession: PlayerSession?
    @State private var showPurgeConfirmation = false

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
                            DownloadGroupRow(group: group) {
                                if let session = downloadManager.playerSession(for: group) {
                                    playerSession = session
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    downloadManager.deleteRelease(group: group)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Очистить кеш", systemImage: "trash") {
                        showPurgeConfirmation = true
                    }
                }
            }
            .confirmationDialog(
                "Очистить кеш загрузок?",
                isPresented: $showPurgeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Очистить всё", role: .destructive) {
                    downloadManager.purgeAllDownloadData()
                }
                Button("Только осиротевшие файлы") {
                    downloadManager.purgeOrphanedDownloadCache()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Удаляет частично скачанные файлы из памяти iPhone.")
            }
            .fullScreenCover(item: $playerSession) { session in
                VideoPlayerView(session: session)
            }
        }
    }
}

private struct DownloadGroupRow: View {
    let group: DownloadReleaseGroup
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                if let posterPath = group.posterPath {
                    PosterImage(path: posterPath, cornerRadius: 8)
                        .frame(width: 48, height: 68)
                } else {
                    Image(systemName: "film.stack")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 48, height: 68)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.releaseTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if group.completedCount > 0 {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.accentColor)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(group.completedCount == 0)
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
