import UIKit
import AVFoundation

@MainActor
final class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    @Published private(set) var isLandscapeLocked = false

    /// Readable from AppDelegate without crossing actor isolation.
    nonisolated(unsafe) private(set) var landscapeLockedFlag = false

    private init() {}

    func lockLandscape() {
        guard !isLandscapeLocked else { return }
        isLandscapeLocked = true
        landscapeLockedFlag = true
        requestLandscape()
    }

    func unlockAll() {
        guard isLandscapeLocked else { return }
        isLandscapeLocked = false
        landscapeLockedFlag = false
        requestPortrait()
    }

    private func requestLandscape() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private func requestPortrait() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        UIViewController.attemptRotationToDeviceOrientation()
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
