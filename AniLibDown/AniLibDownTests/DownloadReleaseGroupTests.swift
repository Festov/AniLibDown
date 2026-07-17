import XCTest
@testable import AniLibDown

final class DownloadReleaseGroupTests: XCTestCase {
    func testFailedCount() {
        let items = [
            makeItem(id: "1", state: .completed),
            makeItem(id: "2", state: .failed),
            makeItem(id: "3", state: .failed),
            makeItem(id: "4", state: .downloading)
        ]
        let group = DownloadReleaseGroup(
            id: "release:1",
            releaseId: 1,
            releaseTitle: "Test",
            posterPath: nil,
            items: items
        )

        XCTAssertEqual(group.completedCount, 1)
        XCTAssertEqual(group.activeCount, 1)
        XCTAssertEqual(group.failedCount, 2)
    }

    private func makeItem(id: String, state: DownloadItem.DownloadState) -> DownloadItem {
        DownloadItem(
            id: id,
            episodeId: id,
            releaseId: 1,
            releaseTitle: "Test",
            episodeTitle: "Серия 1",
            episodeName: nil,
            episodeOrdinal: 1,
            quality: "720p",
            remoteURL: "https://example.com/\(id).m3u8",
            localBookmark: nil,
            progress: state == .completed ? 1 : 0,
            state: state,
            createdAt: Date()
        )
    }
}
