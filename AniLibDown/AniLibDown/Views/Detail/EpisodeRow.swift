import SwiftUI

struct EpisodeRow: View {
    let episode: Episode
    let quality: VideoQuality
    let releaseId: Int
    let releaseTitle: String
    let onPlay: () -> Void
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDeleteDownload: () -> Void
    let onRetryDownload: () -> Void

    @EnvironmentObject private var downloadManager: DownloadManager

    private var downloadItem: DownloadItem? {
        downloadManager.downloadItem(for: episode.id, quality: quality)
    }

    private var downloadState: DownloadItem.DownloadState? {
        downloadItem?.state
    }

    private var downloadProgress: Double {
        downloadItem?.progress ?? 0
    }

    private var isDownloaded: Bool {
        downloadManager.isDownloaded(episodeId: episode.id, quality: quality)
    }

    private var isDownloading: Bool {
        downloadState == .downloading || downloadState == .queued
    }

    private var isFailed: Bool {
        downloadState == .failed
    }

    private var canPlay: Bool {
        quality.streamURL(for: episode) != nil || isDownloaded
    }

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: episode.preview?.thumbnail ?? episode.preview?.displayURL, cornerRadius: 6)
                .frame(width: 72, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.displayTitle)
                    .font(.subheadline.weight(.medium))
                Text(durationString(episode.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isFailed {
                    Text(downloadItem?.lastError ?? "Ошибка загрузки")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            downloadActionButton
        }
        .padding(10)
        .background {
            ZStack(alignment: .leading) {
                Color(.secondarySystemBackground)
                if watchProgress > 0 {
                    Color.accentColor.opacity(0.18)
                        .frame(maxWidth: .infinity)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(maxWidth: .infinity)
                                .scaleEffect(x: watchProgress, y: 1, anchor: .leading)
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(episode.displayTitle)
        .onTapGesture {
            if canPlay {
                onPlay()
            }
        }
    }

    @ViewBuilder
    private var downloadActionButton: some View {
        if isDownloaded {
            Button(action: onDeleteDownload) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Удалить скачанную серию")
        } else if isDownloading {
            Button(action: onCancelDownload) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                        .frame(width: 34, height: 34)

                    Circle()
                        .trim(from: 0, to: max(downloadProgress, downloadState == .queued ? 0.05 : 0))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: downloadProgress)

                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить загрузку")
        } else if isFailed {
            Button(action: onRetryDownload) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Повторить загрузку")
            .accessibilityHint(downloadItem?.lastError ?? "Попробовать скачать снова")
        } else {
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .disabled(quality.streamURL(for: episode) == nil)
            .accessibilityLabel("Скачать серию")
        }
    }

    private var watchProgress: Double {
        WatchProgressStore.shared.progressFraction(for: episode.id, duration: episode.duration)
    }

    private func durationString(_ seconds: Int?) -> String {
        guard let seconds else { return "—" }
        return "\(seconds / 60) мин"
    }
}
