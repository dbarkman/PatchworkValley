/// Coin mode's power-ups. Each one is introduced by a valley and bought with coins.
public enum PowerUp: String, CaseIterable, Hashable, Sendable, Identifiable {
    /// Take back the last placement, and the coins it earned.
    case undo
    /// Trade the current tile for a freshly dealt one.
    case swap
    /// Turn the current tile into a wildcard that matches anything.
    case wildcard
    /// Blast a revealed mountain off the crater floor.
    case dynamite
    /// Lift the fog off every mountain in the crater.
    case lantern

    public var id: Self { self }

    public var price: Int {
        switch self {
        case .undo: 30
        case .swap: 40
        case .wildcard: 80
        case .dynamite: 60
        case .lantern: 50
        }
    }

    /// The valley that introduces this power-up; it stays available after.
    public var unlockValley: Int {
        switch self {
        case .undo: 1
        case .swap: 2
        case .wildcard: 3
        case .dynamite: 4
        case .lantern: 5
        }
    }

    public static func introduced(inValley valley: Int) -> PowerUp? {
        allCases.first { $0.unlockValley == valley }
    }
}

/// Coin mode's other numbers. A simple bot earns about 55–60 coins per valley
/// from quests and perfect fits (see `coinEconomyReport` in the tests), so with
/// the finishing bonus a valley pays for roughly one power-up.
public enum CoinEconomy {
    public static let startingWallet = 200
    /// Paid when the player moves on from a finished valley.
    public static let valleyBonus = 20
    /// "+3 tiles" when a valley runs out with a quest close.
    public static let continuePrice = 100
}
