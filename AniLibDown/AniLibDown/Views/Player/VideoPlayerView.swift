import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let session: PlayerSession

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var currentIndex: Int
    @State private var player: AVPlayer?
    @State private var showEpisodeList = false
    @State private var controlsVisible = true
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
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        toggleControls()
                    }
            } else {
                ProgressView("Подготовка плеера...")
                    .tint(.white)
            }

            if controlsVisible {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
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
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }

            HStack {
                episodeButton(systemName: "backward.fill", enabled: currentIndex > 0) {
                    switchToEpisode(at: currentIndex - 1)
                }
                Spacer()
                episodeButton(
                    systemName: "forward.fill",
                    enabled: currentIndex < session.episodes.count - 1
                ) {
                    switchToEpisode(at: currentIndex + 1)
                }
            }
            .padding(.horizontal, 8)
        }
        .allowsHitTesting(true)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                showEpisodeList = true
                revealControls()
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

    private var bottomBar: some View {
        VStack(spacing: 4) {
            Text(currentEpisode.displayTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("\(currentIndex + 1) / \(session.episodes.count)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 72)
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
    }

    private func toggleControls() {
        if controlsVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = false
            }
            hideControlsTask?.cancel()
        } else {
            revealControls()
        }
    }

    private func revealControls() {
        hideControlsTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controlsVisible = false
                }
            }
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
    }

    private func playbackURL(for episode: Episode) -> URL? {
        if session.preferOffline,
           let offline = downloadManager.localPlaybackURL(for: episode.id, quality: session.quality) {
            return offline
        }
        return session.quality.streamURL(for: episode)
    }
}
