import XCTest
@testable import AniLibDown

@MainActor
final class ShikimoriLinkStoreTests: XCTestCase {
    func testExportImportRoundTrip() throws {
        let store = ShikimoriLinkStore.shared
        let original = store.link(for: 42)
        defer { store.setLink(original, for: 42) }

        store.setLink(ShikimoriLink(animeId: 1, title: "Test"), for: 42)
        let data = try store.exportJSON()
        store.setLink(nil, for: 42)
        XCTAssertNil(store.link(for: 42))
        let count = try store.importJSON(data, merge: true)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.link(for: 42)?.title, "Test")
    }
}
