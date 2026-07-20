import SwiftUI
import AVKit

private let overlayAnimation = Animation.easeInOut(duration: 0.35)

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

private struct PlayerGestureOverlay: UIViewRepresentable {
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

// MARK: - Playback progress

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

// MARK: - Skip prompt

private struct SkipPrompt: Identifiable, Equatable {
    let id: String
    let title: String
    let endTime: Double
}

// MARK: - Video player

struct VideoPlayerView: View {
    let session: PlayerSession

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadManager: DownloadManager
    @ObservedObject private var playerSettings = PlayerSettings.shared

    @StateObject private var progress = PlaybackProgress()
    @State private var currentIndex: Int
    @State private var currentQuality: VideoQuality
    @State private var player: AVPlayer?
    @State private var showEpisodeList = false
    @State private var showSettings = false
    @State private var controlsVisible = true
    @State private var seekHint: String?
    @State private var seekAccumulator: Double = 0
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var seekAccumTask: Task<Void, Never>?
    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false
    @State private var showRemainingTime = false
    @State private var isFastForwarding = false
    @State private var normalPlaybackRate: Float = 1
    @State private var lastSkippedSegment: String?
    @State private var playerOpacity: Double = 0
    @State private var isOrientationTransitioning = true
    @State private var progressSaveTask: Task<Void, Never>?
    @State private var didTriggerAutoNext = false
    @State private var endPlaybackObserver: NSObjectProtocol?
    @State private var skipPrompt: SkipPrompt?
    @State private var skipPromptProgress: CGFloat = 0
    @State private var skipPromptTask: Task<Void, Never>?
    @State private var declinedSkipSegments: Set<String> = []

    init(session: PlayerSession) {
        self.session = session
        _currentIndex = State(initialValue: session.startIndex)
        _currentQuality = State(initialValue: session.quality)
    }

    private var currentEpisode: Episode {
        session.episodes[currentIndex]
    }

    private var availableQualities: [VideoQuality] {
        VideoQuality.allCases.filter { quality in
            if session.preferOffline,
               downloadManager.isDownloaded(episodeId: currentEpisode.id, quality: quality) {
                return true
            }
            return quality.streamURL(for: currentEpisode) != nil
        }
    }

    private var displayedTime: Double {
        isScrubbing ? scrubTime : progress.currentTime
    }

    private var trailingTimeLabel: String {
        if showRemainingTime {
            let remaining = max(progress.duration - displayedTime, 0)
            return "-\(formatTime(remaining))"
        }
        return formatTime(progress.duration)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()
                    .opacity(playerOpacity)
            } else {
                ProgressView("Подготовка плеера...")
                    .tint(.white)
            }

            PlayerGestureOverlay(
                onSingleTap: { toggleControls() },
                onDoubleTapLeft: { seek(by: -playerSettings.seekInterval.seconds) },
                onDoubleTapRight: { seek(by: playerSettings.seekInterval.seconds) },
                onLongPressRightBegan: { beginFastForward() },
                onLongPressRightEnded: { endFastForward() }
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            controlsOverlay
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)

            if skipPrompt != nil {
                skipPromptOverlay
                    .zIndex(25)
            }

            episodeListPanel

            if let seekHint {
                Text(seekHint)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
                    .transition(.opacity.combined(with: .scale))
            }

            if isFastForwarding {
                VStack {
                    Label(playerSettings.holdSpeedRate.title, systemImage: "forward.fill")
                        .font(.title2.weight(.bold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                        .padding(.top, 72)
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale))
                .allowsHitTesting(false)
            }

            if isOrientationTransitioning {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(50)
            }
        }
        .animation(overlayAnimation, value: controlsVisible)
        .animation(overlayAnimation, value: showEpisodeList)
        .animation(overlayAnimation, value: seekHint)
        .animation(overlayAnimation, value: isFastForwarding)
        .animation(overlayAnimation, value: skipPrompt)
        .animation(overlayAnimation, value: isOrientationTransitioning)
        .sheet(isPresented: $showSettings) {
            PlayerSettingsSheet(
                currentQuality: $currentQuality,
                availableQualities: availableQualities
            ) { quality in
                switchQuality(to: quality)
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            AudioSessionConfigurator.activatePlayback()
            isOrientationTransitioning = true
            playerOpacity = 0
            loadEpisode(at: currentIndex)
            scheduleHideControls()

            OrientationManager.shared.lockLandscape(delay: 0.1) {
                withAnimation(.easeInOut(duration: 0.55)) {
                    isOrientationTransitioning = false
                    playerOpacity = 1
                }
            }
        }
        .onDisappear {
            saveWatchProgress()
            hideControlsTask?.cancel()
            seekAccumTask?.cancel()
            skipPromptTask?.cancel()
            progressSaveTask?.cancel()
            endPlaybackObserver.map(NotificationCenter.default.removeObserver)
            endPlaybackObserver = nil
            if let player {
                progress.detach(from: player)
            }
            player?.pause()
            player = nil
            AudioSessionConfigurator.deactivatePlayback()
            OrientationManager.shared.unlockAll(delay: 0.2)
        }
        .onChange(of: currentIndex) { _, _ in
            resetSkipState()
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
                withAnimation(overlayAnimation) {
                    showEpisodeList.toggle()
                }
                scheduleHideControls()
            } label: {
                Label("Серии", systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(showEpisodeList ? "Скрыть список серий" : "Список серий")

            VStack(spacing: 2) {
                Text(session.releaseTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text(currentEpisode.playerEpisodeTitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Text(" (\(currentIndex + 1)/\(session.totalEpisodes))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(session.releaseTitle), \(currentEpisode.playerEpisodeTitle), серия \(currentIndex + 1) из \(session.totalEpisodes), \(currentQuality.rawValue)")

            Button {
                showSettings = true
                scheduleHideControls()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Настройки плеера")

            Button("Закрыть") { closePlayer() }
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel("Закрыть плеер")
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
            episodeButton(
                systemName: "backward.fill",
                enabled: currentIndex > 0,
                accessibilityLabel: "Предыдущая серия"
            ) {
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
            .accessibilityLabel(progress.isPlaying ? "Пауза" : "Воспроизведение")

            episodeButton(
                systemName: "forward.fill",
                enabled: currentIndex < session.episodes.count - 1,
                accessibilityLabel: "Следующая серия"
            ) {
                switchToEpisode(at: currentIndex + 1)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(formatTime(displayedTime))
                    .font(.caption.monospacedDigit())
                    .frame(width: 52, alignment: .leading)

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
                .accessibilityLabel("Позиция воспроизведения")
                .accessibilityValue(formatTime(displayedTime))

                Button {
                    showRemainingTime.toggle()
                    scheduleHideControls()
                } label: {
                    Text(trailingTimeLabel)
                        .font(.caption.monospacedDigit())
                        .frame(width: 52, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showRemainingTime ? "Оставшееся время" : "Длительность")
                .accessibilityHint("Переключить отображение времени")
            }
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

    private var skipPromptOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                skipDeclineButton
            }
            .padding(.trailing, 16)
            .padding(.bottom, controlsVisible ? 72 : 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var skipDeclineButton: some View {
        Button {
            declineSkip()
            scheduleHideControls()
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))

                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.9))
                        .frame(width: max(geometry.size.width * skipPromptProgress, 0))
                }

                Text("Не пропускать")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .frame(width: 196, height: 44)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Не пропускать")
        .accessibilityHint("Отменить автопропуск опенинга или эндинга")
    }

    private var episodeListPanel: some View {
        Group {
            if showEpisodeList {
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeEpisodeList()
                        }
                        .transition(.opacity)

                    episodeListContent
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                .zIndex(20)
            }
        }
    }

    private var episodeListContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Серии")
                    .font(.headline)
                Spacer()
                Button {
                    closeEpisodeList()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
            }
            .foregroundStyle(.white)
            .padding()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(session.episodes.enumerated()), id: \.element.id) { index, episode in
                        Button {
                            switchToEpisode(at: index)
                            closeEpisodeList()
                            scheduleHideControls()
                        } label: {
                            HStack {
                                Text(episode.displayTitle)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if index == currentIndex {
                                    Image(systemName: "play.fill")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(index == currentIndex ? Color.accentColor : .white)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }
                        .accessibilityLabel(index == currentIndex ? "\(episode.displayTitle), сейчас играет" : episode.displayTitle)
                        Divider().overlay(.white.opacity(0.15))
                    }
                }
            }
        }
        .frame(width: min(320, UIScreen.main.bounds.width * 0.42))
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.92))
    }

    private func closeEpisodeList() {
        withAnimation(overlayAnimation) {
            showEpisodeList = false
        }
    }

    private func episodeButton(
        systemName: String,
        enabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
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
        .accessibilityLabel(accessibilityLabel)
    }

    private func toggleControls() {
        hideControlsTask?.cancel()
        withAnimation(overlayAnimation) {
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
                withAnimation(overlayAnimation) {
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
            player.rate = normalPlaybackRate
            player.play()
            progress.isPlaying = true
        }
    }

    private func beginFastForward() {
        guard let player, !isFastForwarding else { return }
        normalPlaybackRate = player.rate > 0 ? player.rate : 1
        isFastForwarding = true
        player.rate = playerSettings.holdSpeedRate.rawValue
        progress.isPlaying = true
        withAnimation(overlayAnimation) { controlsVisible = true }
    }

    private func endFastForward() {
        guard let player, isFastForwarding else { return }
        isFastForwarding = false
        player.rate = normalPlaybackRate
        if normalPlaybackRate > 0 {
            player.play()
            progress.isPlaying = true
        }
    }

    private func seek(by seconds: Double) {
        let step = playerSettings.seekInterval.seconds
        let signedStep = seconds > 0 ? step : -step
        seekAccumulator += signedStep
        seek(to: max(0, progress.currentTime + signedStep))

        let prefix = seekAccumulator > 0 ? "+" : ""
        seekHint = "\(prefix)\(Int(seekAccumulator)) сек"

        seekAccumTask?.cancel()
        seekAccumTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(overlayAnimation) {
                    seekHint = nil
                    seekAccumulator = 0
                }
            }
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

    private func restorePlaybackPosition(_ seconds: Double, on player: AVPlayer, force: Bool = false) {
        guard force || seconds > 5 else { return }

        let performSeek = {
            let duration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)
            let clamped = duration.isFinite && duration > 0 ? min(seconds, duration) : seconds
            let target = CMTime(seconds: max(clamped, 0), preferredTimescale: 600)
            player.seek(to: target)
            if duration.isFinite, duration > 0 {
                progress.duration = duration
            }
            progress.currentTime = max(clamped, 0)
            scrubTime = max(clamped, 0)
        }

        let duration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)
        if duration.isFinite, duration > 0 {
            performSeek()
            return
        }

        Task { @MainActor in
            guard let item = player.currentItem else { return }

            let keys = ["duration", "playable"]
            do {
                try await item.asset.loadValues(forKeys: keys)
            } catch {
                return
            }

            guard player.currentItem === item else { return }
            performSeek()
        }
    }

    private func switchToEpisode(at index: Int) {
        guard session.episodes.indices.contains(index), index != currentIndex else { return }
        saveWatchProgress()
        currentIndex = index
        if let preferred = preferredQuality(for: session.episodes[index]) {
            currentQuality = preferred
        }
        loadEpisode(at: index)
    }

    private func switchQuality(to quality: VideoQuality) {
        guard quality != currentQuality else { return }
        guard availableQualities.contains(quality) || quality.streamURL(for: currentEpisode) != nil
                || downloadManager.isDownloaded(episodeId: currentEpisode.id, quality: quality) else {
            return
        }
        let savedTime = progress.currentTime
        let wasPlaying = progress.isPlaying
        saveWatchProgress()
        currentQuality = quality
        loadEpisode(at: currentIndex, seekTo: savedTime, autoPlay: wasPlaying)
    }

    private func preferredQuality(for episode: Episode) -> VideoQuality? {
        if session.preferOffline,
           downloadManager.isDownloaded(episodeId: episode.id, quality: currentQuality) {
            return currentQuality
        }
        if currentQuality.streamURL(for: episode) != nil {
            return currentQuality
        }
        return episode.availableStreamQualities().first
            ?? VideoQuality.allCases.first {
                downloadManager.isDownloaded(episodeId: episode.id, quality: $0)
            }
    }

    private func closePlayer() {
        OrientationManager.shared.unlockAll(delay: 0) {
            dismiss()
        }
    }

    private func loadEpisode(at index: Int, seekTo: Double? = nil, autoPlay: Bool = true) {
        let episode = session.episodes[index]
        guard let url = playbackURL(for: episode) else { return }

        if let player {
            progress.detach(from: player)
        }
        progress.reset()
        resetSkipState()
        didTriggerAutoNext = false

        let savedPosition = seekTo ?? (WatchProgressStore.shared.position(for: episode.id) ?? 0)

        player?.pause()
        let item = AVPlayerItem(url: url)
        endPlaybackObserver.map(NotificationCenter.default.removeObserver)
        endPlaybackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            guard playerSettings.autoPlayNext,
                  !didTriggerAutoNext,
                  currentIndex < session.episodes.count - 1 else {
                return
            }
            didTriggerAutoNext = true
            switchToEpisode(at: currentIndex + 1)
        }

        if let player {
            player.replaceCurrentItem(with: item)
            progress.observe(player: player) { isScrubbing }
            configureSkipObserver(for: player, episode: episode)
            if savedPosition > 5 || seekTo != nil {
                restorePlaybackPosition(max(savedPosition, 0), on: player, force: seekTo != nil)
            }
            if autoPlay {
                player.rate = normalPlaybackRate
                player.play()
                progress.isPlaying = true
            } else {
                player.pause()
                progress.isPlaying = false
            }
        } else {
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            progress.observe(player: newPlayer) { isScrubbing }
            configureSkipObserver(for: newPlayer, episode: episode)
            if savedPosition > 5 || seekTo != nil {
                restorePlaybackPosition(max(savedPosition, 0), on: newPlayer, force: seekTo != nil)
            }
            if autoPlay {
                newPlayer.play()
                progress.isPlaying = true
            } else {
                newPlayer.pause()
                progress.isPlaying = false
            }
        }
        scheduleProgressSaving()
    }

    private func configureSkipObserver(for player: AVPlayer, episode: Episode) {
        progress.onTimeUpdate = { [self] time in
            if playerSettings.skipOPED {
                handleSkipSegments(at: time, episode: episode)
            } else {
                cancelSkipPrompt()
            }
            maybeAutoPlayNext(at: time, player: player)
        }
    }

    private func resetSkipState() {
        lastSkippedSegment = nil
        declinedSkipSegments = []
        cancelSkipPrompt()
    }

    private func cancelSkipPrompt() {
        skipPromptTask?.cancel()
        skipPromptProgress = 0
        skipPrompt = nil
    }

    private func segmentBounds(
        for key: String,
        skip: EpisodeSkip?,
        duration: Double
    ) -> (start: Double, end: Double)? {
        guard let skip else { return nil }

        let start = Double(skip.start ?? 0)
        let end: Double

        if let stop = skip.stop {
            end = Double(stop)
        } else if key == "ending", duration > 0 {
            end = duration
        } else {
            return nil
        }

        let segmentDuration = end - start
        guard segmentDuration > 0 else { return nil }

        if key == "opening" && segmentDuration > 300 {
            return nil
        }

        if key == "ending" && duration > 0 && start < duration * 0.4 {
            return nil
        }

        return (start, end)
    }

    private func handleSkipSegments(at time: Double, episode: Episode) {
        if let prompt = skipPrompt {
            let stillInside = isInsideSegment(time: time, episode: episode, segmentKey: prompt.id)
            if !stillInside {
                cancelSkipPrompt()
            }
            return
        }

        let segments: [(key: String, title: String, skip: EpisodeSkip?)] = [
            ("opening", "Опенинг", episode.opening),
            ("ending", "Эндинг", episode.ending)
        ]

        for (key, title, skip) in segments {
            guard let bounds = segmentBounds(for: key, skip: skip, duration: progress.duration) else { continue }

            let segmentKey = "\(episode.id)-\(key)"
            if declinedSkipSegments.contains(segmentKey) { continue }
            if lastSkippedSegment == segmentKey { continue }

            guard time >= bounds.start, time < bounds.end else { continue }
            presentSkipPrompt(segmentKey: segmentKey, title: title, endTime: bounds.end)
            return
        }
    }

    private func isInsideSegment(time: Double, episode: Episode, segmentKey: String) -> Bool {
        let segments: [(key: String, skip: EpisodeSkip?)] = [
            ("opening", episode.opening),
            ("ending", episode.ending)
        ]

        for (key, skip) in segments {
            let currentKey = "\(episode.id)-\(key)"
            guard currentKey == segmentKey else { continue }
            guard let bounds = segmentBounds(for: key, skip: skip, duration: progress.duration) else {
                return false
            }
            return time >= bounds.start && time < bounds.end
        }
        return false
    }

    private func presentSkipPrompt(segmentKey: String, title: String, endTime: Double) {
        skipPromptTask?.cancel()
        skipPromptProgress = 0
        withAnimation(overlayAnimation) {
            skipPrompt = SkipPrompt(id: segmentKey, title: title, endTime: endTime)
        }

        withAnimation(.linear(duration: 3)) {
            skipPromptProgress = 1
        }

        skipPromptTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard skipPrompt?.id == segmentKey else { return }
                performSkip(to: endTime, segmentKey: segmentKey)
            }
        }
    }

    private func declineSkip() {
        guard let prompt = skipPrompt else { return }
        skipPromptTask?.cancel()
        declinedSkipSegments.insert(prompt.id)
        withAnimation(overlayAnimation) {
            skipPromptProgress = 0
            skipPrompt = nil
        }
    }

    private func performSkip(to endTime: Double, segmentKey: String) {
        lastSkippedSegment = segmentKey
        withAnimation(overlayAnimation) {
            skipPromptProgress = 0
            skipPrompt = nil
        }
        seek(to: endTime)
    }

    private func maybeAutoPlayNext(at time: Double, player: AVPlayer) {
        guard playerSettings.autoPlayNext, !didTriggerAutoNext else { return }
        guard progress.duration > 0, time >= progress.duration - 1 else { return }
        guard currentIndex < session.episodes.count - 1 else { return }
        didTriggerAutoNext = true
        switchToEpisode(at: currentIndex + 1)
    }

    private func scheduleProgressSaving() {
        progressSaveTask?.cancel()
        progressSaveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { saveWatchProgress() }
            }
        }
    }

    private func saveWatchProgress() {
        guard progress.currentTime > 0 else { return }
        let nearEnd = progress.duration > 0 && progress.currentTime >= progress.duration - 10
        if nearEnd {
            WatchProgressStore.shared.clearPosition(for: currentEpisode.id)
        } else {
            WatchProgressStore.shared.save(
                position: progress.currentTime,
                episodeId: currentEpisode.id,
                releaseId: session.releaseId
            )
        }
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
        if let offline = downloadManager.localPlaybackURL(for: episode.id, quality: currentQuality) {
            return offline
        }
        return currentQuality.streamURL(for: episode)
    }
}

// MARK: - Player settings sheet

private struct PlayerSettingsSheet: View {
    @Binding var currentQuality: VideoQuality
    let availableQualities: [VideoQuality]
    let onQualityChange: (VideoQuality) -> Void

    @ObservedObject private var settings = PlayerSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !availableQualities.isEmpty {
                        Picker(
                            "Качество",
                            selection: Binding(
                                get: { currentQuality },
                                set: { onQualityChange($0) }
                            )
                        ) {
                            ForEach(availableQualities) { quality in
                                Text(quality.rawValue).tag(quality)
                            }
                        }
                        .accessibilityLabel("Качество видео")
                    }

                    Picker("Шаг перемотки", selection: $settings.seekInterval) {
                        ForEach(SeekInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }

                    Toggle("Пропуск опенинга и эндинга", isOn: $settings.skipOPED)
                    Toggle("Автозапуск следующей серии", isOn: $settings.autoPlayNext)

                    Picker("Ускорение при удержании", selection: $settings.holdSpeedRate) {
                        ForEach(HoldSpeedRate.allCases) { rate in
                            Text(rate.title).tag(rate)
                        }
                    }
                }
            }
            .navigationTitle("Настройки плеера")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
