/// Everything needed to play one level. The same number always builds the same level.
public struct LevelSpec: Hashable, Sendable {
    public let number: Int
    public let seed: UInt64
    public let tiles: Int
    public let goals: [Goal]
}

/// The hand-designed levels. Each level's goals add up to half its stack, and each
/// level's tile order (its seed) was chosen with `searchSeed` so the bot wins it:
/// comfortably early on, and only just by level 5.
public enum LevelDesigner {
    public static let levels: [LevelSpec] = [
        LevelSpec(number: 1, seed: 9, tiles: 12, goals: [Goal(terrain: .field, target: 6)]),
        LevelSpec(number: 2, seed: 1, tiles: 18, goals: [Goal(terrain: .forest, target: 9)]),
        LevelSpec(number: 3, seed: 7, tiles: 24, goals: [Goal(terrain: .forest, target: 6), Goal(terrain: .field, target: 6)]),
        LevelSpec(number: 4, seed: 9, tiles: 30, goals: [
            Goal(terrain: .forest, target: 5), Goal(terrain: .field, target: 5), Goal(terrain: .village, target: 5),
        ]),
        LevelSpec(number: 5, seed: 13, tiles: 36, goals: [
            Goal(terrain: .forest, target: 6), Goal(terrain: .field, target: 5),
            Goal(terrain: .village, target: 4), Goal(terrain: .water, target: 3),
        ]),
    ]

    public static var levelCount: Int { levels.count }

    public static func level(_ number: Int) -> LevelSpec {
        precondition(levels.indices.contains(number - 1), "No level \(number)")
        return levels[number - 1]
    }

    /// Tiles the bot has left when it wins `spec`, or nil when it can't win.
    static func botSpare(for spec: LevelSpec) -> Int? {
        var game = ValleyGame(level: spec)
        GreedyBot.play(&game, focus: spec.goals.map(\.terrain))
        return game.outcome == .won ? game.tilesLeft : nil
    }

    /// Finds the first seed from `start` whose tile order the bot wins with a spare-tile count in `spare`.
    /// Used by hand when designing levels; see `LevelSeedSearch` in the tests.
    static func searchSeed(tiles: Int, goals: [Goal], spare: ClosedRange<Int>, start: UInt64 = 1, attempts: Int = 5000) -> UInt64? {
        for seed in start..<(start + UInt64(attempts)) {
            let spec = LevelSpec(number: 0, seed: seed, tiles: tiles, goals: goals)
            if let left = botSpare(for: spec), spare.contains(left) { return seed }
        }
        return nil
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

    /// The move that grows focus regions most (the first focus terrain most of all), with matching edges as the tiebreaker.
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
                for (index, terrain) in focus.enumerated() where turned.contains(terrain) {
                    // The first focus terrain is the main goal, so it counts double.
                    let weight = index == 0 ? 8 : 4
                    value += weight * game.board.region(of: terrain, from: slot, placing: turned).count
                }
                if value > (best?.value ?? -1) {
                    best = (slot, steps, value)
                }
            }
        }
        return best.map { ($0.slot, $0.steps) }
    }
}
