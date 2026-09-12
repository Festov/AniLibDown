import SwiftUI

struct ContinueWatchingSection: View {
    @ObservedObject private var store = ContinueWatchingStore.shared
    let onSelect: (ContinueWatchingEntry) -> Void

    /// Explicit selection for removal — avoids List + horizontal ScrollView
    /// `contextMenu` hit-testing that always resolves to the first card.
    @State private var entryPendingRemoval: ContinueWatchingEntry?

    var body: some View {
        if !store.entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.continueWatching)
                    .font(.headline)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(store.entries.prefix(12))) { entry in
                            ContinueWatchingItem(
                                entry: entry,
                                onSelect: { onSelect(entry) },
                                onRequestRemove: { entryPendingRemoval = entry }
                            )
                            .id(entry.releaseId)
                        }
                    }
                    // Room for scale-up + shadow so top/bottom aren't clipped.
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)
                }
                .scrollClipDisabled()
            }
            .padding(.vertical, 2)
            .confirmationDialog(
                "Убрать из «Продолжить просмотр»?",
                isPresented: Binding(
                    get: { entryPendingRemoval != nil },
                    set: { if !$0 { entryPendingRemoval = nil } }
                ),
                titleVisibility: .visible,
                presenting: entryPendingRemoval
            ) { entry in
                Button("Убрать", role: .destructive) {
                    WatchProgressStore.shared.clearRelease(releaseId: entry.releaseId)
                    entryPendingRemoval = nil
                }
                Button("Отмена", role: .cancel) {
                    entryPendingRemoval = nil
                }
            } message: { entry in
                Text(entry.releaseTitle)
            }
        }
    }
}

private struct ContinueWatchingItem: View {
    let entry: ContinueWatchingEntry
    let onSelect: () -> Void
    let onRequestRemove: () -> Void

    @State private var isPressing = false

    var body: some View {
        ContinueWatchingCard(entry: entry)
            .scaleEffect(isPressing ? 1.07 : 1.0)
            .shadow(color: .black.opacity(isPressing ? 0.18 : 0), radius: isPressing ? 10 : 0, y: isPressing ? 4 : 0)
            .zIndex(isPressing ? 1 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isPressing)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .onLongPressGesture(
                minimumDuration: 0.45,
                maximumDistance: 12,
                pressing: { pressing in
                    isPressing = pressing
                },
                perform: onRequestRemove
            )
            .accessibilityAction(named: "Убрать из «Продолжить просмотр»") {
                onRequestRemove()
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
