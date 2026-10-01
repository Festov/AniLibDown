import SwiftUI
import AVKit

let playerOverlayAnimation = Animation.easeInOut(duration: 0.35)

enum PlayerTimeFormatting {
    static func string(_ seconds: Double) -> String {
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
}

// MARK: - Top bar

struct PlayerTopBar: View {
    let releaseTitle: String
    let episodeTitle: String
    let episodeNumber: Int
    let totalEpisodes: Int
    let qualityTitle: String
    let isEpisodeListVisible: Bool
    let showsPictureInPicture: Bool
    let isPictureInPictureActive: Bool
    let showsAirPlay: Bool

    let onToggleEpisodeList: () -> Void
    let onOpenSettings: () -> Void
    let onTogglePictureInPicture: () -> Void
    let onClose: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggleEpisodeList()
                onInteraction()
            } label: {
                Label("Серии", systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isEpisodeListVisible ? "Скрыть список серий" : "Список серий")

            VStack(spacing: 2) {
                Text(releaseTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text(episodeTitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Text(" (\(episodeNumber)/\(totalEpisodes))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(releaseTitle), \(episodeTitle), серия \(episodeNumber) из \(totalEpisodes), \(qualityTitle)")

            Button {
                onOpenSettings()
                onInteraction()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Настройки плеера")

            if showsPictureInPicture {
                Button {
                    onTogglePictureInPicture()
                    onInteraction()
                } label: {
                    Image(systemName: isPictureInPictureActive ? "pip.exit" : "pip.enter")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Картинка в картинке")
            }

            if showsAirPlay {
                AirPlayRoutePicker()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("AirPlay")
            }

            Button("Закрыть", action: onClose)
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
}

// MARK: - Center controls

struct PlayerCenterControls: View {
    let isPlaying: Bool
    let hasPrevious: Bool
    let hasNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPlayPause: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        HStack(spacing: 48) {
            episodeButton(
                systemName: "backward.fill",
                enabled: hasPrevious,
                accessibilityLabel: "Предыдущая серия",
                action: onPrevious
            )

            Button {
                onPlayPause()
                onInteraction()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Пауза" : "Воспроизведение")

            episodeButton(
                systemName: "forward.fill",
                enabled: hasNext,
                accessibilityLabel: "Следующая серия",
                action: onNext
            )
        }
    }

    private func episodeButton(
        systemName: String,
        enabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            onInteraction()
        } label: {
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
}

// MARK: - Bottom bar

struct PlayerBottomBar: View {
    let displayedTime: Double
    let duration: Double
    let showsRemainingTime: Bool

    let onScrubChanged: (Double) -> Void
    let onScrubEditingChanged: (Bool) -> Void
    let onToggleTimeMode: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(PlayerTimeFormatting.string(displayedTime))
                    .font(.caption.monospacedDigit())
                    .frame(width: 52, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { min(displayedTime, max(duration, 0.1)) },
                        set: { onScrubChanged($0) }
                    ),
                    in: 0...max(duration, 0.1),
                    onEditingChanged: { editing in
                        onScrubEditingChanged(editing)
                    }
                )
                .tint(.white)
                .accessibilityLabel("Позиция воспроизведения")
                .accessibilityValue(PlayerTimeFormatting.string(displayedTime))

                Button {
                    onToggleTimeMode()
                    onInteraction()
                } label: {
                    Text(trailingTimeLabel)
                        .font(.caption.monospacedDigit())
                        .frame(width: 52, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsRemainingTime ? "Оставшееся время" : "Длительность")
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

    private var trailingTimeLabel: String {
        if showsRemainingTime {
            let remaining = max(duration - displayedTime, 0)
            return "-\(PlayerTimeFormatting.string(remaining))"
        }
        return PlayerTimeFormatting.string(duration)
    }
}

// MARK: - Skip prompt

struct PlayerSkipPromptOverlay: View {
    let promptProgress: Double
    let isControlsVisible: Bool
    let onDecline: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                declineButton
            }
            .padding(.trailing, 16)
            .padding(.bottom, isControlsVisible ? 72 : 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var declineButton: some View {
        Button {
            onDecline()
            onInteraction()
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))

                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.9))
                        .frame(width: max(geometry.size.width * CGFloat(promptProgress), 0))
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
}

// MARK: - Episode list

struct PlayerEpisodeListContent: View {
    let episodes: [Episode]
    let currentIndex: Int
    let onSelect: (Int) -> Void
    let onClose: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Серии")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
            }
            .foregroundStyle(.white)
            .padding()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                        Button {
                            onSelect(index)
                            onClose()
                            onInteraction()
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
}