/// Everything needed to play one level. The same number always builds the same level.
public struct LevelSpec: Hashable, Sendable {
    public let number: Int
    public let seed: UInt64
    public let tiles: Int
    public let goals: [Goal]
}

/// Builds levels from their number, no hand design. A bot plays each level's
/// exact tile stream first, and goals are set to a share of what it reached,
/// so every level is beatable.
public enum LevelDesigner {
    /// Tile stacks run 12, 18, 24, 30, 36 and repeat: always a multiple of six, one per side of a hex.
    public static func tileBudget(for level: Int) -> Int {
        12 + 6 * ((level - 1) % 5)
    }

    /// Share of the bot's best the player must reach. Rises with each cycle of five
    /// levels, and the 36-tile level that closes each cycle is harder still. The bot
    /// plays greedily, so asking for all of its best is still fair.
    static func difficulty(for level: Int) -> Double {
        let cycle = Double((level - 1) / 5)
        let finale = (level - 1) % 5 == 4 ? 0.1 : 0
        return min(1, 0.75 + 0.05 * cycle + finale)
    }

    static func goalCount(level: Int, tiles: Int) -> Int {
        switch tiles {
        case ...18: 1
        case ...30: 2
        default: level > 10 ? 3 : 2
        }
    }

    /// The smallest goal worth asking for.
    static let minimumTarget = 4

    public static func level(_ number: Int) -> LevelSpec {
        precondition(number >= 1, "Levels start at 1")
        let seed = 0x5EED_0000 &+ UInt64(number) &* 0x9E37_79B9_7F4A_7C15
        let tiles = tileBudget(for: number)
        let difficulty = difficulty(for: number)
        // Rivers are scarce, so river goals wait until players know the game.
        let candidates: [Terrain] = number >= 8 ? [.forest, .field, .village, .water] : [.forest, .field, .village]
        var rng = SplitMix64(seed: seed ^ 0xA5A5_A5A5)

        // How big each terrain grows on this level's tiles when it is the bot's only focus.
        let soloReach = Dictionary(uniqueKeysWithValues: candidates.map { terrain in
            (terrain, GreedyBot.bestRegions(seed: seed, tiles: tiles, focus: [terrain])[terrain, default: 0])
        })
        // Only terrains that can grow to a quarter of the stack make interesting goals.
        let floor = max(minimumTarget, tiles / 4)
        var viable = candidates.filter { soloReach[$0, default: 0] >= floor }.shuffled(using: &rng)
        if viable.isEmpty, let best = candidates.max(by: { soloReach[$0, default: 0] < soloReach[$1, default: 0] }) {
            viable = [best]
        }
        var terrains = Array(viable.prefix(goalCount(level: number, tiles: tiles)))

        // Goals share one stack of tiles, so measure them together and drop any that can't hold its own.
        while true {
            let reached = GreedyBot.bestRegions(seed: seed, tiles: tiles, focus: terrains)
            let weak = terrains.filter { reached[$0, default: 0] < minimumTarget }
            if weak.isEmpty || terrains.count == 1 {
                let goals = terrains.map { terrain in
                    let best = reached[terrain, default: 0]
                    let target = min(best, max(minimumTarget, Int(Double(best) * difficulty)))
                    return Goal(terrain: terrain, target: max(1, target))
                }
                return LevelSpec(number: number, seed: seed, tiles: tiles, goals: goals)
            }
            terrains.removeAll { weak.contains($0) }
        }
    }
}

/// A simple player that grows the regions it cares about. Levels use it to set
/// fair goals, and tests use it to prove levels can be beaten.
public enum GreedyBot {
    /// Plays a level's tile stream to the end and returns the largest region reached per focus terrain.
    static func bestRegions(seed: UInt64, tiles: Int, focus: [Terrain]) -> [Terrain: Int] {
        var rules = Rules.levels
        rules.startingTiles = tiles
        var game = ValleyGame(seed: seed, rules: rules)
        play(&game, focus: focus)
        return Dictionary(uniqueKeysWithValues: focus.map { ($0, game.board.largestRegion(of: $0).count) })
    }

    /// Plays until the run is over, discarding tiles that fit nowhere.
    public static func play(_ game: inout ValleyGame, focus: [Terrain]) {
        while !game.isOver {
            guard let move = bestMove(in: game, focus: focus) else {
                game.discardCurrent()
                continue
            }
            game.rotateCurrent(clockwiseSteps: move.steps)
            game.placeCurrent(at: move.slot)
        }
    }

    /// The move that grows focus regions most, with matching edges as the tiebreaker.
    public static func bestMove(in game: ValleyGame, focus: [Terrain]) -> (slot: Hex, steps: Int)? {
        guard let tile = game.current else { return nil }
        var best: (slot: Hex, steps: Int, value: Int)?
        // Sets iterate in a different order every launch; sort so the same level always plays the same way.
        for slot in game.board.openSlots.sorted(by: { ($0.r, $0.q) < ($1.r, $1.q) }) {
            for steps in 0..<6 {
                let turned = tile.rotatedClockwise(steps)
                let evaluation = game.board.evaluate(turned, at: slot)
                guard evaluation.isLegal else { continue }
                var value = evaluation.matchingEdges.count
                for terrain in focus where turned.contains(terrain) {
                    value += 4 * game.board.region(of: terrain, from: slot, placing: turned).count
                }
                if value > (best?.value ?? -1) {
                    best = (slot, steps, value)
                }
            }
        }
        return best.map { ($0.slot, $0.steps) }
    }
}
