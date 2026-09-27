import Testing
@testable import ValleyCore

/// Builds a tile from one letter per edge, edge 0 first:
/// m = meadow, f = forest, c = field (crops), v = village, w = water.
private func tile(_ code: String, id: Int = 99, quest: QuestSpec? = nil) -> Tile {
    let terrains: [Character: Terrain] = ["m": .meadow, "f": .forest, "c": .field, "v": .village, "w": .water]
    return Tile(id: id, edges: code.map { terrains[$0]! }, quest: quest)
}

/// East of the origin. Its edge 3 faces the origin tile's edge 0.
private let east = Hex(1, 0)

@Suite struct HexTests {
    @Test func oppositeDirectionsCancel() {
        for direction in 0..<6 {
            #expect(Hex.origin.neighbor(direction).neighbor(Hex.opposite(direction)) == .origin)
        }
    }

    @Test func wrapHandlesNegativeDirections() {
        #expect(Hex.wrap(-1) == 5)
        #expect(Hex.wrap(7) == 1)
    }
}

@Suite struct TileTests {
    @Test func clockwiseRotationMovesEachEdgeOneDirectionBack() {
        let rotated = tile("fmmmmm").rotatedClockwise()
        #expect(rotated.edges == tile("mmmmmf").edges)
    }

    @Test func sixTurnsIsIdentityAndNegativeStepsUndo() {
        let original = tile("fcvmwm")
        #expect(original.rotatedClockwise(6) == original)
        #expect(original.rotatedClockwise(2).rotatedClockwise(-2) == original)
    }
}

@Suite struct BoardTests {
    @Test func placementMustTouchTheValley() {
        let board = Board(starter: tile("mmmmmm", id: 0))
        #expect(board.canPlace(tile("mmmmmm"), at: east))
        #expect(!board.canPlace(tile("mmmmmm"), at: Hex(5, 5)))
        #expect(!board.canPlace(tile("mmmmmm"), at: .origin))
    }

    @Test func riversMustMeetRivers() {
        let dry = Board(starter: tile("mmmmmm", id: 0))
        #expect(!dry.canPlace(tile("mmmwmm"), at: east))

        let wet = Board(starter: tile("wmmwmm", id: 0))
        #expect(wet.canPlace(tile("mmmwmw"), at: east))
        #expect(!wet.canPlace(tile("mmmmmm"), at: east))
    }

    @Test func evaluationCountsMatchingAndClashingEdges() {
        var board = Board(starter: tile("ffffff", id: 0))
        board.place(tile("cccccc", id: 1), at: Hex(1, -1))
        // At east: edge 3 faces the forest origin, edge 2 faces the field tile at (1, -1).
        let evaluation = board.evaluate(tile("mmffmm"), at: east)
        #expect(evaluation.isLegal)
        #expect(evaluation.matchingEdges == [3])
        #expect(evaluation.clashingEdges == [2])
        #expect(!evaluation.isPerfect)
    }

    @Test func perfectNeedsSixMatchingNeighbors() {
        let board = boardWithHole(around: east)
        #expect(board.evaluate(tile("mmmmmm"), at: east).isPerfect)
        #expect(!board.evaluate(tile("fmmmmm"), at: east).isPerfect)
    }

    @Test func bestRotationPicksTheMostMatches() {
        let board = Board(starter: tile("ffffff", id: 0))
        // Only edge 0 is forest; it has to turn to face west (direction 3) toward the origin.
        let steps = board.bestRotation(for: tile("fmmmmm"), at: east)
        #expect(steps.map { tile("fmmmmm").rotatedClockwise($0).edge(3) } == .forest)
    }

    @Test func bestRotationIsNilWhenNothingFits() {
        let board = Board(starter: tile("mmmmmm", id: 0))
        #expect(board.bestRotation(for: tile("wwwwww"), at: east) == nil)
    }

    @Test func regionFollowsMatchingEdgesOnly() {
        var board = Board(starter: tile("ffffff", id: 0))
        board.place(tile("mmmfmm", id: 1), at: east)            // forest faces the origin
        board.place(tile("mmmmmm", id: 2), at: Hex(-1, 0))      // meadow faces the origin
        #expect(board.region(of: .forest, from: .origin) == [.origin, east])
    }

    @Test func closedRegionHasNoOpenEdges() {
        var board = Board(starter: tile("mmmmmm", id: 0))
        board.place(tile("mmmfmm", id: 1), at: east)
        let region = board.region(of: .forest, from: east)
        #expect(region == [east])
        #expect(board.openEdgeCount(of: region, terrain: .forest) == 0)
    }

    /// Meadow tiles on all six sides of `hole`.
    private func boardWithHole(around hole: Hex) -> Board {
        var board = Board(starter: tile("mmmmmm", id: 0))
        for (index, hex) in hole.neighbors.enumerated() where board[hex] == nil {
            board.place(tile("mmmmmm", id: 10 + index), at: hex)
        }
        return board
    }
}

@Suite struct GameTests {
    @Test func newGameShowsCurrentAndNextTile() {
        let game = ValleyGame(seed: 42)
        #expect(game.tilesLeft == game.rules.startingTiles)
        #expect(game.current != nil)
        #expect(game.next != nil)
        #expect(game.current?.id != game.next?.id)
    }

    @Test func illegalPlacementChangesNothing() {
        var game = ValleyGame(board: Board(starter: tile("mmmmmm", id: 0)), queue: [tile("mmmwmm")], tilesLeft: 3)
        let placed = game.placeCurrent(at: east)
        #expect(placed == nil)
        #expect(game.tilesLeft == 3)
        #expect(game.board.tiles.count == 1)
    }

    @Test func placementScoresMatchingEdges() throws {
        var game = ValleyGame(board: Board(starter: tile("ffffff", id: 0)), queue: [tile("mmmfmm")], tilesLeft: 3)
        let placed = game.placeCurrent(at: east)
        let result = try #require(placed)
        #expect(result.points == game.rules.matchPoints)
        #expect(game.score == game.rules.matchPoints)
        #expect(game.tilesLeft == 2)
    }

    @Test func perfectFitEarnsABonusTile() throws {
        var board = Board(starter: tile("mmmmmm", id: 0))
        for (index, hex) in east.neighbors.enumerated() where board[hex] == nil {
            board.place(tile("mmmmmm", id: 10 + index), at: hex)
        }
        var game = ValleyGame(board: board, queue: [tile("mmmmmm")], tilesLeft: 3)
        let placed = game.placeCurrent(at: east)
        let result = try #require(placed)
        #expect(result.evaluation.isPerfect)
        #expect(result.tilesAwarded == game.rules.perfectBonusTiles)
        #expect(game.tilesLeft == 3 - 1 + game.rules.perfectBonusTiles)
        #expect(result.points == 6 * game.rules.matchPoints + game.rules.perfectPoints)
    }

    @Test func questCompletesAndAwardsTiles() throws {
        let questTile = tile("ffffff", quest: QuestSpec(terrain: .forest, target: 2))
        var game = ValleyGame(board: Board(starter: tile("ffffff", id: 0)), queue: [questTile], tilesLeft: 5)
        let placed = game.placeCurrent(at: east)
        let result = try #require(placed)
        #expect(result.completedQuests.map(\.id) == [questTile.id])
        #expect(result.tilesAwarded == game.rules.questReward(for: 2))
        #expect(game.tilesLeft == 5 - 1 + game.rules.questReward(for: 2))
        #expect(game.activeQuests.isEmpty)
    }

    @Test func questFailsWhenItsRegionIsClosedOff() throws {
        let questTile = tile("mmmfmm", quest: QuestSpec(terrain: .forest, target: 3))
        var game = ValleyGame(board: Board(starter: tile("mmmmmm", id: 0)), queue: [questTile], tilesLeft: 5)
        let placed = game.placeCurrent(at: east)
        let result = try #require(placed)
        #expect(result.failedQuests.map(\.id) == [questTile.id])
        #expect(game.quests.first?.status == .failed)
    }

    @Test func runningOutOfTilesReportsNearMisses() throws {
        let questTile = tile("ffffff", quest: QuestSpec(terrain: .forest, target: 3))
        var game = ValleyGame(board: Board(starter: tile("ffffff", id: 0)), queue: [questTile], tilesLeft: 1)
        let placed = game.placeCurrent(at: east)
        try #require(placed != nil)
        #expect(game.isGameOver)
        #expect(game.current == nil)
        #expect(game.nearMisses.map(\.remaining) == [1])
    }

    @Test func continueAddsTilesToAFinishedRun() throws {
        var game = ValleyGame(board: Board(starter: tile("mmmmmm", id: 0)), queue: [tile("mmmmmm")], tilesLeft: 1)
        let placed = game.placeCurrent(at: east)
        try #require(placed != nil)
        #expect(game.isGameOver)
        game.continueRun()
        #expect(game.tilesLeft == game.rules.continueTiles)
        #expect(game.current != nil)
    }

    @Test func discardOnlyWorksWhenStuck() {
        var game = ValleyGame(board: Board(starter: tile("mmmmmm", id: 0)), queue: [tile("mmmmmm")], tilesLeft: 3)
        game.discardCurrent()
        #expect(game.tilesLeft == 3)

        var stuck = ValleyGame(board: Board(starter: tile("mmmmmm", id: 0)), queue: [tile("wwwwww")], tilesLeft: 3)
        #expect(stuck.isStuck)
        stuck.discardCurrent()
        #expect(stuck.tilesLeft == 2)
    }

    /// Plays many seeded runs with random legal moves and checks the invariants hold throughout.
    @Test(arguments: 1...25)
    func randomPlaythroughKeepsInvariants(seed: UInt64) {
        var game = ValleyGame(seed: seed)
        var rng = SplitMix64(seed: seed &* 7919)
        var lastScore = 0
        var moves = 0

        while !game.isGameOver && moves < 400 {
            moves += 1
            guard let current = game.current else {
                Issue.record("A run with tiles left has no current tile")
                return
            }
            if game.isStuck {
                game.discardCurrent()
                continue
            }
            let options = game.board.openSlots.compactMap { slot in
                game.board.bestRotation(for: current, at: slot).map { (slot, $0) }
            }
            guard let (slot, steps) = options.randomElement(using: &rng) else {
                Issue.record("Not stuck, yet no slot fits")
                return
            }
            game.rotateCurrent(clockwiseSteps: steps)
            let placed = game.placeCurrent(at: slot)
            #expect(placed != nil)

            #expect(game.score >= lastScore)
            lastScore = game.score
            #expect(game.tilesLeft >= 0)
            #expect(game.board.tiles.count == game.tilesPlaced + 1)
            #expect(game.activeQuests.count <= game.rules.maxActiveQuests)
            #expect((game.current == nil) == game.isGameOver)
            for quest in game.activeQuests {
                #expect(quest.progress < quest.target)
            }
        }
    }
}

@Suite struct GeneratorTests {
    @Test func sameSeedMakesTheSameTiles() {
        var first = TileGenerator(seed: 7, riverChance: 0.15, questChance: 0.22)
        var second = TileGenerator(seed: 7, riverChance: 0.15, questChance: 0.22)
        for _ in 0..<50 {
            #expect(first.makeTile(allowQuest: true, questBase: 5) == second.makeTile(allowQuest: true, questBase: 5))
        }
    }

    @Test func riversCrossExactlyTwoEdges() {
        var generator = TileGenerator(seed: 11, riverChance: 0.5, questChance: 0)
        var sawRiver = false
        for _ in 0..<200 {
            let waterEdges = generator.makeTile(allowQuest: false, questBase: 5).edges.filter { $0 == .water }.count
            #expect(waterEdges == 0 || waterEdges == 2)
            sawRiver = sawRiver || waterEdges == 2
        }
        #expect(sawRiver)
    }

    @Test func questsOnlyAskForTerrainOnTheTile() {
        var generator = TileGenerator(seed: 3, riverChance: 0.15, questChance: 1)
        for _ in 0..<200 {
            let made = generator.makeTile(allowQuest: true, questBase: 5)
            if let quest = made.quest {
                #expect(made.contains(quest.terrain))
                #expect(quest.target >= 3)
            }
        }
    }

    @Test func starterTileHasNoRiverOrQuest() {
        var generator = TileGenerator(seed: 5, riverChance: 1, questChance: 1)
        let starter = generator.makeStarterTile()
        #expect(!starter.contains(.water))
        #expect(starter.quest == nil)
    }
}
