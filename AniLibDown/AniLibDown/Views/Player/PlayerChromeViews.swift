import SwiftUI
import AVKit

// MARK: - Player layer

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var onLayerReady: ((AVPlayerLayer) -> Void)?

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.player = player
        DispatchQueue.main.async {
            onLayerReady?(view.playerLayer)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.player = player
        DispatchQueue.main.async {
            onLayerReady?(uiView.playerLayer)
        }
    }
}

// MARK: - Gesture overlay

final class PlayerGestureView: UIView {
    var onSingleTap: (() -> Void)?
    var onDoubleTapLeft: (() -> Void)?
    var onDoubleTapRight: (() -> Void)?
    var onLongPressRightBegan: (() -> Void)?
    var onLongPressRightEnded: (() -> Void)?

    private let leftZone = UIView()
    private let rightZone = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        [leftZone, rightZone].forEach {
            $0.backgroundColor = .clear
            $0.isUserInteractionEnabled = true
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            leftZone.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftZone.topAnchor.constraint(equalTo: topAnchor),
            leftZone.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftZone.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            rightZone.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightZone.topAnchor.constraint(equalTo: topAnchor),
            rightZone.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightZone.leadingAnchor.constraint(equalTo: leftZone.trailingAnchor)
        ])

        attachGestures(to: leftZone, doubleAction: #selector(handleDoubleTapLeft), longPress: false)
        attachGestures(to: rightZone, doubleAction: #selector(handleDoubleTapRight), longPress: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func attachGestures(to view: UIView, doubleAction: Selector, longPress: Bool) {
        let double = UITapGestureRecognizer(target: self, action: doubleAction)
        double.numberOfTapsRequired = 2

        let single = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        single.numberOfTapsRequired = 1
        single.require(toFail: double)

        view.addGestureRecognizer(double)
        view.addGestureRecognizer(single)

        if longPress {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressRight))
            press.minimumPressDuration = 0.25
            view.addGestureRecognizer(press)
        }
    }

    @objc private func handleSingleTap() { onSingleTap?() }
    @objc private func handleDoubleTapLeft() { onDoubleTapLeft?() }
    @objc private func handleDoubleTapRight() { onDoubleTapRight?() }

    @objc private func handleLongPressRight(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            onLongPressRightBegan?()
        case .ended, .cancelled, .failed:
            onLongPressRightEnded?()
        default:
            break
        }
    }
}

struct PlayerGestureOverlay: UIViewRepresentable {
    let onSingleTap: () -> Void
    let onDoubleTapLeft: () -> Void
    let onDoubleTapRight: () -> Void
    let onLongPressRightBegan: () -> Void
    let onLongPressRightEnded: () -> Void

    func makeUIView(context: Context) -> PlayerGestureView {
        let view = PlayerGestureView()
        syncCallbacks(to: view)
        return view
    }

    func updateUIView(_ uiView: PlayerGestureView, context: Context) {
        syncCallbacks(to: uiView)
    }

    private func syncCallbacks(to view: PlayerGestureView) {
        view.onSingleTap = onSingleTap
        view.onDoubleTapLeft = onDoubleTapLeft
        view.onDoubleTapRight = onDoubleTapRight
        view.onLongPressRightBegan = onLongPressRightBegan
        view.onLongPressRightEnded = onLongPressRightEnded
    }
}

