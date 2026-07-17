import XCTest
@testable import AniLibDown

final class ReleaseFormattingTests: XCTestCase {
    func testEpisodesWordPluralization() {
        XCTAssertEqual(ReleaseFormatting.episodesWord(for: 1), "серия")
        XCTAssertEqual(ReleaseFormatting.episodesWord(for: 2), "серии")
        XCTAssertEqual(ReleaseFormatting.episodesWord(for: 3), "серии")
        XCTAssertEqual(ReleaseFormatting.episodesWord(for: 4), "серии")
        XCTAssertEqual(ReleaseFormatting.episodesWord(for: 5), "серий")
        XCTAssertEqual(ReleaseFormatting.episodesWord(for: 11), "серий")
        XCTAssertEqual(ReleaseFormatting.episodesWord(for: 21), "серия")
        XCTAssertEqual(ReleaseFormatting.episodesWord(for: 22), "серии")
    }

    func testEpisodesCountLabel() {
        XCTAssertEqual(ReleaseFormatting.episodesCountLabel(1), "1 серия")
        XCTAssertEqual(ReleaseFormatting.episodesCountLabel(12), "12 серий")
    }

    func testDisplayEpisodeOrdinal() {
        XCTAssertEqual(ReleaseFormatting.displayEpisodeOrdinal(0), "—")
        XCTAssertEqual(ReleaseFormatting.displayEpisodeOrdinal(1), "1")
        XCTAssertEqual(ReleaseFormatting.displayEpisodeOrdinal(12), "12")
        XCTAssertEqual(ReleaseFormatting.displayEpisodeOrdinal(0.5), "1")
        XCTAssertEqual(ReleaseFormatting.displayEpisodeOrdinal(3.5), "3.5")
    }

    func testBroadcastStatus() {
        XCTAssertEqual(
            ReleaseFormatting.broadcastStatus(
                isOngoing: true,
                isInProduction: false,
                episodesCount: 5,
                episodesTotal: 12
            ),
            .ongoing
        )
        XCTAssertEqual(
            ReleaseFormatting.broadcastStatus(
                isOngoing: false,
                isInProduction: false,
                episodesCount: 12,
                episodesTotal: 12
            ),
            .released
        )
        XCTAssertEqual(
            ReleaseFormatting.broadcastStatus(
                isOngoing: false,
                isInProduction: true,
                episodesCount: 0,
                episodesTotal: nil
            ),
            .upcoming
        )
    }
}
