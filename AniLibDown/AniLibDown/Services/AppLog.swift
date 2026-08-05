import Foundation
import os

enum AppLog {
    private static let subsystem = "top.aniliberty.AniLibDown"

    static let api = AppLogger(subsystem: subsystem, category: "api")
    static let player = AppLogger(subsystem: subsystem, category: "player")
    static let shikimori = AppLogger(subsystem: subsystem, category: "shikimori")
}

struct AppLogger {
    private let logger: Logger

    init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
