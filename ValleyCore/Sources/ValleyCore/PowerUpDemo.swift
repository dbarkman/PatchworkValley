/// Small fixed valleys that show each power-up the first time a player meets it: Undo in valley 2,
/// Wildcard in 3, Dynamite in 4 and Lantern in 5. Each is a little hand-built crater with a
/// starter tile and six designed tiles; it pays no coins and sets no quests. The app deals a fresh
/// real valley afterwards.
public enum PowerUpDemo {
    /// Power-ups that have a demo valley: undo, wildcard, dynamite, lantern (not swap; the first run shows Swap).
    public static let demoed: [PowerUp] = [.undo, .wildcard, .dynamite, .lantern]

    /// The demo valley for `powerUp` (one of `demoed`), the same every time.
    public static func makeGame(for powerUp: PowerUp) -> ValleyGame {
        guard let design = design(for: powerUp) else { preconditionFailure("No demo for \(powerUp)") }
        var rules = Rules.coins(valley: powerUp.unlockValley)
        rules.coinsPerMatch = 0
        rules.coinsPerPerfect = 0
        rules.questChance = 0
        rules.alwaysQuest = false
        rules.startingTiles = 6
        rules.allowsDiscard = false
        rules.requiresMatch = true
        let board = Board(starter: design.starter, crater: design.crater, requiresMatch: rules.requiresMatch)
        return ValleyGame(rules: rules, board: board, queue: design.stack, tilesLeft: rules.startingTiles)
    }

    /// Undo: the spot where the player places the first tile before taking it back.
    /// Dynamite: the spot where the app places the first tile for the player; placing it there uncovers a mountain.
    /// Wildcard, Lantern: nil.
    /// Nil too once the tile in hand no longer fits there.
    public static func spot(for powerUp: PowerUp, in game: ValleyGame) -> Hex? {
        guard let spot = design(for: powerUp)?.spot, let tile = game.current,
              game.board.bestRotation(for: tile, at: spot) != nil else { return nil }
        return spot
    }

    /// Dynamite: the floor mountain to blast once the first tile is down (nil for the others).
    /// Nil too once it has been blasted.
    public static func target(for powerUp: PowerUp, in game: ValleyGame) -> Hex? {
        guard let target = design(for: powerUp)?.target, game.board.mountains.contains(target) else { return nil }
        return target
    }

    /// A demo valley's layout and stack.
    private struct Design {
        let crater: Crater
        let starter: Tile
        /// The six tiles, in the order dealt.
        let stack: [Tile]
        var spot: Hex?
        var target: Hex?
    }

    /// Each demo's crater is the floor within 3 steps of the start, with a few bulges and bays so it
    /// looks like a real valley, ringed by a rim. Peaks and lakes stand 2 or more steps from the start,
    /// so they begin in the fog. The starter shows all four land terrains, like a real crater's, except
    /// in the Wildcard demo, where it has no village so the all-village tile in hand fits nowhere.
    private static func design(for powerUp: PowerUp) -> Design? {
        switch powerUp {
        case .swap:
            return nil
        case .undo:
            // A forest-and-field tile to place beside the starter's forest, then take back.
            return Design(
                crater: crater(
                    bulges: [Hex(4, -2), Hex(4, -1), Hex(3, 1), Hex(-1, 4), Hex(-2, 4)], bays: [Hex(-3, 0), Hex(0, -3)],
                    peaks: [Hex(2, -3), Hex(3, -3), Hex(-2, -1), Hex(-3, 1), Hex(1, 2)], lakes: [Hex(3, -1), Hex(-2, 3)]
                ),
                starter: tile("mmfccv", id: 0),
                stack: stack(["ffmmcc", "mmmvvf", "ccffff", "mmcccm", "fvvmmf", "cccmff"]),
                spot: Hex(0, -1)
            )
        case .wildcard:
            // An all-village tile, and the starter has no village at all, so it fits nowhere until it turns wild.
            return Design(
                crater: crater(
                    bulges: [Hex(-4, 1), Hex(-4, 2), Hex(-3, -1), Hex(1, 3), Hex(2, 2)], bays: [Hex(3, -3), Hex(3, 0)],
                    peaks: [Hex(2, -2), Hex(2, -3), Hex(-1, -2), Hex(-3, 3), Hex(0, 3), Hex(1, 2)], lakes: [Hex(-3, 1), Hex(3, -1)]
                ),
                starter: tile("ffccmm", id: 0),
                stack: stack(["vvvvvv", "mmffcc", "ccmmmf", "ffffmm", "mcccff", "fmmmcc"])
            )
        case .dynamite:
            // The first tile goes beside the starter's village, uncovering the end of a ridge.
            return Design(
                crater: crater(
                    bulges: [Hex(1, -4), Hex(2, -4), Hex(4, -1), Hex(-2, -2), Hex(-4, 3)], bays: [Hex(-3, 0), Hex(0, 3)],
                    peaks: [Hex(2, -1), Hex(3, -1), Hex(3, -2), Hex(-2, 2), Hex(-1, 3), Hex(0, -3)], lakes: [Hex(-2, 0), Hex(2, 1)]
                ),
                starter: tile("cvmmfc", id: 0),
                stack: stack(["vvvccm", "ccffmm", "mmmfff", "fccccm", "mmvvcc", "ffmmcc"]),
                spot: Hex(1, -1),
                target: Hex(2, -1)
            )
        case .lantern:
            // A river tile in hand: east of the starter, its river can flow into a lake the Lantern shows.
            return Design(
                crater: crater(
                    bulges: [Hex(-1, -3), Hex(-2, -2), Hex(4, -2), Hex(3, 1), Hex(-3, 4)], bays: [Hex(3, -3), Hex(-3, 1)],
                    peaks: [Hex(1, -3), Hex(2, -3), Hex(3, -1), Hex(-2, -1), Hex(-1, 3), Hex(-2, 3)], lakes: [Hex(2, -1), Hex(-2, 1)]
                ),
                starter: tile("mfccvm", id: 0),
                stack: stack(["cwmmmw", "ffmmcc", "mmcccv", "ccffmm", "fffmmc", "mmffvv"])
            )
        }
    }

    /// The floor within `radius` of the start, with `bulges` added and `bays` cut out, ringed by a rim.
    private static func crater(radius: Int = 3, bulges: [Hex], bays: [Hex], peaks: [Hex], lakes: [Hex]) -> Crater {
        let floor = Set(Hex.within(radius: radius)).union(bulges).subtracting(bays)
        let rim = Set(floor.flatMap(\.neighbors)).subtracting(floor)
        return Crater(radius: radius, floor: floor, rim: rim, peaks: Set(peaks), lakes: Set(lakes))
    }

    /// Designed tiles take ids from 101, so a tile the generator deals mid-demo (a swap or a
    /// wildcard, from id 1) never shares one.
    private static func stack(_ codes: [String]) -> [Tile] {
        codes.enumerated().map { tile($1, id: 101 + $0) }
    }

    /// A tile from one letter per edge, edge 0 first: m = meadow, f = forest, c = field (crops), v = village, w = water.
    private static func tile(_ code: String, id: Int) -> Tile {
        let terrains: [Character: Terrain] = ["m": .meadow, "f": .forest, "c": .field, "v": .village, "w": .water]
        return Tile(id: id, edges: code.map { terrains[$0]! })
    }
}
