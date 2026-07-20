import XCTest
@testable import AniLibDown

@MainActor
final class SearchHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AniLibDown.SearchHistoryStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRecordAndClear() {
        let store = SearchHistoryStore.shared
        store.clear()
        store.record("naruto")
        store.record("one piece")
        XCTAssertEqual(store.queries.first, "one piece")
        store.remove("one piece")
        XCTAssertFalse(store.queries.contains("one piece"))
        store.clear()
        XCTAssertTrue(store.queries.isEmpty)
    }
}
