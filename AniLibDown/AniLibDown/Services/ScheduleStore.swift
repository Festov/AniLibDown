import Foundation

@MainActor
final class ScheduleStore: ObservableObject {
    static let shared = ScheduleStore()

    enum Mode: String, CaseIterable, Identifiable {
        case near
        case week

        var id: String { rawValue }

        var title: String {
            switch self {
            case .near: return "Близко"
            case .week: return "Неделя"
            }
        }
    }

    @Published var mode: Mode = .near
    @Published private(set) var nearSchedule: ScheduleNowResponse?
    @Published private(set) var weekItems: [ScheduleItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published var showSubscribedOnly = false

    private init() {}

    var weekSections: [(day: PublishDay, items: [ScheduleItem])] {
        let grouped = Dictionary(grouping: weekItems) { item -> Int in
            item.release.publishDay?.value ?? 0
        }
        return (1...7).compactMap { dayValue in
            guard let items = grouped[dayValue], !items.isEmpty else { return nil }
            let title = items.first?.release.publishDay?.description ?? "День \(dayValue)"
            let day = PublishDay(value: dayValue, description: title)
            return (day, items)
        }
    }

    func loadIfNeeded() async {
        guard nearSchedule == nil, weekItems.isEmpty else { return }
        await load(force: false)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await load(force: true)
    }

    func load(force: Bool) async {
        if !force, isLoading { return }
        if nearSchedule == nil && weekItems.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        defer { isLoading = false }

        do {
            if force {
                ScheduleNowCache.invalidate()
            }
            async let near = ScheduleNowCache.get(force: force)
            async let week = APIClient.shared.getScheduleWeek()
            let (nearResult, weekResult) = try await (near, week)
            nearSchedule = nearResult
            weekItems = weekResult
        } catch {
            errorMessage = error.localizedDescription
            if nearSchedule == nil && weekItems.isEmpty {
                AppLog.api.error("Schedule load failed: \(error.localizedDescription)")
            }
        }
    }
}
