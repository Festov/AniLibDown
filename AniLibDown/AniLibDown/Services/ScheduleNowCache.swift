import Foundation

/// Shared in-memory cache for `GET /anime/schedule/now` so schedule UI and
/// episode alerts do not hit the network twice in parallel.
@MainActor
enum ScheduleNowCache {
    private static var cached: (value: ScheduleNowResponse, fetchedAt: Date)?
    private static var inFlight: Task<ScheduleNowResponse, Error>?
    private static let ttl: TimeInterval = 90

    static func get(force: Bool = false) async throws -> ScheduleNowResponse {
        if !force,
           let cached,
           Date().timeIntervalSince(cached.fetchedAt) < ttl {
            return cached.value
        }

        if let inFlight {
            return try await inFlight.value
        }

        let task = Task {
            try await APIClient.shared.getScheduleNow()
        }
        inFlight = task
        defer { inFlight = nil }

        let value = try await task.value
        cached = (value, Date())
        return value
    }

    static func invalidate() {
        cached = nil
    }
}
