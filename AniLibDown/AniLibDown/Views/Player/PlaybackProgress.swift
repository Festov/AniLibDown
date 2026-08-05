import AVKit
import Foundation

@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false

    private var observer: Any?
    var onTimeUpdate: ((Double) -> Void)?

    func observe(player: AVPlayer, isScrubbing: @escaping () -> Bool) {
        detach(from: player)
        currentTime = 0
        duration = 0

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !isScrubbing() else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                self.currentTime = seconds
                self.onTimeUpdate?(seconds)
            }
            if let item = player.currentItem {
                let total = CMTimeGetSeconds(item.duration)
                if total.isFinite, total > 0 {
                    self.duration = total
                }
            }
            self.isPlaying = player.rate > 0
        }
    }

    func detach(from player: AVPlayer) {
        guard let observer else { return }
        player.removeTimeObserver(observer)
        self.observer = nil
        onTimeUpdate = nil
    }

    func reset() {
        currentTime = 0
        duration = 0
        isPlaying = false
    }
}

