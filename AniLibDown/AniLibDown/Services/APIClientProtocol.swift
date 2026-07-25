import Foundation

protocol APIClientProtocol: Actor {
    func setAccessToken(_ token: String?) async
    func login(login: String, password: String) async throws -> String
    func logout() async throws
    func getProfile() async throws -> UserProfile
    func getCatalog(
        page: Int,
        limit: Int,
        search: String?,
        genreIds: [Int],
        sorting: CatalogSorting,
        year: Int?
    ) async throws -> CatalogResponse
    func getCatalogGenres() async throws -> [AnimeGenre]
    func getRelease(idOrAlias: String) async throws -> ReleaseDetail
    func getRandomReleases(limit: Int) async throws -> [ReleaseSummary]
    func getFranchises(forReleaseId releaseId: Int) async throws -> [Franchise]
    func getCollection(type: CollectionType, page: Int, limit: Int) async throws -> CollectionResponse
    func getCollectionIds() async throws -> [CollectionMembership]
    func addToCollection(releaseId: Int, type: CollectionType) async throws
    func removeFromCollection(releaseId: Int) async throws
}

extension APIClient: APIClientProtocol {}
