import UIKit
import AVFoundation

@MainActor
final class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    @Published private(set) var isLandscapeLocked = false

    /// Readable from AppDelegate without crossing actor isolation.
    nonisolated(unsafe) private(set) var landscapeLockedFlag = false

    private var lockTask: Task<Void, Never>?
    private var unlockTask: Task<Void, Never>?

    private init() {}

    func lockLandscape(delay: TimeInterval = 0) {
        lockTask?.cancel()
        unlockTask?.cancel()

        lockTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            guard !isLandscapeLocked else { return }
            isLandscapeLocked = true
            landscapeLockedFlag = true
            await requestLandscape()
        }
    }

    func unlockAll(delay: TimeInterval = 0) {
        lockTask?.cancel()
        unlockTask?.cancel()

        unlockTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            guard isLandscapeLocked else { return }
            isLandscapeLocked = false
            landscapeLockedFlag = false
            await requestPortrait()
        }
    }

    private func requestLandscape() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        await withCheckedContinuation { continuation in
            UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseInOut]) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
                for window in scene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            } completion: { _ in
                UIViewController.attemptRotationToDeviceOrientation()
                continuation.resume()
            }
        }
    }

    private func requestPortrait() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        await withCheckedContinuation { continuation in
            UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseInOut]) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
                for window in scene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            } completion: { _ in
                UIViewController.attemptRotationToDeviceOrientation()
                continuation.resume()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationManager.shared.landscapeLockedFlag ? .landscape : .allButUpsideDown
    }
}

enum AudioSessionConfigurator {
    static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }

    static func deactivatePlayback() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
