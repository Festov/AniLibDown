import SwiftUI

@MainActor
final class ReleaseDetailViewModel: ObservableObject {
    @Published var release: ReleaseDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var collectionStatus: CollectionType?
    @Published var isUpdatingCollection = false
    @Published var collectionError: String?
    @Published var shikimoriStatus: ShikimoriListStatus?
    @Published var shikimoriLink: ShikimoriLink?
    @Published var isUpdatingShikimori = false
    @Published var shikimoriError: String?
    @Published var relatedReleases: [FranchiseRelease] = []
    @Published var isLoadingRelated = false

    func load(id: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let releaseTask = APIClient.shared.getRelease(idOrAlias: String(id))
        async let relatedTask = loadRelatedReleases(releaseId: id)

        do {
            release = try await releaseTask
            collectionStatus = CollectionStatusStore.shared.status(for: id)
            refreshShikimoriLink(releaseId: id)
            await refreshShikimoriStatus(releaseId: id)
            _ = await relatedTask
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRelatedReleases(releaseId: Int) async {
        isLoadingRelated = true
        defer { isLoadingRelated = false }

        do {
            let franchises = try await APIClient.shared.getFranchises(forReleaseId: releaseId)
            var seen = Set<Int>()
            var related: [FranchiseRelease] = []
            for franchise in franchises {
                for item in franchise.relatedReleases where item.releaseId != releaseId {
                    if seen.insert(item.releaseId).inserted {
                        related.append(item)
                    }
                }
            }
            relatedReleases = related
        } catch {
            relatedReleases = []
        }
    }

    func refreshCollectionStatus(releaseId: Int) {
        collectionStatus = CollectionStatusStore.shared.status(for: releaseId)
    }

    func refreshShikimoriLink(releaseId: Int) {
        shikimoriLink = ShikimoriLinkStore.shared.link(for: releaseId)
    }

    func refreshShikimoriStatus(releaseId: Int) async {
        guard ShikimoriAuthService.shared.isAuthenticated,
              let link = ShikimoriLinkStore.shared.link(for: releaseId) else {
            shikimoriStatus = nil
            return
        }

        shikimoriError = nil
        do {
            let rate = try await ShikimoriAuthService.shared.userRate(for: link.animeId)
            shikimoriStatus = rate?.listStatus
        } catch {
            shikimoriError = error.localizedDescription
        }
    }

    func linkShikimori(anime: ShikimoriAnime, releaseId: Int) async {
        let link = ShikimoriLink(animeId: anime.id, title: anime.displayTitle)
        ShikimoriLinkStore.shared.setLink(link, for: releaseId)
        shikimoriLink = link
        shikimoriStatus = nil
        await refreshShikimoriStatus(releaseId: releaseId)
    }

    func unlinkShikimori(releaseId: Int) {
        ShikimoriLinkStore.shared.setLink(nil, for: releaseId)
        shikimoriLink = nil
        shikimoriStatus = nil
        shikimoriError = nil
    }

    func setShikimoriStatus(_ status: ShikimoriListStatus, releaseId: Int) async {
        guard let link = ShikimoriLinkStore.shared.link(for: releaseId) else { return }

        isUpdatingShikimori = true
        shikimoriError = nil
        defer { isUpdatingShikimori = false }

        do {
            let rate = try await ShikimoriAuthService.shared.setStatus(status, animeId: link.animeId)
            shikimoriStatus = rate.listStatus
        } catch {
            shikimoriError = error.localizedDescription
        }
    }

    func setCollectionStatus(_ type: CollectionType?, releaseId: Int) async {
        isUpdatingCollection = true
        collectionError = nil
        defer { isUpdatingCollection = false }

        do {
            try await CollectionStatusStore.shared.setStatus(releaseId: releaseId, type: type)
            collectionStatus = type
        } catch {
            collectionError = error.localizedDescription
        }
    }
}

struct ReleaseDetailView: View {
    let releaseId: Int

    @StateObject private var viewModel = ReleaseDetailViewModel()
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var shikimoriAuth = ShikimoriAuthService.shared
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var playerSession: PlayerSession?
    @State private var selectedEpisodeRangeIndex = 0
    @State private var showShikimoriSearch = false
    @State private var showPosterFullscreen = false
    @State private var showLogin = false

    private let episodeRangeSize = 50

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
                        episodesSkeleton
                    }
                    .padding()
                }
            } else if let release = viewModel.release {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(for: release)
                        actionButtonsRow(for: release)
                        if let error = viewModel.collectionError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if appSettings.showShikimoriOnReleaseCard {
                            shikimoriSection(for: release)
                        }
                        descriptionSection(for: release)
                        relatedSection(currentReleaseId: release.id)
                        downloadAllButton(for: release)
                        episodesSection(for: release)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Не удалось загрузить",
                    systemImage: "exclamationmark.triangle",
                    description: Text(viewModel.errorMessage ?? "Попробуйте позже")
                )
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

    private var episodesSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.22))
                .frame(width: 70, height: 20)
                .skeletonShimmer()

            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.14))
                    .frame(height: 52)
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
            }
        }
    }

    @ViewBuilder
    private func actionButtonsRow(for release: ReleaseDetail) -> some View {
        let resumeEpisode = resumeEpisode(for: release)

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
                                subtitle: ReleaseFormatting.yearString(summary.year),
                                posterPath: summary.poster?.displayURL
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
    private func shikimoriSection(for release: ReleaseDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shikimori")
                .font(.headline)

            if !ShikimoriConfig.isConfigured {
                Text(ShikimoriConfig.configurationHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !shikimoriAuth.isAuthenticated {
                Text("Подключите аккаунт Shikimori в профиле, чтобы отмечать статус просмотра.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let link = viewModel.shikimoriLink {
                Text("Привязано: \(link.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Статус", selection: shikimoriStatusBinding(for: release.id)) {
                    ForEach(ShikimoriListStatus.allCases.filter { $0 != .rewatching }) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.isUpdatingShikimori)

                if viewModel.isUpdatingShikimori {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Сменить привязку", role: .destructive) {
                    showShikimoriSearch = true
                }
                .font(.caption)

                Button("Отвязать") {
                    viewModel.unlinkShikimori(releaseId: release.id)
                }
                .font(.caption)
            } else {
                Text("Привяжите этот релиз к тайтлу на Shikimori, чтобы ставить статусы вроде «Смотрю» или «Просмотрено».")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showShikimoriSearch = true
                } label: {
                    Label("Привязать к Shikimori", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let error = viewModel.shikimoriError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func shikimoriStatusBinding(for releaseId: Int) -> Binding<ShikimoriListStatus> {
        Binding(
            get: { viewModel.shikimoriStatus ?? .planned },
            set: { newValue in
                Task { await viewModel.setShikimoriStatus(newValue, releaseId: releaseId) }
            }
        )
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

    @ViewBuilder
    private func downloadAllButton(for release: ReleaseDetail) -> some View {
        let downloadable = release.episodes.filter { selectedQuality.streamURL(for: $0) != nil }
        if !downloadable.isEmpty {
            Button {
                downloadManager.enqueueAll(
                    episodes: downloadable,
                    releaseId: release.id,
                    releaseTitle: release.name.main,
                    quality: selectedQuality,
                    posterPath: release.poster?.displayURL
                )
            } label: {
                Label(
                    "Скачать все серии (\(downloadable.count))",
                    systemImage: "arrow.down.circle.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
        }
    }

    @ViewBuilder
    private func episodesSection(for release: ReleaseDetail) -> some View {
        let ranges = episodeRanges(for: release.episodes.count)
        let visibleEpisodes = episodes(in: release.episodes, rangeIndex: selectedEpisodeRangeIndex, ranges: ranges)

        VStack(alignment: .leading, spacing: 8) {
            Text("Серии")
                .font(.headline)

            if ranges.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                            Button(range.label) {
                                selectedEpisodeRangeIndex = index
                            }
                            .buttonStyle(.bordered)
                            .tint(selectedEpisodeRangeIndex == index ? Color.accentColor : .secondary)
                        }
                    }
                }
            }

            ForEach(visibleEpisodes) { episode in
                EpisodeRow(
                    episode: episode,
                    quality: selectedQuality,
                    releaseId: release.id,
                    releaseTitle: release.name.main,
                    onPlay: { play(episode: episode, release: release) },
                    onDownload: {
                        downloadManager.enqueue(
                            episode: episode,
                            releaseId: release.id,
                            releaseTitle: release.name.main,
                            quality: selectedQuality,
                            posterPath: release.poster?.displayURL
                        )
                    },
                    onCancelDownload: {
                        if let item = downloadManager.downloadItem(for: episode.id, quality: selectedQuality) {
                            downloadManager.cancel(item: item)
                        }
                    },
                    onDeleteDownload: {
                        if let item = downloadManager.downloadItem(for: episode.id, quality: selectedQuality) {
                            downloadManager.delete(item: item)
                        }
                    },
                    onRetryDownload: {
                        if let item = downloadManager.downloadItem(for: episode.id, quality: selectedQuality) {
                            downloadManager.retry(item: item)
                        }
                    }
                )
            }
        }
    }

    private func play(episode: Episode, release: ReleaseDetail) {
        playerSession = PlayerSession(
            releaseId: release.id,
            releaseTitle: release.name.main,
            episodes: release.episodes,
            startEpisodeId: episode.id,
            quality: selectedQuality,
            preferOffline: true,
            episodesTotal: release.episodesTotal
        )
    }

    private struct EpisodeRange {
        let start: Int
        let end: Int

        var label: String { "\(start)-\(end)" }
    }

    private func episodeRanges(for count: Int) -> [EpisodeRange] {
        guard count > 100 else {
            return count > 0 ? [EpisodeRange(start: 1, end: count)] : []
        }

        var ranges: [EpisodeRange] = []
        var start = 1
        while start <= count {
            let end = min(start + episodeRangeSize - 1, count)
            ranges.append(EpisodeRange(start: start, end: end))
            start = end + 1
        }
        return ranges
    }

    private func episodes(in allEpisodes: [Episode], rangeIndex: Int, ranges: [EpisodeRange]) -> [Episode] {
        guard ranges.indices.contains(rangeIndex) else { return allEpisodes }
        let range = ranges[rangeIndex]
        return allEpisodes.filter { episode in
            let number = Int(episode.ordinal.rounded(.towardZero))
            return number >= range.start && number <= range.end
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let quality: VideoQuality
    let releaseId: Int
    let releaseTitle: String
    let onPlay: () -> Void
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDeleteDownload: () -> Void
    let onRetryDownload: () -> Void

    @EnvironmentObject private var downloadManager: DownloadManager

    private var downloadItem: DownloadItem? {
        downloadManager.downloadItem(for: episode.id, quality: quality)
    }

    private var downloadState: DownloadItem.DownloadState? {
        downloadItem?.state
    }

    private var downloadProgress: Double {
        downloadItem?.progress ?? 0
    }

    private var isDownloaded: Bool {
        downloadManager.isDownloaded(episodeId: episode.id, quality: quality)
    }

    private var isDownloading: Bool {
        downloadState == .downloading || downloadState == .queued
    }

    private var isFailed: Bool {
        downloadState == .failed
    }

    private var canPlay: Bool {
        quality.streamURL(for: episode) != nil || isDownloaded
    }

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: episode.preview?.thumbnail ?? episode.preview?.displayURL, cornerRadius: 6)
                .frame(width: 72, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.displayTitle)
                    .font(.subheadline.weight(.medium))
                Text(durationString(episode.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isFailed {
                    Text(downloadItem?.lastError ?? "Ошибка загрузки")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            downloadActionButton
        }
        .padding(10)
        .background {
            ZStack(alignment: .leading) {
                Color(.secondarySystemBackground)
                if watchProgress > 0 {
                    Color.accentColor.opacity(0.18)
                        .frame(maxWidth: .infinity)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(maxWidth: .infinity)
                                .scaleEffect(x: watchProgress, y: 1, anchor: .leading)
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(episode.displayTitle)
        .onTapGesture {
            if canPlay {
                onPlay()
            }
        }
    }

    @ViewBuilder
    private var downloadActionButton: some View {
        if isDownloaded {
            Button(action: onDeleteDownload) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Удалить скачанную серию")
        } else if isDownloading {
            Button(action: onCancelDownload) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                        .frame(width: 34, height: 34)

                    Circle()
                        .trim(from: 0, to: max(downloadProgress, downloadState == .queued ? 0.05 : 0))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: downloadProgress)

                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить загрузку")
        } else if isFailed {
            Button(action: onRetryDownload) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Повторить загрузку")
            .accessibilityHint(downloadItem?.lastError ?? "Попробовать скачать снова")
        } else {
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .disabled(quality.streamURL(for: episode) == nil)
            .accessibilityLabel("Скачать серию")
        }
    }

    private var watchProgress: Double {
        WatchProgressStore.shared.progressFraction(for: episode.id, duration: episode.duration)
    }

    private func durationString(_ seconds: Int?) -> String {
        guard let seconds else { return "—" }
        return "\(seconds / 60) мин"
    }
}
