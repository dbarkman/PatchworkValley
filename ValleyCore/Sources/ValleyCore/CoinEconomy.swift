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
    /// Light every mountain and lake in the crater for one turn; the fog returns after the next tile.
    case lantern

    public var id: Self { self }

    public var price: Int {
        switch self {
        case .undo: 50
        case .swap: 100
        case .wildcard: 150
        case .dynamite: 200
        case .lantern: 300
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

/// Coin mode's other numbers. A planning bot earns about 80–100 coins per valley,
/// finishing bonus included, from matched sides, quests and perfect fits (see
/// `coinEconomyReport` in the tests): about one Swap a valley, and a Lantern takes three.
public enum CoinEconomy {
    public static let startingWallet = 500
    /// Paid the moment a valley's stack is used up.
    public static let valleyBonus = 20
    /// "+3 tiles" when a valley runs out with a quest close.
    public static let continuePrice = 250
}
