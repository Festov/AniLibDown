import SwiftUI
import AVKit

// MARK: - Video player

struct VideoPlayerView: View {
    let session: PlayerSession

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadManager: DownloadManager
    @ObservedObject private var playerSettings = PlayerSettings.shared
    @StateObject private var pipController = PlayerPiPController()
    @StateObject private var progress = PlaybackProgress()
    @StateObject private var skipController = PlayerSkipController()

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
    @State private var playerOpacity: Double = 0
    @State private var isOrientationTransitioning = true
    @State private var progressSaveTask: Task<Void, Never>?
    @State private var didTriggerAutoNext = false
    @State private var endPlaybackObserver: NSObjectProtocol?
    @State private var subtitleOptions: [AVMediaSelectionOption] = []
    @State private var selectedSubtitleOption: AVMediaSelectionOption?
    @State private var didSyncShikimoriEpisode = false

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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                PlayerLayerView(player: player) { layer in
                    pipController.attach(to: layer)
                }
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

            if skipController.prompt != nil {
                PlayerSkipPromptOverlay(
                    promptProgress: skipController.promptProgress,
                    isControlsVisible: controlsVisible,
                    onDecline: { skipController.decline() },
                    onInteraction: { scheduleHideControls() }
                )
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
                        .font(.caption.weight(.semibold))
                        .imageScale(.small)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        .padding(.top, 64)
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
        .animation(playerOverlayAnimation, value: controlsVisible)
        .animation(playerOverlayAnimation, value: showEpisodeList)
        .animation(playerOverlayAnimation, value: seekHint)
        .animation(playerOverlayAnimation, value: isFastForwarding)
        .animation(playerOverlayAnimation, value: skipController.prompt)
        .animation(playerOverlayAnimation, value: isOrientationTransitioning)
        .sheet(isPresented: $showSettings) {
            PlayerSettingsSheet(
                currentQuality: $currentQuality,
                availableQualities: availableQualities,
                subtitleOptions: subtitleOptions,
                selectedSubtitleOption: $selectedSubtitleOption,
                onQualityChange: { quality in
                    switchQuality(to: quality)
                },
                onSubtitleChange: applySubtitleOption
            )
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            AudioSessionConfigurator.activatePlayback()
            skipController.onSkip = { endTime in
                seek(to: endTime)
            }
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
            skipController.cancelPrompt()
            skipController.onSkip = nil
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
            skipController.reset()
        }
    }

    // MARK: - Chrome composition

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            PlayerTopBar(
                releaseTitle: session.releaseTitle,
                episodeTitle: currentEpisode.playerEpisodeTitle,
                episodeNumber: currentIndex + 1,
                totalEpisodes: session.totalEpisodes,
                qualityTitle: currentQuality.rawValue,
                isEpisodeListVisible: showEpisodeList,
                showsPictureInPicture: AVPictureInPictureController.isPictureInPictureSupported(),
                isPictureInPictureActive: pipController.isPictureInPictureActive,
                showsAirPlay: player != nil,
                onToggleEpisodeList: {
                    withAnimation(playerOverlayAnimation) {
                        showEpisodeList.toggle()
                    }
                },
                onOpenSettings: { showSettings = true },
                onTogglePictureInPicture: { pipController.togglePictureInPicture() },
                onClose: { closePlayer() },
                onInteraction: { scheduleHideControls() }
            )
            Spacer().allowsHitTesting(false)
            PlayerCenterControls(
                isPlaying: progress.isPlaying,
                hasPrevious: currentIndex > 0,
                hasNext: currentIndex < session.episodes.count - 1,
                onPrevious: { switchToEpisode(at: currentIndex - 1) },
                onNext: { switchToEpisode(at: currentIndex + 1) },
                onPlayPause: { togglePlayPause() },
                onInteraction: { scheduleHideControls() }
            )
            Spacer().allowsHitTesting(false)
            PlayerBottomBar(
                displayedTime: displayedTime,
                duration: progress.duration,
                showsRemainingTime: showRemainingTime,
                onScrubChanged: { scrubTime = $0 },
                onScrubEditingChanged: handleScrubEditingChange,
                onToggleTimeMode: { showRemainingTime.toggle() },
                onInteraction: { scheduleHideControls() }
            )
        }
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

                    PlayerEpisodeListContent(
                        episodes: session.episodes,
                        currentIndex: currentIndex,
                        onSelect: { switchToEpisode(at: $0) },
                        onClose: { closeEpisodeList() },
                        onInteraction: { scheduleHideControls() }
                    )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                .zIndex(20)
            }
        }
    }

    private func closeEpisodeList() {
        withAnimation(playerOverlayAnimation) {
            showEpisodeList = false
        }
    }

    // MARK: - Chrome behaviour

    private func toggleControls() {
        hideControlsTask?.cancel()
        withAnimation(playerOverlayAnimation) {
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
                withAnimation(playerOverlayAnimation) {
                    controlsVisible = false
                }
            }
        }
    }

    private func handleScrubEditingChange(_ editing: Bool) {
        isScrubbing = editing
        if editing {
            hideControlsTask?.cancel()
            scrubTime = progress.currentTime
        } else {
            seek(to: scrubTime)
            scheduleHideControls()
        }
    }

    // MARK: - Playback

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
        hideControlsTask?.cancel()
        // Only the speed badge should show — keep player chrome hidden.
        withAnimation(playerOverlayAnimation) { controlsVisible = false }
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
                withAnimation(playerOverlayAnimation) {
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
        guard let resolved = resolvePlayback(for: episode) else {
            ToastCenter.shared.show("Нет доступного видео для этой серии", isError: true)
            return
        }
        let url = resolved.url
        if resolved.quality != currentQuality {
            currentQuality = resolved.quality
        }

        if let player {
            progress.detach(from: player)
        }
        progress.reset()
        skipController.reset()
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
            player.allowsExternalPlayback = true
            player.replaceCurrentItem(with: item)
            progress.observe(player: player) { isScrubbing }
            configureTimeObserver(for: player, episode: episode)
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
            newPlayer.allowsExternalPlayback = true
            newPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
            player = newPlayer
            progress.observe(player: newPlayer) { isScrubbing }
            configureTimeObserver(for: newPlayer, episode: episode)
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
        loadSubtitleOptions(for: item)
        didSyncShikimoriEpisode = false
        scheduleProgressSaving()
    }

    private func loadSubtitleOptions(for item: AVPlayerItem) {
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else {
                await MainActor.run {
                    subtitleOptions = []
                    selectedSubtitleOption = nil
                }
                return
            }
            let options = group.options
            await MainActor.run {
                subtitleOptions = options
                selectedSubtitleOption = item.currentMediaSelection.selectedMediaOption(in: group)
            }
        }
    }

    private func applySubtitleOption(_ option: AVMediaSelectionOption?) {
        guard let player, let item = player.currentItem else { return }
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            await MainActor.run {
                item.select(option, in: group)
                selectedSubtitleOption = option
            }
        }
    }

    private func configureTimeObserver(for player: AVPlayer, episode: Episode) {
        progress.onTimeUpdate = { [self] time in
            skipController.handle(time: time, episode: episode, duration: progress.duration)
            maybeAutoPlayNext(at: time, player: player)
        }
    }

    private func maybeAutoPlayNext(at time: Double, player: AVPlayer) {
        guard playerSettings.autoPlayNext, !didTriggerAutoNext else { return }
        guard progress.duration > 0, time >= progress.duration - 1 else { return }
        guard currentIndex < session.episodes.count - 1 else { return }
        didTriggerAutoNext = true
        switchToEpisode(at: currentIndex + 1)
    }

    private func resolvePlayback(for episode: Episode) -> (url: URL, quality: VideoQuality)? {
        if session.preferOffline,
           let offline = downloadManager.anyLocalPlaybackURL(for: episode.id, preferred: currentQuality) {
            return offline
        }
        if let offline = downloadManager.localPlaybackURL(for: episode.id, quality: currentQuality) {
            return (offline, currentQuality)
        }
        if let online = currentQuality.streamURL(for: episode) {
            return (online, currentQuality)
        }
        if let fallback = episode.availableStreamQualities().first,
           let online = fallback.streamURL(for: episode) {
            return (online, fallback)
        }
        return downloadManager.anyLocalPlaybackURL(for: episode.id, preferred: currentQuality)
    }

    // MARK: - Persistence

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
            syncShikimoriEpisodeIfNeeded()
        } else {
            guard session.releaseId > 0 else { return }
            WatchProgressStore.shared.save(
                position: progress.currentTime,
                episodeId: currentEpisode.id,
                releaseId: session.releaseId,
                releaseTitle: session.releaseTitle,
                posterPath: session.posterPath,
                episodeTitle: currentEpisode.displayTitle,
                duration: currentEpisode.duration
            )
        }
    }

    private func syncShikimoriEpisodeIfNeeded() {
        guard !didSyncShikimoriEpisode,
              session.releaseId > 0,
              ShikimoriAuthService.shared.isAuthenticated,
              let link = ShikimoriLinkStore.shared.link(for: session.releaseId) else { return }
        didSyncShikimoriEpisode = true
        Task {
            await ShikimoriAuthService.shared.syncEpisodeCount(
                animeId: link.animeId,
                episodeOrdinal: Int(currentEpisode.ordinal.rounded(.towardZero))
            )
        }
    }
}