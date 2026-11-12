import XCTest
@testable import AniLibDown

final class DownloadStorageEstimateTests: XCTestCase {
    private func episode(id: String, duration: Int?) -> Episode {
        Episode(id: id, name: nil, ordinal: 1, duration: duration)
    }

    func testEstimateMatchesBitrateTable() {
        // 24 минуты (1440с) 720p при 2.5 Мбит/с → 2.5e6 / 8 * 1440 = 450 МБ
        let episodes = [episode(id: "1", duration: 1440)]
        XCTAssertEqual(
            DownloadManager.estimatedBytes(forEpisodes: episodes, quality: .p720),
            450_000_000
        )
    }

    func testEstimateScalesWithQuality() {
        let episodes = [episode(id: "1", duration: 1440)]
        XCTAssertEqual(
            DownloadManager.estimatedBytes(forEpisodes: episodes, quality: .p1080),
            900_000_000
        )
        XCTAssertEqual(
            DownloadManager.estimatedBytes(forEpisodes: episodes, quality: .p480),
            180_000_000
        )
    }

    func testEstimateSumsDurations() {
        let episodes = [
            episode(id: "1", duration: 1440),
            episode(id: "2", duration: 1440),
            episode(id: "3", duration: 720)
        ]
        XCTAssertEqual(
            DownloadManager.estimatedBytes(forEpisodes: episodes, quality: .p720),
            1_125_000_000
        )
    }

    func testEpisodesWithoutDurationAreSkipped() {
        let episodes = [episode(id: "1", duration: nil), episode(id: "2", duration: nil)]
        XCTAssertEqual(DownloadManager.estimatedBytes(forEpisodes: episodes, quality: .p1080), 0)
    }

    func testAvailableStorageIsReported() {
        let available = DownloadManager.availableStorageBytes()
        XCTAssertNotNil(available)
        XCTAssertGreaterThan(available ?? 0, 0)
    }
}
