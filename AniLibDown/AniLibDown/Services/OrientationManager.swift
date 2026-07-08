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

    func lockLandscape(delay: TimeInterval = 0, completion: (@MainActor () -> Void)? = nil) {
        lockTask?.cancel()
        unlockTask?.cancel()

        lockTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            guard !isLandscapeLocked else {
                completion?()
                return
            }
            isLandscapeLocked = true
            landscapeLockedFlag = true
            await requestLandscape()
            completion?()
        }
    }

    func unlockAll(delay: TimeInterval = 0, completion: (@MainActor () -> Void)? = nil) {
        lockTask?.cancel()
        unlockTask?.cancel()

        unlockTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            guard isLandscapeLocked else {
                completion?()
                return
            }
            isLandscapeLocked = false
            landscapeLockedFlag = false
            await requestPortrait()
            completion?()
        }
    }

    private func requestLandscape() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        UIViewController.attemptRotationToDeviceOrientation()
        try? await Task.sleep(nanoseconds: 550_000_000)
    }

    private func requestPortrait() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        UIViewController.attemptRotationToDeviceOrientation()
        try? await Task.sleep(nanoseconds: 400_000_000)
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
