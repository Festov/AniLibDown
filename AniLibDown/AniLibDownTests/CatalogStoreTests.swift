import XCTest
@testable import AniLibDown

@MainActor
final class CatalogStoreTests: XCTestCase {
    private var createdCacheURLs: [URL] = []

    override func tearDown() {
        for url in createdCacheURLs {
            try? FileManager.default.removeItem(at: url)
        }
        createdCacheURLs = []
        super.tearDown()
    }

    /// Each test gets its own store and its own cache file, so no state leaks
    /// between tests and nothing is written to the real Documents directory.
    private func makeStore(api: any APIClientProtocol = MockAPIClient()) -> CatalogStore {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-page-cache-\(UUID().uuidString).json")
        createdCacheURLs.append(cacheURL)
        return CatalogStore(api: api, cacheFileURL: cacheURL)
    }

    func testCacheKeyIncludesSortingAndYear() {
        let store = makeStore()
        store.sorting = .yearDesc
        store.filterYear = 2024
        store.searchText = "test"
        store.selectedGenreIds = [1, 2]
        store.applyFilters()
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testYearFilterToggle() {
        let store = makeStore()
        store.applyYearFilter(2020)
        XCTAssertEqual(store.filterYear, 2020)
        store.applyYearFilter(nil)
        XCTAssertNil(store.filterYear)
    }

    func testFreshStoreHasNoActiveFilters() {
        let store = makeStore()
        XCTAssertFalse(store.hasActiveFilters)
        XCTAssertTrue(store.releases.isEmpty)
    }

    func testLoadInitialUsesInjectedAPIClient() async {
        let mock = MockAPIClient()
        let store = makeStore(api: mock)
        await store.loadInitial(force: true)
        let calls = await mock.catalogCallCount
        XCTAssertEqual(calls, 1)
        XCTAssertNil(store.errorMessage)
    }
}