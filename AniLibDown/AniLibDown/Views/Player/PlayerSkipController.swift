import SwiftUI

struct PlayerSkipPrompt: Identifiable, Equatable {
    let id: String
    let title: String
    let endTime: Double
}

/// Owns the "skip opening / ending" prompt: which segment was already handled,
/// which ones the user declined, and the 3-second countdown shown for a new one.
@MainActor
final class PlayerSkipController: ObservableObject {
    @Published private(set) var prompt: PlayerSkipPrompt?
    @Published private(set) var promptProgress: Double = 0

    /// Called when the countdown finishes and playback must jump to the segment end.
    var onSkip: ((Double) -> Void)?

    private let settings: PlayerSettings
    private var promptTask: Task<Void, Never>?
    private var lastSkippedSegment: String?
    private var declinedSkipSegments: Set<String> = []

    init(settings: PlayerSettings = .shared) {
        self.settings = settings
    }

    func reset() {
        lastSkippedSegment = nil
        declinedSkipSegments = []
        cancelPrompt()
    }

    func cancelPrompt() {
        promptTask?.cancel()
        promptProgress = 0
        prompt = nil
    }

    func decline() {
        guard let prompt else { return }
        promptTask?.cancel()
        declinedSkipSegments.insert(prompt.id)
        withAnimation(playerOverlayAnimation) {
            promptProgress = 0
            self.prompt = nil
        }
    }

    func handle(time: Double, episode: Episode, duration: Double) {
        guard settings.skipOpening || settings.skipEnding else {
            cancelPrompt()
            return
        }

        if let prompt {
            let stillInside = isInsideSegment(
                time: time,
                episode: episode,
                segmentKey: prompt.id,
                duration: duration
            )
            if !stillInside {
                cancelPrompt()
            }
            return
        }

        let segments: [(key: String, title: String, skip: EpisodeSkip?)] = [
            ("opening", "Опенинг", episode.opening),
            ("ending", "Эндинг", episode.ending)
        ]

        for (key, title, skip) in segments {
            if key == "opening", !settings.skipOpening { continue }
            if key == "ending", !settings.skipEnding { continue }

            guard let bounds = segmentBounds(for: key, skip: skip, duration: duration) else { continue }

            let segmentKey = "\(episode.id)-\(key)"
            if declinedSkipSegments.contains(segmentKey) { continue }
            if lastSkippedSegment == segmentKey { continue }

            guard time >= bounds.start, time < bounds.end else { continue }
            presentPrompt(segmentKey: segmentKey, title: title, endTime: bounds.end)
            return
        }
    }

    // MARK: - Segment math

    private func segmentBounds(
        for key: String,
        skip: EpisodeSkip?,
        duration: Double
    ) -> (start: Double, end: Double)? {
        guard let skip else { return nil }

        let start = Double(skip.start ?? 0)
        let end: Double

        if let stop = skip.stop {
            end = Double(stop)
        } else if key == "ending", duration > 0 {
            end = duration
        } else {
            return nil
        }

        let segmentDuration = end - start
        guard segmentDuration > 0 else { return nil }

        if key == "opening" && segmentDuration > 300 {
            return nil
        }

        if key == "ending" && duration > 0 && start < duration * 0.4 {
            return nil
        }

        return (start, end)
    }

    private func isInsideSegment(
        time: Double,
        episode: Episode,
        segmentKey: String,
        duration: Double
    ) -> Bool {
        let segments: [(key: String, skip: EpisodeSkip?)] = [
            ("opening", episode.opening),
            ("ending", episode.ending)
        ]

        for (key, skip) in segments {
            let currentKey = "\(episode.id)-\(key)"
            guard currentKey == segmentKey else { continue }
            guard let bounds = segmentBounds(for: key, skip: skip, duration: duration) else {
                return false
            }
            return time >= bounds.start && time < bounds.end
        }
        return false
    }

    // MARK: - Countdown

    private func presentPrompt(segmentKey: String, title: String, endTime: Double) {
        promptTask?.cancel()
        promptProgress = 0
        withAnimation(playerOverlayAnimation) {
            prompt = PlayerSkipPrompt(id: segmentKey, title: title, endTime: endTime)
        }

        withAnimation(.linear(duration: 3)) {
            promptProgress = 1
        }

        promptTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.prompt?.id == segmentKey else { return }
                self.performSkip(to: endTime, segmentKey: segmentKey)
            }
        }
    }

    private func performSkip(to endTime: Double, segmentKey: String) {
        lastSkippedSegment = segmentKey
        withAnimation(playerOverlayAnimation) {
            promptProgress = 0
            prompt = nil
        }
        onSkip?(endTime)
    }
}