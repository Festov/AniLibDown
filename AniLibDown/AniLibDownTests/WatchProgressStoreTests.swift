import XCTest
@testable import AniLibDown

@MainActor
final class WatchProgressStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: WatchProgressStore!
    private var tempDir: URL!
    private let suiteName = "AniLibDown.WatchProgressStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        // Большой debounce: в тестах запись на диск управляется явным flush().
        store = WatchProgressStore(defaults: defaults, directory: tempDir, debounce: 3600)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
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

    func testStateSurvivesNewInstance() {
        store.save(position: 42, episodeId: "ep-1", releaseId: 10)
        store.save(position: 77, episodeId: "ep-2", releaseId: 11)
        store.flush()

        let reloaded = WatchProgressStore(defaults: defaults, directory: tempDir, debounce: 3600)
        XCTAssertEqual(reloaded.position(for: "ep-1"), 42)
        XCTAssertEqual(reloaded.position(for: "ep-2"), 77)
        XCTAssertEqual(reloaded.lastEpisodeId(for: 10), "ep-1")
        XCTAssertEqual(reloaded.lastEpisodeId(for: 11), "ep-2")
    }

    func testClearAllPersistsEmptyState() {
        store.save(position: 42, episodeId: "ep-1", releaseId: 10)
        store.flush()
        store.clearAll()

        let reloaded = WatchProgressStore(defaults: defaults, directory: tempDir, debounce: 3600)
        XCTAssertNil(reloaded.position(for: "ep-1"))
        XCTAssertNil(reloaded.lastEpisodeId(for: 10))
    }

    func testMigratesFromUserDefaults() {
        let progress = ["ep-1": WatchProgress(episodeId: "ep-1", position: 33, updatedAt: Date())]
        let progressData = try! JSONEncoder().encode(progress)
        defaults.set(progressData, forKey: "watchProgressByEpisode")
        defaults.set(["10": "ep-1"], forKey: "lastWatchedEpisodeByRelease")

        let migrated = WatchProgressStore(defaults: defaults, directory: tempDir, debounce: 3600)
        XCTAssertEqual(migrated.position(for: "ep-1"), 33)
        XCTAssertEqual(migrated.lastEpisodeId(for: 10), "ep-1")

        // Устаревшие ключи удалены, данные сразу зафиксированы в файле.
        XCTAssertNil(defaults.data(forKey: "watchProgressByEpisode"))
        XCTAssertNil(defaults.dictionary(forKey: "lastWatchedEpisodeByRelease"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("watch-progress.json").path
        ))

        // Файл читается новым экземпляром.
        let reloaded = WatchProgressStore(defaults: defaults, directory: tempDir, debounce: 3600)
        XCTAssertEqual(reloaded.position(for: "ep-1"), 33)
    }

    func testCorruptedFileIsBackedUpAndReset() {
        let fileURL = tempDir.appendingPathComponent("watch-progress.json")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try! Data("not a json".utf8).write(to: fileURL)

        let recovered = WatchProgressStore(defaults: defaults, directory: tempDir, debounce: 3600)
        XCTAssertNil(recovered.position(for: "ep-1"))

        let files = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        XCTAssertFalse(files.contains("watch-progress.json"), "повреждённый файл должен быть перемещён")
        XCTAssertTrue(files.contains { $0.hasPrefix("watch-progress.corrupted-") }, "должна остаться резервная копия")
    }

    func testFlushWritesFileAfterSave() {
        let fileURL = tempDir.appendingPathComponent("watch-progress.json")
        store.save(position: 42, episodeId: "ep-1", releaseId: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "с большим debounce файл не должен появляться до flush()")

        store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
