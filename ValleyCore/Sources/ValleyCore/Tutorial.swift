/// The first-run tutorial's valley: a fixed valley-1 deal whose opening teaches placing a tile,
/// turning one to match, and finishing a quest, before the player takes over.
public enum Tutorial {
    /// The coached steps, in order.
    public enum Step: Int, CaseIterable, Sendable { case place, turn, quest, choice }

    /// The valley-1 seed whose opening fits the steps (pinned by TutorialTests).
    public static let seed: UInt64 = 120_854

    /// The tutorial valley: `ValleyGame(seed: seed, rules: .coins(valley: 1))`, the same every time.
    public static func makeGame() -> ValleyGame { makeGame(seed: seed) }

    /// The spot to coach for `step` in `game`, or nil when the step has none (the coach then skips it).
    /// .place and .quest: an open slot where the current tile fits in some rotation, preferring one where its
    ///   best rotation (Board.bestRotation) grows an active quest's region, then more matched sides, then (r, q) order.
    /// .turn: an open slot where the current tile as dealt does NOT fit but a clockwise turn does, preferring the
    ///   fewest turns (see firstFittingTurn), then growing an active quest, then more matched sides, then (r, q) order.
    /// .choice: always nil (the player picks any fitting spot).
    public static func spot(for step: Step, in game: ValleyGame) -> Hex? {
        guard step != .choice, let tile = game.current else { return nil }
        let board = game.board
        var best: (hex: Hex, rank: (fewerTurns: Int, growsQuest: Int, matches: Int))?
        // Sets iterate in a different order every launch; sort so the app coaches the same spot as the tests.
        for hex in board.openSlots.sorted(by: { ($0.r, $0.q) < ($1.r, $1.q) }) {
            let steps: Int
            var fewerTurns = 0
            if step == .turn {
                guard !board.canPlace(tile, at: hex), let turns = firstFittingTurn(for: tile, at: hex, on: board) else { continue }
                steps = turns
                fewerTurns = -turns
            } else {
                guard let rotation = board.bestRotation(for: tile, at: hex) else { continue }
                steps = rotation
            }
            let placed = tile.rotatedClockwise(steps)
            let rank = (
                fewerTurns: fewerTurns,
                growsQuest: growsAQuest(placed, at: hex, in: game) ? 1 : 0,
                matches: board.evaluate(placed, at: hex).matchingEdges.count
            )
            // Only a strictly better spot replaces the best so far, so ties go to the first in (r, q) order.
            if best.map({ rank > $0.rank }) ?? true { best = (hex, rank) }
        }
        return best?.hex
    }

    /// Clockwise turns (1...5) from the tile's current rotation to the first rotation that fits at `hex`,
    /// which is what tapping the ghost does in the app; nil when no turn fits.
    public static func firstFittingTurn(for tile: Tile, at hex: Hex, on board: Board) -> Int? {
        (1...5).first { board.canPlace(tile.rotatedClockwise($0), at: hex) }
    }

    /// The tutorial valley played to the end by GreedyBot (focusing the active quests' terrains), for the
    /// opening glimpse of a finished valley. Computed once and cached.
    public static func glimpse() -> Board { finishedValley }

    private static let finishedValley = glimpse(seed: seed)

    static func makeGame(seed: UInt64) -> ValleyGame {
        ValleyGame(seed: seed, rules: .coins(valley: 1))
    }

    /// `seed`'s valley played to the end by GreedyBot.
    static func glimpse(seed: UInt64) -> Board {
        var game = makeGame(seed: seed)
        playOut(&game)
        return game.board
    }

    /// Plays `game` to the end with GreedyBot, focusing the active quests' terrains at each move,
    /// and returns the tiles it was dealt, in order and as dealt.
    @discardableResult
    static func playOut(_ game: inout ValleyGame) -> [Tile] {
        var dealt: [Tile] = []
        while !game.isOver, let tile = game.current,
              let move = GreedyBot.bestMove(in: game, focus: game.activeQuests.map(\.terrain)) {
            dealt.append(tile)
            game.rotateCurrent(clockwiseSteps: move.steps)
            game.placeCurrent(at: move.slot)
        }
        return dealt
    }

    /// Whether `tile`, placed at `hex` as it is, joins the region of an active quest.
    private static func growsAQuest(_ tile: Tile, at hex: Hex, in game: ValleyGame) -> Bool {
        game.activeQuests.contains { game.board.region(of: $0.terrain, from: hex, placing: tile).contains($0.anchor) }
    }
}

// MARK: - Choosing the seed

extension Tutorial {
    /// What a seed's valley must do for the tutorial to work. `audit(seed:)` checks each one.
    enum Requirement: Int, CaseIterable, Sendable {
        /// The seed deals the same valley every time.
        case sameDeal = 1
        /// The valley opens with one board quest to grow a land region by 3, no quest on the
        /// first four tiles, and no river on the first three.
        case opening
        /// Placing at the .place spot, in its best rotation, pays 1 coin and leaves the quest 2 to go.
        case place
        /// The .turn spot takes one turn, then pays 2 coins and leaves the quest 1 to go.
        case turn
        /// Placing at the .quest spot, in its best rotation, finishes the quest.
        case quest
        /// The fourth tile fits in at least 3 spots.
        case choice
        /// Wherever the fourth tile goes, the bot plays the rest of the stack without running out of room.
        case everyChoiceFinishes
        /// The glimpse holds the whole stack and the starter.
        case glimpse
    }

    /// One requirement a seed misses, and why.
    struct Problem: Hashable, Sendable, CustomStringConvertible {
        let requirement: Requirement
        let reason: String

        var description: String { "requirement \(requirement): \(reason)" }
    }

    /// How a seed's opening plays when the app coaches it.
    struct Audit: Sendable {
        /// The spot coached at each step that has one.
        var spots: [Step: Hex] = [:]
        /// Requirements the seed meets.
        var met: Set<Requirement> = []
        /// Why the seed misses the requirements it does. A coached step that fails stops the walk,
        /// so the requirements after it are neither met nor listed here.
        var problems: [Problem] = []

        var passes: Bool { met.count == Requirement.allCases.count }
    }

    /// Plays `seed`'s tutorial valley the way the app coaches it and checks every requirement.
    /// TutorialTests and the `findTutorialSeed` design tool both use it. With `stopAtFirst`, it
    /// returns at the first problem, for a quick search.
    static func audit(seed: UInt64, stopAtFirst: Bool = false) -> Audit {
        var audit = Audit()
        if let problem = walkOpening(seed: seed, into: &audit) {
            audit.problems.append(problem)
            if stopAtFirst { return audit }
        }

        let room = Rules.coins(valley: 1).startingTiles + 1
        let placed = glimpse(seed: seed).tiles.count
        if placed == room {
            audit.met.insert(.glimpse)
        } else {
            audit.problems.append(Problem(requirement: .glimpse, reason: "the bot placed \(placed) of \(room) tiles"))
            if stopAtFirst { return audit }
        }

        if dealsAlike(seed: seed) {
            audit.met.insert(.sameDeal)
        } else {
            audit.problems.append(Problem(requirement: .sameDeal, reason: "two games from the seed differ"))
        }
        return audit
    }

    /// Walks the coached opening step by step, as the app plays it, recording each coached spot
    /// and each requirement met, and returns the first problem.
    private static func walkOpening(seed: UInt64, into audit: inout Audit) -> Problem? {
        func problem(_ requirement: Requirement, _ reason: String) -> Problem {
            Problem(requirement: requirement, reason: reason)
        }
        /// Tiles 1–4 carry no quest, and tiles 1–3 no river, so the opening stays simple.
        func quietTile(_ number: Int, in game: ValleyGame) -> Problem? {
            guard let tile = game.current else { return problem(.opening, "no tile \(number)") }
            if tile.quest != nil { return problem(.opening, "tile \(number) carries a quest") }
            if number <= 3 && tile.edges.contains(.water) { return problem(.opening, "tile \(number) has a river") }
            return nil
        }
        func remaining(of quest: Quest, in game: ValleyGame) -> Int? {
            game.quests.first { $0.id == quest.id && $0.status == .active }?.remaining
        }

        var game = makeGame(seed: seed)
        let active = game.activeQuests
        guard active.count == 1, let quest = active.first else { return problem(.opening, "\(active.count) active quests") }
        guard quest.id < 0 else { return problem(.opening, "the quest rides on a tile, not the board") }
        guard quest.terrain != .water else { return problem(.opening, "the quest is a river quest") }
        guard quest.remaining == 3 else { return problem(.opening, "the quest asks for \(quest.remaining) tiles") }

        // Place: the app turns the tile to its best rotation and places it.
        if let found = quietTile(1, in: game) { return found }
        guard let placeSpot = spot(for: .place, in: game), let placeSteps = game.current.flatMap({ game.board.bestRotation(for: $0, at: placeSpot) }) else {
            return problem(.place, "no spot")
        }
        audit.spots[.place] = placeSpot
        game.rotateCurrent(clockwiseSteps: placeSteps)
        guard let placed = game.placeCurrent(at: placeSpot) else { return problem(.place, "placing failed") }
        guard placed.coins == 1 else { return problem(.place, "pays \(placed.coins) coins") }
        guard remaining(of: quest, in: game) == 2 else { return problem(.place, "the quest isn't 2 to go") }
        audit.met.insert(.place)

        // Turn: the ghost is illegal as dealt; tapping it turns the tile to the first rotation that fits.
        if let found = quietTile(2, in: game) { return found }
        guard let turnSpot = spot(for: .turn, in: game), let tile = game.current,
              let turns = firstFittingTurn(for: tile, at: turnSpot, on: game.board) else {
            return problem(.turn, "no spot")
        }
        audit.spots[.turn] = turnSpot
        guard turns == 1 else { return problem(.turn, "takes \(turns) turns") }
        game.rotateCurrent(clockwiseSteps: turns)
        guard let turned = game.placeCurrent(at: turnSpot) else { return problem(.turn, "placing failed") }
        guard turned.coins == 2 else { return problem(.turn, "pays \(turned.coins) coins") }
        guard remaining(of: quest, in: game) == 1 else { return problem(.turn, "the quest isn't 1 to go") }
        audit.met.insert(.turn)

        // Quest: like Place, and the tile finishes the quest.
        if let found = quietTile(3, in: game) { return found }
        guard let questSpot = spot(for: .quest, in: game), let questSteps = game.current.flatMap({ game.board.bestRotation(for: $0, at: questSpot) }) else {
            return problem(.quest, "no spot")
        }
        audit.spots[.quest] = questSpot
        game.rotateCurrent(clockwiseSteps: questSteps)
        guard let finished = game.placeCurrent(at: questSpot) else { return problem(.quest, "placing failed") }
        guard finished.completedQuests.count == 1 else { return problem(.quest, "completes \(finished.completedQuests.count) quests") }
        audit.met.insert(.quest)

        // Choice: the player places the fourth tile anywhere it fits, and the valley must stay finishable.
        if let found = quietTile(4, in: game) { return found }
        audit.met.insert(.opening)
        guard let fourth = game.current else { return problem(.choice, "no fourth tile") }
        let choices = game.board.openSlots.sorted { ($0.r, $0.q) < ($1.r, $1.q) }.compactMap { hex in
            game.board.bestRotation(for: fourth, at: hex).map { (hex: hex, steps: $0) }
        }
        guard choices.count >= 3 else { return problem(.choice, "fits in \(choices.count) spots") }
        audit.met.insert(.choice)

        for choice in choices {
            var played = game
            played.rotateCurrent(clockwiseSteps: choice.steps)
            played.placeCurrent(at: choice.hex)
            playOut(&played)
            guard played.outcome == .outOfTiles, played.tilesLeft == 0 else {
                return problem(.everyChoiceFinishes, "out of room with \(played.tilesLeft) tiles left after choosing \(choice.hex)")
            }
        }
        audit.met.insert(.everyChoiceFinishes)
        return nil
    }

    /// Two games from `seed` start alike and deal the same tiles, in the same order, when played the same way.
    private static func dealsAlike(seed: UInt64) -> Bool {
        var first = makeGame(seed: seed)
        var second = makeGame(seed: seed)
        guard first.current == second.current, first.next == second.next,
              first.activeQuests == second.activeQuests,
              first.board.tiles == second.board.tiles,
              first.board.mountains == second.board.mountains,
              first.board.lakes == second.board.lakes,
              first.board.floor == second.board.floor else { return false }
        return playOut(&first) == playOut(&second) && first.board.tiles == second.board.tiles
    }
}
