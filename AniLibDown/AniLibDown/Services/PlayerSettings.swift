import Foundation

enum SeekInterval: Int, CaseIterable, Identifiable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    var id: Int { rawValue }

    var title: String { "\(rawValue) сек" }

    var seconds: Double { Double(rawValue) }
}

@MainActor
final class PlayerSettings: ObservableObject {
    static let shared = PlayerSettings()

    @Published var seekInterval: SeekInterval {
        didSet { UserDefaults.standard.set(seekInterval.rawValue, forKey: Keys.seekInterval) }
    }

    @Published var skipOPED: Bool {
        didSet { UserDefaults.standard.set(skipOPED, forKey: Keys.skipOPED) }
    }

    @Published var autoPlayNext: Bool {
        didSet { UserDefaults.standard.set(autoPlayNext, forKey: Keys.autoPlayNext) }
    }

    private enum Keys {
        static let seekInterval = "playerSeekInterval"
        static let skipOPED = "playerSkipOPED"
        static let autoPlayNext = "playerAutoPlayNext"
    }

    private init() {
        let storedInterval = UserDefaults.standard.integer(forKey: Keys.seekInterval)
        seekInterval = SeekInterval(rawValue: storedInterval) ?? .five

        if UserDefaults.standard.object(forKey: Keys.skipOPED) == nil {
            skipOPED = true
        } else {
            skipOPED = UserDefaults.standard.bool(forKey: Keys.skipOPED)
        }

        if UserDefaults.standard.object(forKey: Keys.autoPlayNext) == nil {
            autoPlayNext = true
        } else {
            autoPlayNext = UserDefaults.standard.bool(forKey: Keys.autoPlayNext)
        }
    }
}
