import XCTest
@testable import AniLibDown

@MainActor
final class WatchProgressStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: WatchProgressStore!
    private let suiteName = "AniLibDown.WatchProgressStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = WatchProgressStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testSaveAndReadPosition() {
        store.save(position: 42, episodeId: "ep-1", releaseId: 10)
        XCTAssertEqual(store.position(for: "ep-1"), 42)
        XCTAssertEqual(store.lastEpisodeId(for: 10), "ep-1")
    }

    func testIgnoresTinyPositions() {
        store.save(position: 3, episodeId: "ep-1", releaseId: 10)
        XCTAssertNil(store.position(for: "ep-1"))
    }

    func testClearPositionAndAll() {
        store.save(position: 20, episodeId: "ep-1", releaseId: 10)
        store.save(position: 30, episodeId: "ep-2", releaseId: 11)

        store.clearPosition(for: "ep-1")
        XCTAssertNil(store.position(for: "ep-1"))
        XCTAssertEqual(store.position(for: "ep-2"), 30)

        store.clearAll()
        XCTAssertNil(store.position(for: "ep-2"))
        XCTAssertNil(store.lastEpisodeId(for: 11))
    }

    func testProgressFraction() {
        store.save(position: 50, episodeId: "ep-1", releaseId: 1)
        XCTAssertEqual(store.progressFraction(for: "ep-1", duration: 100), 0.5, accuracy: 0.001)
        XCTAssertEqual(store.progressFraction(for: "ep-1", duration: nil), 0)
    }
}
