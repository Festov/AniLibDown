import SwiftUI
import AVKit

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
        [leftZone, rightZone].forEach {
            $0.backgroundColor = .clear
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
        let single = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        let double = UITapGestureRecognizer(target: self, action: doubleAction)
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        view.addGestureRecognizer(single)
        view.addGestureRecognizer(double)
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

// MARK: - Video player

struct VideoPlayerView: View {
    let session: PlayerSession

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var currentIndex: Int
    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var showEpisodeList = false
    @State private var controlsVisible = true
    @State private var seekHint: String?
    @State private var hideControlsTask: Task<Void, Never>?

    init(session: PlayerSession) {
        self.session = session
        _currentIndex = State(initialValue: session.startIndex)
    }

    private var currentEpisode: Episode {
        session.episodes[currentIndex]
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

            if !controlsVisible {
                PlayerGestureOverlay(
                    onSingleTap: { revealControls() },
                    onDoubleTapLeft: { seek(by: -5) },
                    onDoubleTapRight: { seek(by: 5) }
                )
                .ignoresSafeArea()
            }

            if controlsVisible {
                controlsOverlay
                    .transition(.opacity)
            }

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
        .animation(.easeInOut(duration: 0.2), value: seekHint)
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
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
            player?.pause()
            player = nil
            AudioSessionConfigurator.deactivatePlayback()
            OrientationManager.shared.unlockAll()
        }
    }

    private var controlsOverlay: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerControls
                Spacer()
                bottomBar
            }
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
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
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
        VStack(spacing: 4) {
            Text(currentEpisode.displayTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("\(currentIndex + 1) / \(session.episodes.count)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            Text("Двойной тап слева/справа — ±5 сек")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
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
        if controlsVisible {
            withAnimation { controlsVisible = false }
            hideControlsTask?.cancel()
        } else {
            revealControls()
        }
    }

    private func revealControls() {
        hideControlsTask?.cancel()
        withAnimation { controlsVisible = true }
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation { controlsVisible = false }
            }
        }
    }

    private func togglePlayPause() {
        guard let player else { return }
        if player.rate > 0 {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func seek(by seconds: Double) {
        guard let player, let item = player.currentItem else { return }

        let current = player.currentTime()
        let duration = item.duration
        var target = CMTimeAdd(current, CMTime(seconds: seconds, preferredTimescale: 600))

        if duration.isNumeric {
            target = min(max(target, .zero), duration)
        } else {
            target = max(target, .zero)
        }

        player.seek(to: target)
        seekHint = seconds > 0 ? "+5 сек" : "-5 сек"
        revealControls()

        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run { seekHint = nil }
        }
    }

    private func switchToEpisode(at index: Int) {
        guard session.episodes.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        loadEpisode(at: index)
    }

    private func loadEpisode(at index: Int) {
        let episode = session.episodes[index]
        guard let url = playbackURL(for: episode) else { return }

        player?.pause()
        let item = AVPlayerItem(url: url)
        if let player {
            player.replaceCurrentItem(with: item)
            player.play()
        } else {
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            newPlayer.play()
        }
        isPlaying = true
    }

    private func playbackURL(for episode: Episode) -> URL? {
        if session.preferOffline,
           let offline = downloadManager.localPlaybackURL(for: episode.id, quality: session.quality) {
            return offline
        }
        return session.quality.streamURL(for: episode)
    }
}
