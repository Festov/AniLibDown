import SwiftUI

struct ContinueWatchingSection: View {
    @ObservedObject private var store = ContinueWatchingStore.shared
    let onSelect: (ContinueWatchingEntry) -> Void

    var body: some View {
        if !store.entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.continueWatching)
                    .font(.headline)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Materialize Array so ForEach identity is stable (ArraySlice + contextMenu
                        // often captures the wrong element / first item).
                        ForEach(Array(store.entries.prefix(12))) { entry in
                            ContinueWatchingItem(entry: entry, onSelect: onSelect)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Isolated item view so contextMenu/preview close over this entry, not a loop variable.
private struct ContinueWatchingItem: View {
    let entry: ContinueWatchingEntry
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ContinueWatchingCard(entry: entry)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Убрать из «Продолжить просмотр»", role: .destructive) {
                WatchProgressStore.shared.clearRelease(releaseId: entry.releaseId)
            }
        } preview: {
            ContinueWatchingCard(entry: entry)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct ContinueWatchingCard: View {
    let entry: ContinueWatchingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImage(path: entry.posterPath, cornerRadius: 10)
                .frame(width: 120, height: 170)

            Text(entry.releaseTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 120, height: 32, alignment: .topLeading)

            Text(entry.episodeTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            ProgressView(value: entry.progressFraction)
                .tint(.accentColor)
                .frame(width: 120)
        }
        .frame(width: 120, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.releaseTitle), \(entry.episodeTitle), прогресс \(Int(entry.progressFraction * 100)) процентов"
        )
        .accessibilityHint("Удерживайте, чтобы убрать из продолжить просмотр")
    }
}
