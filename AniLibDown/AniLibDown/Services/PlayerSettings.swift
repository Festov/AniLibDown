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

enum HoldSpeedRate: Float, CaseIterable, Identifiable {
    case x1_5 = 1.5
    case x2 = 2.0

    var id: Float { rawValue }

    var title: String {
        if rawValue.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rawValue))×"
        }
        return String(format: "%.1f×", rawValue).replacingOccurrences(of: ".", with: ",")
    }

    static func migrated(from stored: Double) -> HoldSpeedRate {
        guard stored > 0 else { return .x2 }
        if abs(stored - Double(HoldSpeedRate.x1_5.rawValue)) < 0.01 { return .x1_5 }
        return .x2
    }
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

    @Published var holdSpeedRate: HoldSpeedRate {
        didSet { UserDefaults.standard.set(Double(holdSpeedRate.rawValue), forKey: Keys.holdSpeedRate) }
    }

    private enum Keys {
        static let seekInterval = "playerSeekInterval"
        static let skipOPED = "playerSkipOPED"
        static let autoPlayNext = "playerAutoPlayNext"
        static let holdSpeedRate = "playerHoldSpeedRate"
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

        let storedSpeed = UserDefaults.standard.double(forKey: Keys.holdSpeedRate)
        holdSpeedRate = HoldSpeedRate.migrated(from: storedSpeed)
    }
}
