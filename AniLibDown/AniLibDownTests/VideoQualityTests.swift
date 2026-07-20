import XCTest
@testable import AniLibDown

final class VideoQualityTests: XCTestCase {
    func testStreamURLMapping() {
        let episode = Episode(
            id: "ep-1",
            name: "Пилот",
            ordinal: 1,
            hls480: "https://example.com/480.m3u8",
            hls720: "https://example.com/720.m3u8",
            hls1080: "https://example.com/1080.m3u8"
        )

        XCTAssertEqual(VideoQuality.p480.streamURL(for: episode)?.absoluteString, "https://example.com/480.m3u8")
        XCTAssertEqual(VideoQuality.p720.streamURL(for: episode)?.absoluteString, "https://example.com/720.m3u8")
        XCTAssertEqual(VideoQuality.p1080.streamURL(for: episode)?.absoluteString, "https://example.com/1080.m3u8")
        XCTAssertEqual(episode.availableStreamQualities(), [.p1080, .p720, .p480])
    }

    func testMissingQualitiesAreFiltered() {
        let episode = Episode(
            id: "ep-2",
            name: nil,
            ordinal: 2,
            hls720: "https://example.com/720.m3u8"
        )

        XCTAssertEqual(episode.availableStreamQualities(), [.p720])
        XCTAssertFalse(VideoQuality.p1080.isAvailable(for: episode))
        XCTAssertTrue(VideoQuality.p720.isAvailable(for: episode))
    }
}
