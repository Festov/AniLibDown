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
    @Published var shikimoriEpisodes: Int?
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
            ToastCenter.shared.show(error.localizedDescription, isError: true)
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
            shikimoriEpisodes = nil
            return
        }

        shikimoriError = nil
        do {
            let rate = try await ShikimoriAuthService.shared.userRate(for: link.animeId)
            shikimoriStatus = rate?.listStatus
            shikimoriEpisodes = rate?.episodes
        } catch {
            shikimoriError = error.localizedDescription
        }
    }

    func linkShikimori(anime: ShikimoriAnime, releaseId: Int) async {
        let link = ShikimoriLink(animeId: anime.id, title: anime.displayTitle)
        ShikimoriLinkStore.shared.setLink(link, for: releaseId)
        shikimoriLink = link
        shikimoriStatus = nil
        shikimoriEpisodes = nil
        await refreshShikimoriStatus(releaseId: releaseId)
    }

    func unlinkShikimori(releaseId: Int) {
        ShikimoriLinkStore.shared.setLink(nil, for: releaseId)
        shikimoriLink = nil
        shikimoriStatus = nil
        shikimoriEpisodes = nil
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
            shikimoriEpisodes = rate.episodes
        } catch {
            shikimoriError = error.localizedDescription
            ToastCenter.shared.show(error.localizedDescription, isError: true)
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
            ToastCenter.shared.show(error.localizedDescription, isError: true)
        }
    }
}
