import SwiftUI
import AVKit

private let controlsAnimation = Animation.easeInOut(duration: 0.35)

// MARK: - Player layer

private final class PlayerContainerView: UIView {
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

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.player = player
    }
}

// MARK: - Gesture overlay

private final class PlayerGestureView: UIView {
    var onSingleTap: (() -> Void)?
    var onDoubleTapLeft: (() -> Void)?
    var onDoubleTapRight: (() -> Void)?

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

        attachGestures(to: leftZone, doubleAction: #selector(handleDoubleTapLeft))
        attachGestures(to: rightZone, doubleAction: #selector(handleDoubleTapRight))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func attachGestures(to view: UIView, doubleAction: Selector) {
        let double = UITapGestureRecognizer(target: self, action: doubleAction)
        double.numberOfTapsRequired = 2

        let single = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        single.numberOfTapsRequired = 1
        single.require(toFail: double)

        view.addGestureRecognizer(double)
        view.addGestureRecognizer(single)
    }

    @objc private func handleSingleTap() { onSingleTap?() }
    @objc private func handleDoubleTapLeft() { onDoubleTapLeft?() }
    @objc private func handleDoubleTapRight() { onDoubleTapRight?() }
}

private struct PlayerGestureOverlay: UIViewRepresentable {
    let onSingleTap: () -> Void
    let onDoubleTapLeft: () -> Void
    let onDoubleTapRight: () -> Void

    func makeUIView(context: Context) -> PlayerGestureView {
        let view = PlayerGestureView()
        view.onSingleTap = onSingleTap
        view.onDoubleTapLeft = onDoubleTapLeft
        view.onDoubleTapRight = onDoubleTapRight
        return view
    }

    func updateUIView(_ uiView: PlayerGestureView, context: Context) {
        uiView.onSingleTap = onSingleTap
        uiView.onDoubleTapLeft = onDoubleTapLeft
        uiView.onDoubleTapRight = onDoubleTapRight
    }
}

// MARK: - Playback progress

@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false

    private var observer: Any?

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
    }

    func reset() {
        currentTime = 0
        duration = 0
        isPlaying = false
    }
}

// MARK: - Video player

struct VideoPlayerView: View {
    let session: PlayerSession

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadManager: DownloadManager

    @StateObject private var progress = PlaybackProgress()
    @State private var currentIndex: Int
    @State private var player: AVPlayer?
    @State private var showEpisodeList = false
    @State private var controlsVisible = true
    @State private var seekHint: String?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false

    init(session: PlayerSession) {
        self.session = session
        _currentIndex = State(initialValue: session.startIndex)
    }

    private var currentEpisode: Episode {
        session.episodes[currentIndex]
    }

    private var displayedTime: Double {
        isScrubbing ? scrubTime : progress.currentTime
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView("Подготовка плеера...")
                    .tint(.white)
            }

            PlayerGestureOverlay(
                onSingleTap: { toggleControls() },
                onDoubleTapLeft: { seek(by: -5) },
                onDoubleTapRight: { seek(by: 5) }
            )
            .ignoresSafeArea()

            controlsOverlay
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)

            if let seekHint {
                Text(seekHint)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
                    .transition(.opacity)
            }
        }
        .animation(controlsAnimation, value: controlsVisible)
        .animation(.easeInOut(duration: 0.2), value: seekHint)
        .confirmationDialog("Выбор серии", isPresented: $showEpisodeList, titleVisibility: .visible) {
            ForEach(Array(session.episodes.enumerated()), id: \.element.id) { index, episode in
                Button(episode.displayTitle) {
                    switchToEpisode(at: index)
                    scheduleHideControls()
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear {
            OrientationManager.shared.lockLandscape()
            AudioSessionConfigurator.activatePlayback()
            loadEpisode(at: currentIndex)
            scheduleHideControls()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            if let player {
                progress.detach(from: player)
            }
            player?.pause()
            player = nil
            AudioSessionConfigurator.deactivatePlayback()
            OrientationManager.shared.unlockAll()
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer().allowsHitTesting(false)
            centerControls
            Spacer().allowsHitTesting(false)
            bottomBar
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                showEpisodeList = true
                scheduleHideControls()
            } label: {
                Label("Серии", systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }

            Text(session.releaseTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)

            Button("Закрыть") { dismiss() }
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.75), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var centerControls: some View {
        HStack(spacing: 48) {
            episodeButton(systemName: "backward.fill", enabled: currentIndex > 0) {
                switchToEpisode(at: currentIndex - 1)
            }

            Button {
                togglePlayPause()
                scheduleHideControls()
            } label: {
                Image(systemName: progress.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            episodeButton(systemName: "forward.fill", enabled: currentIndex < session.episodes.count - 1) {
                switchToEpisode(at: currentIndex + 1)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(formatTime(displayedTime))
                    .font(.caption.monospacedDigit())
                    .frame(width: 48, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { min(displayedTime, max(progress.duration, 0.1)) },
                        set: { scrubTime = $0 }
                    ),
                    in: 0...max(progress.duration, 0.1),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if editing {
                            hideControlsTask?.cancel()
                            scrubTime = progress.currentTime
                        } else {
                            seek(to: scrubTime)
                            scheduleHideControls()
                        }
                    }
                )
                .tint(.white)

                Text(formatTime(progress.duration))
                    .font(.caption.monospacedDigit())
                    .frame(width: 48, alignment: .trailing)
            }

            Text(currentEpisode.displayTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .allowsHitTesting(false)

            Text("\(currentIndex + 1) / \(session.episodes.count) • двойной тап слева/справа ±5 сек")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .allowsHitTesting(false)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func episodeButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            scheduleHideControls()
        }) {
            Image(systemName: systemName)
                .font(.title)
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.45))
                .clipShape(Circle())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func toggleControls() {
        hideControlsTask?.cancel()
        withAnimation(controlsAnimation) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(controlsAnimation) {
                    controlsVisible = false
                }
            }
        }
    }

    private func togglePlayPause() {
        guard let player else { return }
        if player.rate > 0 {
            player.pause()
            progress.isPlaying = false
        } else {
            player.play()
            progress.isPlaying = true
        }
    }

    private func seek(by seconds: Double) {
        seek(to: max(0, progress.currentTime + seconds))
        seekHint = seconds > 0 ? "+5 сек" : "-5 сек"

        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run { seekHint = nil }
        }
    }

    private func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = min(max(seconds, 0), max(progress.duration, 0))
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: target)
        progress.currentTime = clamped
        scrubTime = clamped
    }

    private func switchToEpisode(at index: Int) {
        guard session.episodes.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        loadEpisode(at: index)
    }

    private func loadEpisode(at index: Int) {
        let episode = session.episodes[index]
        guard let url = playbackURL(for: episode) else { return }

        if let player {
            progress.detach(from: player)
        }
        progress.reset()

        player?.pause()
        let item = AVPlayerItem(url: url)
        if let player {
            player.replaceCurrentItem(with: item)
            player.play()
            progress.observe(player: player) { isScrubbing }
        } else {
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            newPlayer.play()
            progress.observe(player: newPlayer) { isScrubbing }
        }
        progress.isPlaying = true
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func playbackURL(for episode: Episode) -> URL? {
        if session.preferOffline,
           let offline = downloadManager.localPlaybackURL(for: episode.id, quality: session.quality) {
            return offline
        }
        return session.quality.streamURL(for: episode)
    }
}
