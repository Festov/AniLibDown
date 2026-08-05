import Foundation

actor MockAPIClient: APIClientProtocol {
    var catalogPages: [Int: CatalogResponse] = [:]
    var genres: [AnimeGenre] = []
    var catalogCallCount = 0

    func setAccessToken(_ token: String?) async {}

    func login(login: String, password: String) async throws -> String {
        "token"
    }

    func logout() async throws {}

    func getProfile() async throws -> UserProfile {
        throw APIError.unauthorized
    }

    func getCatalog(
        page: Int,
        limit: Int,
        search: String?,
        genreIds: [Int],
        sorting: CatalogSorting,
        year: Int?
    ) async throws -> CatalogResponse {
        catalogCallCount += 1
        if let response = catalogPages[page] {
            return response
        }
        return CatalogResponse(
            data: [],
            meta: PaginatedMeta(pagination: Pagination(
                total: 0,
                count: 0,
                perPage: limit,
                currentPage: page,
                totalPages: 1
            ))
        )
    }

    func getCatalogGenres() async throws -> [AnimeGenre] {
        genres
    }

    func getRelease(idOrAlias: String) async throws -> ReleaseDetail {
        throw APIError.httpError(status: 404, message: nil)
    }

    func getRandomReleases(limit: Int) async throws -> [ReleaseSummary] {
        []
    }

    func getFranchises(forReleaseId releaseId: Int) async throws -> [Franchise] {
        []
    }

    func getScheduleNow() async throws -> ScheduleNowResponse {
        ScheduleNowResponse(today: [], yesterday: [], tomorrow: [])
    }

    func getScheduleWeek() async throws -> [ScheduleItem] {
        []
    }

    func getCollection(type: CollectionType, page: Int, limit: Int) async throws -> CollectionResponse {
        CatalogResponse(
            data: [],
            meta: PaginatedMeta(pagination: Pagination(
                total: 0,
                count: 0,
                perPage: limit,
                currentPage: page,
                totalPages: 1
            ))
        )
    }

    func getCollectionIds() async throws -> [CollectionMembership] {
        []
    }

    func addToCollection(releaseId: Int, type: CollectionType) async throws {}

    func removeFromCollection(releaseId: Int) async throws {}
}
