import SwiftUI

struct ReleaseDetailView: View {
    let releaseId: Int

    @StateObject private var viewModel = ReleaseDetailViewModel()
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var episodeAlerts = EpisodeAlertStore.shared
    @ObservedObject private var shikimoriAuth = ShikimoriAuthService.shared
    @State private var playerSession: PlayerSession?
    @State private var showShikimoriSearch = false
    @State private var showPosterFullscreen = false
    @State private var showLogin = false

    private var selectedQuality: VideoQuality {
        appSettings.defaultVideoQuality
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.release == nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSkeleton
                        descriptionSkeleton
                    }
                    .padding()
                }
            } else if let release = viewModel.release {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(for: release)
                        actionButtons(for: release)
                        if let error = viewModel.collectionError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if appSettings.showShikimoriOnReleaseCard {
                            ShikimoriReleaseSection(
                                release: release,
                                viewModel: viewModel,
                                shikimoriAuth: shikimoriAuth,
                                onLinkTapped: { showShikimoriSearch = true }
                            )
                        }
                        descriptionSection(for: release)
                        relatedSection(currentReleaseId: release.id)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(viewModel.errorMessage ?? "Попробуйте позже")
                } actions: {
                    Button("Повторить") {
                        Task { await viewModel.load(id: releaseId) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(viewModel.release?.name.main ?? "Аниме")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(id: releaseId)
        }
        .onAppear {
            viewModel.refreshCollectionStatus(releaseId: releaseId)
            viewModel.refreshShikimoriLink(releaseId: releaseId)
        }
        .onChange(of: shikimoriAuth.isAuthenticated) { _, _ in
            Task { await viewModel.refreshShikimoriStatus(releaseId: releaseId) }
        }
        .sheet(isPresented: $showShikimoriSearch) {
            if let release = viewModel.release {
                ShikimoriLinkSearchView(releaseTitle: release.name.main) { anime in
                    Task { await viewModel.linkShikimori(anime: anime, releaseId: releaseId) }
                }
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
        .fullScreenCover(item: $playerSession) { session in
            VideoPlayerView(session: session)
        }
        .fullScreenCover(isPresented: $showPosterFullscreen) {
            PosterFullscreenView(path: viewModel.release?.poster?.displayURL)
        }
    }

    private var headerSkeleton: some View {
        HStack(alignment: .top, spacing: 16) {
            SkeletonPoster(cornerRadius: 12)
                .frame(width: 120, height: 170)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.22))
                    .frame(height: 24)
                    .skeletonShimmer()
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: 180, height: 16)
                    .skeletonShimmer()
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: 120, height: 14)
                    .skeletonShimmer()
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: 72, height: 24)
                    .skeletonShimmer()
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.16))
                    .frame(height: 12)
                    .skeletonShimmer()
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.16))
                    .frame(width: 140, height: 12)
                    .skeletonShimmer()
            }
        }
    }

    private var descriptionSkeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.22))
                .frame(width: 110, height: 20)
                .skeletonShimmer()

            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.16))
                    .frame(height: 14)
                    .frame(maxWidth: index == 3 ? 220 : .infinity, alignment: .leading)
                    .skeletonShimmer()
            }
        }
    }

    @ViewBuilder
    private func header(for release: ReleaseDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Button {
                showPosterFullscreen = true
            } label: {
                PosterImage(path: release.poster?.displayURL, cornerRadius: 12)
                    .frame(width: 120, height: 170)
            }
            .buttonStyle(.plain)
            .disabled(release.poster?.displayURL == nil)

            VStack(alignment: .leading, spacing: 6) {
                Text(release.name.main)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let english = release.name.english, !english.isEmpty {
                    Text(english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(ReleaseFormatting.yearString(release.year)) • \(release.type?.description ?? "Аниме")")
                    .font(.subheadline)
                if let rating = release.ageRating?.label {
                    Text(rating)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
                if let genres = release.genres, !genres.isEmpty {
                    Text(genres.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let aired = release.episodes.count
                let total = release.episodesTotal ?? aired
                Text("\(aired) / \(total) \(ReleaseFormatting.episodesWord(for: total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Only for titles AniLiberty is still releasing (including late dubs).
                if release.isOngoing, let day = release.publishDay {
                    Text("Выходит: \(day.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtons(for release: ReleaseDetail) -> some View {
        let resumeEpisode = resumeEpisode(for: release)

        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let episode = resumeEpisode {
                        play(episode: episode, release: release)
                    }
                } label: {
                    Label(
                        resumeEpisode != nil ? "Смотреть" : "Смотреть с начала",
                        systemImage: "play.fill"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .disabled(release.episodes.isEmpty)

                if authService.isAuthenticated {
                    collectionMenuButton(for: release)
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        Label("Коллекции", systemImage: "heart")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                }
            }

            HStack(spacing: 10) {
                NavigationLink {
                    ReleaseEpisodesView(release: release)
                } label: {
                    Label("Все серии", systemImage: "list.bullet")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .disabled(release.episodes.isEmpty)

                NavigationLink {
                    ReleaseTeamView(releaseId: release.id, initialMembers: release.members)
                } label: {
                    Label("Команда", systemImage: "person.3.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
            }

            if shouldShowEpisodeAlertButton(for: release) {
                episodeAlertButton(for: release)
            }
        }
    }

    /// Reminders make sense while AniLiberty still releases episodes (including late dubs).
    /// Keep the control if the user is already subscribed, so they can turn it off.
    private func shouldShowEpisodeAlertButton(for release: ReleaseDetail) -> Bool {
        release.isOngoing || episodeAlerts.isSubscribed(releaseId: release.id)
    }

    @ViewBuilder
    private func episodeAlertButton(for release: ReleaseDetail) -> some View {
        let subscribed = episodeAlerts.isSubscribed(releaseId: release.id)
        Button {
            let latest = release.episodes.max(by: { $0.ordinal < $1.ordinal })
            let seed = latest?.id
            let nextNumber: Int? = {
                guard let latest else { return 1 }
                return Int(latest.ordinal.rounded(.towardZero)) + 1
            }()
            episodeAlerts.toggleSubscription(
                releaseId: release.id,
                title: release.name.main,
                posterPath: release.poster?.displayURL,
                publishDay: release.publishDay,
                nextEpisodeNumber: nextNumber,
                seedEpisodeId: seed
            )
            if !subscribed {
                appSettings.episodeNotificationsEnabled = true
                Task {
                    await NotificationManager.shared.requestAuthorizationIfNeeded()
                    await episodeAlerts.rescheduleReminders()
                }
            }
        } label: {
            Label(
                subscribed ? "Уведомления включены" : "Напомнить о сериях",
                systemImage: subscribed ? "bell.fill" : "bell"
            )
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func collectionMenuButton(for release: ReleaseDetail) -> some View {
        Menu {
            Button {
                Task { await viewModel.setCollectionStatus(nil, releaseId: release.id) }
            } label: {
                if viewModel.collectionStatus == nil {
                    Label("Не в коллекции", systemImage: "checkmark")
                } else {
                    Text("Не в коллекции")
                }
            }

            ForEach(CollectionType.allCases) { type in
                Button {
                    Task { await viewModel.setCollectionStatus(type, releaseId: release.id) }
                } label: {
                    if viewModel.collectionStatus == type {
                        Label(type.title, systemImage: "checkmark")
                    } else {
                        Text(type.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isUpdatingCollection {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: viewModel.collectionStatus == nil ? "heart" : "heart.fill")
                }
                Text(viewModel.collectionStatus?.shortTitle ?? "Коллекции")
                    .lineLimit(1)
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.accentColor)
        .disabled(viewModel.isUpdatingCollection)
    }

    private func resumeEpisode(for release: ReleaseDetail) -> Episode? {
        if let lastId = WatchProgressStore.shared.lastEpisodeId(for: release.id),
           let episode = release.episodes.first(where: { $0.id == lastId }) {
            return episode
        }
        return release.episodes.first
    }

    @ViewBuilder
    private func relatedSection(currentReleaseId: Int) -> some View {
        if viewModel.isLoadingRelated {
            ProgressView("Связанные релизы...")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !viewModel.relatedReleases.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Связанные")
                    .font(.headline)

                ForEach(viewModel.relatedReleases) { item in
                    if let summary = item.release {
                        NavigationLink(value: item.releaseId) {
                            ReleaseRowView(
                                title: summary.name.main,
                                subtitle: ReleaseFormatting.listSubtitle(
                                    ReleaseFormatting.yearString(summary.year)
                                ),
                                posterPath: summary.poster?.displayURL,
                                isOngoing: summary.isOngoing
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: item.releaseId) {
                            Text("Релиз #\(item.releaseId)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func descriptionSection(for release: ReleaseDetail) -> some View {
        if let description = release.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Описание")
                    .font(.headline)
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func play(episode: Episode, release: ReleaseDetail) {
        ContinueWatchingStore.shared.updateMetadata(
            releaseId: release.id,
            releaseTitle: release.name.main,
            posterPath: release.poster?.displayURL,
            episodeId: episode.id,
            episodeTitle: episode.displayTitle,
            duration: episode.duration
        )
        playerSession = PlayerSession(
            releaseId: release.id,
            releaseTitle: release.name.main,
            episodes: release.episodes,
            startEpisodeId: episode.id,
            quality: selectedQuality,
            preferOffline: true,
            episodesTotal: release.episodesTotal,
            posterPath: release.poster?.displayURL
        )
    }
}
