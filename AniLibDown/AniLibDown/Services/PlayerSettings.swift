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
    case x2 = 2
    case x2_5 = 2.5
    case x3 = 3
    case x3_5 = 3.5
    case x4 = 4
    case x4_5 = 4.5
    case x5 = 5

    var id: Float { rawValue }

    var title: String {
        if rawValue.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rawValue))×"
        }
        return String(format: "%.1f×", rawValue).replacingOccurrences(of: ".", with: ",")
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
        if storedSpeed > 0,
           let rate = HoldSpeedRate.allCases.first(where: { abs(Double($0.rawValue) - storedSpeed) < 0.01 }) {
            holdSpeedRate = rate
        } else {
            holdSpeedRate = .x2
        }
    }
}
