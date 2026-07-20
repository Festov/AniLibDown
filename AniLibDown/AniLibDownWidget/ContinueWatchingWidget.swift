import WidgetKit
import SwiftUI

struct ContinueWatchingWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let episodeTitle: String
    let progress: Double
}

struct ContinueWatchingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueWatchingWidgetEntry {
        ContinueWatchingWidgetEntry(date: .now, title: "Аниме", episodeTitle: "Серия 1", progress: 0.4)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueWatchingWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueWatchingWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> ContinueWatchingWidgetEntry {
        let defaults = UserDefaults(suiteName: ContinueWatchingStore.appGroupID) ?? .standard
        guard let data = defaults.data(forKey: "continueWatchingMetadata"),
              let metadata = try? JSONDecoder().decode([String: WidgetMetadata].self, from: data),
              let first = metadata.values.sorted(by: { $0.updatedAt > $1.updatedAt }).first else {
            return ContinueWatchingWidgetEntry(date: .now, title: "AniLibDown", episodeTitle: "Нет активного просмотра", progress: 0)
        }
        return ContinueWatchingWidgetEntry(
            date: .now,
            title: first.releaseTitle,
            episodeTitle: first.episodeTitle,
            progress: 0.35
        )
    }

    private struct WidgetMetadata: Codable {
        let releaseTitle: String
        let episodeTitle: String
        let updatedAt: Date
    }
}

struct ContinueWatchingWidgetView: View {
    let entry: ContinueWatchingWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Продолжить")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(entry.title)
                .font(.headline)
                .lineLimit(2)
            Text(entry.episodeTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: entry.progress)
        }
        .padding()
    }
}

// Add as a Widget Extension target in Xcode to enable. Not part of the app IPA target.
struct ContinueWatchingWidget: Widget {
    let kind = "ContinueWatchingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContinueWatchingProvider()) { entry in
            ContinueWatchingWidgetView(entry: entry)
        }
        .configurationDisplayName("Продолжить просмотр")
        .description("Последний незавершённый тайтл")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
