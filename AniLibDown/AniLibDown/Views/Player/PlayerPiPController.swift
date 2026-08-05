import AVKit
import UIKit

@MainActor
final class PlayerPiPController: NSObject, ObservableObject {
    @Published private(set) var isPictureInPictureActive = false

    private var pipController: AVPictureInPictureController?

    func attach(to playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return
        }

        if pipController?.playerLayer === playerLayer { return }

        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
        pipController?.canStartPictureInPictureAutomaticallyFromInline = false
    }

    func togglePictureInPicture() {
        guard let pipController else {
            ToastCenter.shared.show("Картинка в картинке недоступна", isError: true)
            return
        }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
            return
        }
        guard pipController.isPictureInPicturePossible else {
            ToastCenter.shared.show("PiP пока недоступен. Дождитесь начала воспроизведения.", isError: true)
            return
        }
        pipController.startPictureInPicture()
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
            ToastCenter.shared.show("Не удалось включить картинку в картинке", isError: true)
        }
    }
}
