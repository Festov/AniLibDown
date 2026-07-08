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

    func load(id: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            release = try await APIClient.shared.getRelease(idOrAlias: String(id))
            collectionStatus = CollectionStatusStore.shared.status(for: id)
            refreshShikimoriLink(releaseId: id)
            await refreshShikimoriStatus(releaseId: id)
        } catch {
            errorMessage = error.localizedDescription
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
    @ObservedObject private var shikimoriAuth = ShikimoriAuthService.shared
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var selectedQuality: VideoQuality = .p720
    @State private var playerSession: PlayerSession?
    @State private var selectedEpisodeRangeIndex = 0
    @State private var showShikimoriSearch = false

    private let episodeRangeSize = 50

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.release == nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSkeleton
                        descriptionSkeleton
                        qualityPickerSkeleton
                        episodesSkeleton
                    }
                    .padding()
                }
            } else if let release = viewModel.release {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(for: release)
                        if authService.isAuthenticated {
                            collectionSection(for: release)
                        }
                        shikimoriSection(for: release)
                        descriptionSection(for: release)
                        qualityPicker
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
        .fullScreenCover(item: $playerSession) { session in
            VideoPlayerView(session: session)
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

    private var qualityPickerSkeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.22))
                .frame(width: 90, height: 20)
                .skeletonShimmer()

            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.16))
                .frame(height: 32)
                .skeletonShimmer()
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
            PosterImage(path: release.poster?.displayURL, cornerRadius: 12)
                .frame(width: 120, height: 170)

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
                BroadcastStatusBadge(status: release.broadcastStatus)
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
                Text("\(release.episodes.count) / \(release.episodesTotal ?? release.episodes.count) серий")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func collectionSection(for release: ReleaseDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("В коллекции")
                .font(.headline)

            Picker("Статус", selection: collectionBinding(for: release.id)) {
                Text("Не в коллекции").tag(Optional<CollectionType>.none)
                ForEach(CollectionType.allCases) { type in
                    Text(type.title).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)
            .disabled(viewModel.isUpdatingCollection)

            if viewModel.isUpdatingCollection {
                ProgressView()
                    .controlSize(.small)
            }

            if let error = viewModel.collectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func collectionBinding(for releaseId: Int) -> Binding<CollectionType?> {
        Binding(
            get: { viewModel.collectionStatus },
            set: { newValue in
                Task { await viewModel.setCollectionStatus(newValue, releaseId: releaseId) }
            }
        )
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

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Качество")
                .font(.headline)
            Picker("Качество", selection: $selectedQuality) {
                ForEach(VideoQuality.allCases) { quality in
                    Text(quality.rawValue).tag(quality)
                }
            }
            .pickerStyle(.segmented)
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
                    quality: selectedQuality
                )
            } label: {
                Label("Скачать все серии (\(downloadable.count))", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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
                            .tint(selectedEpisodeRangeIndex == index ? .accentColor : .secondary)
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
                            quality: selectedQuality
                        )
                    },
                    onDeleteDownload: {
                        if let item = downloadManager.downloadItem(for: episode.id, quality: selectedQuality) {
                            downloadManager.delete(item: item)
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
    let onDeleteDownload: () -> Void

    @EnvironmentObject private var downloadManager: DownloadManager

    private var downloadState: DownloadItem.DownloadState? {
        downloadManager.downloadItem(for: episode.id, quality: quality)?.state
    }

    private var isDownloaded: Bool {
        downloadManager.isDownloaded(episodeId: episode.id, quality: quality)
    }

    private var canPlay: Bool {
        quality.streamURL(for: episode) != nil || isDownloaded
    }

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: episode.preview?.thumbnail ?? episode.preview?.displayURL, cornerRadius: 6)
                .frame(width: 72, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.displayTitle)
                    .font(.subheadline.weight(.medium))
                Text(durationString(episode.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            downloadStatusIcon

            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!canPlay)

            if isDownloaded {
                Button(action: onDeleteDownload) {
                    Image(systemName: "trash.circle")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(
                    quality.streamURL(for: episode) == nil
                    || downloadState == .downloading
                    || downloadState == .queued
                )
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            if canPlay {
                onPlay()
            }
        }
    }

    @ViewBuilder
    private var downloadStatusIcon: some View {
        if isDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if let state = downloadState {
            switch state {
            case .downloading, .queued:
                if let item = downloadManager.downloadItem(for: episode.id, quality: quality) {
                    ProgressView(value: item.progress)
                        .frame(width: 28)
                }
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.red)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func durationString(_ seconds: Int?) -> String {
        guard let seconds else { return "—" }
        return "\(seconds / 60) мин"
    }
}
