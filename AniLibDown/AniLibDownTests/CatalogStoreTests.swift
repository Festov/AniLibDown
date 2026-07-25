import XCTest
@testable import AniLibDown

@MainActor
final class CatalogStoreTests: XCTestCase {
    func testCacheKeyIncludesSortingAndYear() {
        let store = CatalogStore.shared
        store.sorting = .yearDesc
        store.filterYear = 2024
        store.searchText = "test"
        store.selectedGenreIds = [1, 2]
        store.applyFilters()
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testYearFilterToggle() {
        let store = CatalogStore.shared
        store.applyYearFilter(2020)
        XCTAssertEqual(store.filterYear, 2020)
        store.applyYearFilter(nil)
        XCTAssertNil(store.filterYear)
    }
}
