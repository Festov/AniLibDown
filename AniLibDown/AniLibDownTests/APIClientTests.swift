import XCTest
@testable import AniLibDown

final class APIErrorTests: XCTestCase {
    func testFriendly404Message() {
        let error = APIError.httpError(status: 404, message: "No query results for model")
        XCTAssertTrue(error.localizedDescription.contains("VPN") || error.localizedDescription.contains("недоступен"))
    }
}

final class CatalogSortingTests: XCTestCase {
    func testSortingCases() {
        XCTAssertEqual(CatalogSorting.allCases.count, 3)
        XCTAssertEqual(CatalogSorting.freshAtDesc.title, "Сначала новые")
    }
}
