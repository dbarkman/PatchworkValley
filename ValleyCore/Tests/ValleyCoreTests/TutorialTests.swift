import Testing
@testable import ValleyCore

/// Builds a tile from one letter per edge, edge 0 first:
/// m = meadow, f = forest, c = field (crops), v = village, w = water.
private func tile(_ code: String, id: Int = 99, quest: QuestSpec? = nil) -> Tile {
    let terrains: [Character: Terrain] = ["m": .meadow, "f": .forest, "c": .field, "v": .village, "w": .water]
    return Tile(id: id, edges: code.map { terrains[$0]! }, quest: quest)
}

@Suite struct TutorialTests {
    /// The tutorial seed's opening, played the way the app coaches it, once for every check below.
    private static let audit = Tutorial.audit(seed: Tutorial.seed)

    /// `Tutorial.seed` meets every requirement. If a rule change breaks one, pick a new seed
    /// with the disabled `findTutorialSeed` design tool.
    @Test(arguments: Tutorial.Requirement.allCases)
    func theSeedMeets(_ requirement: Tutorial.Requirement) {
        #expect(Self.audit.met.contains(requirement), "\(Self.audit.problems)")
    }

    /// The app must coach the same spots on every launch, whatever order its sets iterate in.
    /// Each test run is a new process with a new hash seed, so a spot that depended on set
    /// order would drift away from these.
    @Test func theCoachedSpotsNeverMove() {
        #expect(Self.audit.spots == [.place: Hex(1, -1), .questTile: Hex(1, 0), .turn: Hex(2, -1), .finishQuest: Hex(2, 0)])
        #expect(Self.audit.coins == [.place: 1, .questTile: 2, .turn: 2, .finishQuest: 12])
    }

    @Test func makeGameDealsTheSameFirstValleyEveryTime() {
        var first = Tutorial.makeGame()
        var second = Tutorial.makeGame()
        #expect(first.rules.startingTiles == Rules.coins(valley: 1).startingTiles)
        #expect(first.tilesLeft == first.rules.startingTiles)
        #expect(first.current == second.current)
        #expect(first.next == second.next)
        #expect(first.activeQuests == second.activeQuests)
        #expect(first.board.mountains == second.board.mountains)
        #expect(first.board.lakes == second.board.lakes)
        #expect(first.board.floor == second.board.floor)
        let dealt = Tutorial.playOut(&first)
        #expect(dealt.count == first.rules.startingTiles)
        #expect(Array(dealt.prefix(8)) == Array(Tutorial.playOut(&second).prefix(8)))
    }

    /// The valley opens with no quest going and the second tile carrying a land quest of 3.
    @Test func theSecondTileBringsTheFirstQuest() throws {
        let game = Tutorial.makeGame()
        #expect(game.activeQuests.isEmpty)
        #expect(game.current?.quest == nil)
        let spec = try #require(game.next?.quest)
        #expect([Terrain.forest, .field, .village].contains(spec.terrain))
        #expect(spec.target == 3)
    }

    @Test func theGlimpseIsTheWholeValleyEveryTime() {
        let glimpse = Tutorial.glimpse()
        #expect(glimpse.tiles.count == Rules.coins(valley: 1).startingTiles + 1)
        #expect(Tutorial.glimpse().tiles == glimpse.tiles)
        #expect(Tutorial.glimpse(seed: Tutorial.seed).tiles == glimpse.tiles, "the cached glimpse is the tutorial valley's")
    }

    @Test func theChoiceStepHasNoSpot() {
        #expect(Tutorial.spot(for: .choice, in: Tutorial.makeGame()) == nil)
    }

    /// Turns count clockwise from the tile's current rotation, stopping at the first that fits.
    @Test func firstFittingTurnCountsClockwiseTurns() {
        // A river crosses the starter on edges 0 and 3; east of it, a tile's edge 3 must be a river.
        let board = Board(starter: tile("wmmwmm", id: 0))
        let east = Hex(1, 0)
        #expect(Tutorial.firstFittingTurn(for: tile("mmmmwm"), at: east, on: board) == 1)
        #expect(Tutorial.firstFittingTurn(for: tile("mwmmmm"), at: east, on: board) == 4)
        #expect(Tutorial.firstFittingTurn(for: tile("mmmwmm"), at: east, on: board) == nil, "it fits only as it is")
        #expect(Tutorial.firstFittingTurn(for: tile("mmmmmm"), at: east, on: board) == nil, "no river to meet the river")
    }

    /// Growing the quest beats matching more sides.
    @Test func thePlaceAndFinishSpotsGrowTheQuest() throws {
        // A forest quest east of a meadow starter, its only forest edge facing (2, 0).
        let questTile = tile("fmmmmm", id: 1, quest: QuestSpec(terrain: .forest, target: 3))
        var game = ValleyGame(board: Board(starter: tile("mmmmmm", id: 0)), queue: [questTile, tile("mmmfmm", id: 2)], tilesLeft: 5)
        let placed = game.placeCurrent(at: Hex(1, 0))
        try #require(placed != nil)
        try #require(game.activeQuests.count == 1)
        let current = try #require(game.current)
        // Between the starter and the quest tile, the tile matches two meadow sides but misses the forest.
        let between = Hex(1, -1)
        let steps = try #require(game.board.bestRotation(for: current, at: between))
        #expect(game.board.evaluate(current.rotatedClockwise(steps), at: between).matchingEdges.count == 2)
        #expect(Tutorial.spot(for: .place, in: game) == Hex(2, 0))
        #expect(Tutorial.spot(for: .finishQuest, in: game) == Hex(2, 0))
    }

    /// Starting the quest alone, so it asks for the number on its tag, beats matching more sides.
    @Test func theQuestTileSpotStartsTheQuestAlone() throws {
        // A forest starter ringed by a meadow tile to the east. The quest tile's only forest side
        // joins the starter's forest wherever it touches the starter, so the coach puts it beyond
        // the meadow tile, touching only that.
        var board = Board(starter: tile("ffffff", id: 0))
        board.place(tile("mmmfmm", id: 1), at: Hex(1, 0))
        let questTile = tile("fmmmmm", id: 2, quest: QuestSpec(terrain: .forest, target: 3))
        let game = ValleyGame(board: board, queue: [questTile], tilesLeft: 5)
        let spot = try #require(Tutorial.spot(for: .questTile, in: game))
        #expect(spot.distance(to: .origin) == 2)
        let steps = try #require(board.bestRotation(for: questTile, at: spot))
        #expect(board.region(of: .forest, from: spot, placing: questTile.rotatedClockwise(steps)).count == 1)

        var played = game
        played.rotateCurrent(clockwiseSteps: steps)
        let placed = played.placeCurrent(at: spot)
        try #require(placed != nil)
        #expect(played.activeQuests.map(\.target) == [3])
    }

    @Test func theQuestTileStepIsSkippedWithoutAQuestInHand() {
        let game = ValleyGame(board: Board(starter: tile("mmmmmm", id: 0)), queue: [tile("mmmmmm", id: 1)], tilesLeft: 5)
        #expect(Tutorial.spot(for: .questTile, in: game) == nil)
    }

    @Test func theTurnStepIsSkippedWhenTheTileFitsEverywhereAsDealt() {
        let game = ValleyGame(board: Board(starter: tile("mmmmmm", id: 0)), queue: [tile("mmmmmm", id: 1)], tilesLeft: 5)
        #expect(Tutorial.spot(for: .turn, in: game) == nil)
        #expect(Tutorial.spot(for: .place, in: game) != nil)
    }

    /// Across many valleys: the place and quest-tile spots fit, and the turn spot needs a turn, the fewest available.
    @Test(arguments: 1...12)
    func spotsFollowTheirRules(seed: UInt64) throws {
        let game = ValleyGame(seed: seed, rules: .coins(valley: 1))
        let current = try #require(game.current)
        let board = game.board
        if let spot = Tutorial.spot(for: .place, in: game) {
            #expect(board.bestRotation(for: current, at: spot) != nil)
        } else {
            #expect(!board.hasLegalPlacement(for: current))
        }
        if let spot = Tutorial.spot(for: .questTile, in: game) {
            #expect(current.quest != nil)
            #expect(board.bestRotation(for: current, at: spot) != nil)
        } else {
            #expect(current.quest == nil || !board.hasLegalPlacement(for: current))
        }
        let turns = board.openSlots
            .filter { !board.canPlace(current, at: $0) }
            .compactMap { Tutorial.firstFittingTurn(for: current, at: $0, on: board) }
        if let spot = Tutorial.spot(for: .turn, in: game) {
            #expect(!board.canPlace(current, at: spot))
            #expect(Tutorial.firstFittingTurn(for: current, at: spot, on: board) == turns.min())
        } else {
            #expect(turns.isEmpty)
        }
    }
}
