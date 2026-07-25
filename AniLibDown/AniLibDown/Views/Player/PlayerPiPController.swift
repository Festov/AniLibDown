import AVKit
import UIKit

@MainActor
final class PlayerPiPController: NSObject, ObservableObject {
    @Published private(set) var isPictureInPicturePossible = false
    @Published private(set) var isPictureInPictureActive = false

    private var pipController: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?

    func attach(to playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPictureInPicturePossible = false
            return
        }

        if pipController?.playerLayer === playerLayer { return }

        possibleObservation?.invalidate()
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
        pipController?.canStartPictureInPictureAutomaticallyFromInline = false

        possibleObservation = pipController?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            Task { @MainActor in
                self?.isPictureInPicturePossible = controller.isPictureInPicturePossible
            }
        }
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
