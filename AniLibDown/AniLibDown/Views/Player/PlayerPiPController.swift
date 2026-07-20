import AVKit
import UIKit

@MainActor
final class PlayerPiPController: NSObject, ObservableObject {
    @Published private(set) var isPictureInPicturePossible = false
    @Published private(set) var isPictureInPictureActive = false

    private var pipController: AVPictureInPictureController?
    private weak var playerLayer: AVPlayerLayer?

    func attach(to playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        self.playerLayer = playerLayer
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
        isPictureInPicturePossible = pipController?.isPictureInPicturePossible ?? false
    }

    func togglePictureInPicture() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else if pipController.isPictureInPicturePossible {
            pipController.startPictureInPicture()
        }
    }

    func refreshAvailability() {
        isPictureInPicturePossible = pipController?.isPictureInPicturePossible ?? false
    }
}

extension PlayerPiPController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in isPictureInPictureActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in isPictureInPictureActive = false }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            AppLog.player.error("PiP failed: \(error.localizedDescription)")
        }
    }
}
