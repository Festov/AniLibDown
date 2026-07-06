import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let session: PlayerSession

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var currentIndex: Int
    @State private var player: AVPlayer?
    @State private var showEpisodeList = false

    init(session: PlayerSession) {
        self.session = session
        _currentIndex = State(initialValue: session.startIndex)
    }

    private var currentEpisode: Episode {
        session.episodes[currentIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView("Подготовка плеера...")
                        .tint(.white)
                }

                controlsOverlay
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(session.releaseTitle)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showEpisodeList = true
                    } label: {
                        Label("Серии", systemImage: "list.bullet")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .confirmationDialog("Выбор серии", isPresented: $showEpisodeList, titleVisibility: .visible) {
                ForEach(Array(session.episodes.enumerated()), id: \.element.id) { index, episode in
                    Button(episode.displayTitle) {
                        switchToEpisode(at: index)
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
            .onAppear {
                OrientationManager.shared.lockLandscape()
                AudioSessionConfigurator.activatePlayback()
                loadEpisode(at: currentIndex)
            }
            .onDisappear {
                player?.pause()
                player = nil
                AudioSessionConfigurator.deactivatePlayback()
                OrientationManager.shared.unlockAll()
            }
        }
    }

    private var controlsOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 32) {
                Button {
                    switchToEpisode(at: currentIndex - 1)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title)
                        .padding()
                }
                .disabled(currentIndex == 0)

                VStack(spacing: 4) {
                    Text(currentEpisode.displayTitle)
                        .font(.headline)
                    Text("\(currentIndex + 1) / \(session.episodes.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button {
                    switchToEpisode(at: currentIndex + 1)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .padding()
                }
                .disabled(currentIndex >= session.episodes.count - 1)
            }
            .foregroundStyle(.white)
            .padding()
            .background(.black.opacity(0.55))
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
