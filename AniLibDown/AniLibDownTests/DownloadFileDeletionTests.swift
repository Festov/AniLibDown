import XCTest
@testable import AniLibDown

@MainActor
final class DownloadFileDeletionTests: XCTestCase {
    private var manager: DownloadManager!
    private var createdFiles: [URL] = []

    override func setUp() {
        super.setUp()
        manager = DownloadManager.shared
    }

    override func tearDown() {
        for url in createdFiles {
            try? FileManager.default.removeItem(at: url)
        }
        createdFiles = []
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeItem(filePath: String?) -> DownloadItem {
        DownloadItem(
            id: UUID().uuidString,
            episodeId: "ep-test",
            releaseId: 1,
            releaseTitle: "Test Release",
            episodeTitle: "Серия 1",
            episodeName: nil,
            episodeOrdinal: 1,
            quality: VideoQuality.p720.rawValue,
            remoteURL: "https://example.com/video/playlist.m3u8",
            localBookmark: nil,
            localFilePath: filePath,
            progress: 1,
            state: .completed,
            createdAt: Date()
        )
    }

    @discardableResult
    private func makeFile(in directory: URL, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("data".utf8).write(to: url)
        createdFiles.append(url)
        return url
    }

    // MARK: - Тесты

    func testDeletesExactFileInsideStorage() throws {
        let file = try makeFile(in: manager.storageURL, name: "episode-1.movpkg")
        let item = makeItem(filePath: file.path)

        manager.removeFiles(for: item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "файл по точному пути должен быть удалён")
    }

    func testDoesNotTouchFilesWithSimilarNames() throws {
        let file = try makeFile(in: manager.storageURL, name: "episode-1.movpkg")
        // Старый fuzzy-матчинг по подстроке удалил бы и этот файл.
        let decoy = try makeFile(in: manager.storageURL, name: "episode-10.movpkg")
        let item = makeItem(filePath: file.path)

        manager.removeFiles(for: item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: decoy.path),
                      "файл с похожим именем не должен пострадать")
    }

    func testRefusesToDeleteOutsideStorage() throws {
        // Имитация повреждённого индекса: путь указывает на чужой файл вне каталогов загрузок.
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = try makeFile(in: outside, name: "important.movpkg")
        let item = makeItem(filePath: file.path)

        manager.removeFiles(for: item)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "файл вне каталогов загрузок удаляться не должен")
    }

    func testIsDownloadStoragePath() {
        let inside = manager.storageURL.appendingPathComponent("some.movpkg")
        XCTAssertTrue(manager.isDownloadStoragePath(inside))

        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("some.movpkg")
        XCTAssertFalse(manager.isDownloadStoragePath(outside))

        // Каталог, чьё имя лишь начинается с имени каталога загрузок, — не внутри него.
        let sibling = manager.storageURL.deletingLastPathComponent()
            .appendingPathComponent("Downloads-evil/file.movpkg")
        XCTAssertFalse(manager.isDownloadStoragePath(sibling))
    }

    func testItemWithoutAnyPathIsSafeNoOp() {
        let item = makeItem(filePath: nil)
        // Ни bookmark, ни пути, ни pending-URL: ничего не должно произойти и не упасть.
        manager.removeFiles(for: item)
    }
}
