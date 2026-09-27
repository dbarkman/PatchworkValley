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
        #expect(game.outcome == .outOfTiles)
        #expect(game.current == nil)
        #expect(game.nearMisses.map(\.remaining) == [1])
    }

    @Test func continueAddsTilesToAFinishedRun() throws {
        var game = ValleyGame(board: Board(starter: tile("mmmmmm", id: 0)), queue: [tile("mmmmmm")], tilesLeft: 1)
        let placed = game.placeCurrent(at: east)
        try #require(placed != nil)
        #expect(game.outcome == .outOfTiles)
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

        while !game.isOver && moves < 400 {
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
            #expect((game.current == nil) == (game.tilesLeft == 0))
            for quest in game.activeQuests {
                #expect(quest.progress < quest.target)
            }
        }
    }
}

@Suite struct GeneratorTests {
    @Test func sameSeedMakesTheSameTiles() {
        var first = TileGenerator(seed: 7, riverChance: 0.15, questChance: 0.22, lakeChance: 0.35)
        var second = TileGenerator(seed: 7, riverChance: 0.15, questChance: 0.22, lakeChance: 0.35)
        for _ in 0..<50 {
            #expect(first.makeTile() == second.makeTile())
        }
    }

    @Test func riversCrossTwoEdgesAndLakesTakeOne() {
        var generator = TileGenerator(seed: 11, riverChance: 0.5, questChance: 0, lakeChance: 0.4)
        var counts: Set<Int> = []
        for _ in 0..<300 {
            let waterEdges = generator.makeTile().edges.filter { $0 == .water }.count
            #expect([0, 1, 2].contains(waterEdges))
            counts.insert(waterEdges)
        }
        #expect(counts == [0, 1, 2])
    }

    @Test func withoutLakesEveryRiverCrossesTwoEdges() {
        var generator = TileGenerator(seed: 11, riverChance: 0.5, questChance: 0)
        for _ in 0..<200 {
            let waterEdges = generator.makeTile().edges.filter { $0 == .water }.count
            #expect(waterEdges == 0 || waterEdges == 2)
        }
    }

    @Test func questsOnlyAskForTerrainOnTheTile() {
        var generator = TileGenerator(seed: 3, riverChance: 0.15, questChance: 1)
        let plenty = Dictionary(uniqueKeysWithValues: Terrain.questable.map { ($0, 30) })
        for _ in 0..<200 {
            let made = generator.assignQuest(to: generator.makeTile(), base: 5, supply: plenty)
            if let quest = made.quest {
                #expect(made.contains(quest.terrain))
                #expect(quest.target >= 3)
            }
        }
    }

    /// A terrain on one side of the quest tile can only grow one way, so its quests ask for less.
    @Test func singleSideTerrainGetsSmallerQuests() {
        var generator = TileGenerator(seed: 21, riverChance: 0, questChance: 1)
        let plenty = Dictionary(uniqueKeysWithValues: Terrain.questable.map { ($0, 40) })
        let oneForest = Tile(id: 60, edges: [.forest, .meadow, .meadow, .meadow, .meadow, .meadow])
        let fullForest = Tile(id: 61, edges: Array(repeating: .forest, count: 6))
        let thin = (0..<200).compactMap { _ in generator.assignQuest(to: oneForest, base: 6, supply: plenty).quest?.target }
        let wide = (0..<200).compactMap { _ in generator.assignQuest(to: fullForest, base: 6, supply: plenty).quest?.target }
        #expect(thin.max()! <= 6 + 3 - 2)
        #expect(wide.max()! == 6 + 3)
    }

    /// A quest never asks for more than the quest tile plus 70% (60% for rivers) of the matching tiles to come.
    @Test func questsFitTheTilesStillToCome() {
        var generator = TileGenerator(seed: 8, riverChance: 0.15, questChance: 1)
        let river = Tile(id: 50, edges: [.water, .meadow, .meadow, .water, .meadow, .meadow])
        let scarce: [Terrain: Int] = [.water: 2, .meadow: 30]
        for _ in 0..<100 {
            #expect(generator.assignQuest(to: river, base: 8, supply: scarce).quest == nil, "1 + 60% of 2 rivers is too few for a quest")
        }
        let enough: [Terrain: Int] = [.water: 10]
        for _ in 0..<100 {
            if let quest = generator.assignQuest(to: river, base: 8, supply: enough).quest {
                #expect(quest.target <= 1 + 6)
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

@Suite struct CoinsPerMatchTests {
    @Test func coinModePaysOneCoinPerMatchedSide() throws {
        var board = Board(starter: tile("ffffff", id: 0))
        board.place(tile("cccccc", id: 1), at: Hex(1, -1))
        var game = ValleyGame(rules: .coins(valley: 1), board: board, queue: [tile("mmcfmm")], tilesLeft: 5)
        let placed = game.placeCurrent(at: east)
        let result = try #require(placed)
        #expect(result.evaluation.matchingEdges.count == 2)
        #expect(result.coins == 2)
    }

    @Test func zenAndLevelsPayNoCoins() throws {
        var game = ValleyGame(board: Board(starter: tile("ffffff", id: 0)), queue: [tile("mmmfmm")], tilesLeft: 3)
        let placed = game.placeCurrent(at: east)
        let result = try #require(placed)
        #expect(result.coins == 0)
    }
}

@Suite struct LevelTests {
    @Test func fiveLevelsWithGoalsAddingUpToHalfTheStack() {
        #expect(LevelDesigner.levels.map(\.tiles) == [12, 18, 24, 30, 36])
        #expect(LevelDesigner.levels.map(\.number) == [1, 2, 3, 4, 5])
        for level in LevelDesigner.levels {
            #expect(level.goals.map(\.target).reduce(0, +) == level.tiles / 2, "Level \(level.number)")
            #expect(Set(level.goals.map(\.terrain)).count == level.goals.count, "Level \(level.number) repeats a terrain")
        }
    }

    /// Each level's tile order was picked so the bot wins it; this catches rule changes that break that.
    @Test(arguments: LevelDesigner.levels)
    func botBeatsEveryLevel(level: LevelSpec) {
        #expect(LevelDesigner.botSpare(for: level) != nil, "Level \(level.number) is no longer beatable by the bot")
    }

    @Test func laterLevelsLeaveTheBotLessToSpare() {
        let spares = LevelDesigner.levels.compactMap(LevelDesigner.botSpare)
        #expect(spares.count == LevelDesigner.levelCount)
        #expect(spares.first! > spares.last!)
    }

    @Test func levelStacksOnlyCountDown() {
        let level = LevelDesigner.level(4)
        var game = ValleyGame(level: level)
        var last = game.tilesLeft
        while !game.isOver {
            guard let move = GreedyBot.bestMove(in: game, focus: []) else {
                game.discardCurrent()
                continue
            }
            game.rotateCurrent(clockwiseSteps: move.steps)
            let placed = game.placeCurrent(at: move.slot)
            #expect(placed?.tilesAwarded == 0)
            #expect(game.tilesLeft < last)
            last = game.tilesLeft
        }
        #expect(game.quests.isEmpty)
    }

    @Test func winningPaysForUnusedTilesAndEndsTheLevel() throws {
        let goal = Goal(terrain: .forest, target: 2)
        var game = ValleyGame(rules: .levels, board: Board(starter: tile("ffffff", id: 0)), queue: [tile("mmmfmm")], tilesLeft: 5, goals: [goal])
        #expect(game.goals.first?.progress == 1)
        let placed = game.placeCurrent(at: east)
        let result = try #require(placed)
        #expect(result.metGoals.map(\.terrain) == [.forest])
        #expect(game.outcome == .won)
        #expect(result.bonusPoints == 4 * game.rules.unusedTileBonus)
        #expect(game.score == result.points + result.bonusPoints)

        let after = game.placeCurrent(at: Hex(-1, 0))
        #expect(after == nil)
    }

    @Test func runningOutWithAGoalCloseIsANearMiss() {
        let goal = Goal(terrain: .forest, target: 3)
        var game = ValleyGame(rules: .levels, board: Board(starter: tile("ffffff", id: 0)), queue: [tile("mmmfmm")], tilesLeft: 1, goals: [goal])
        game.placeCurrent(at: east)
        #expect(game.outcome == .outOfTiles)
        #expect(game.nearMisses == [NearMiss(terrain: .forest, remaining: 1, target: 3)])
        game.continueRun()
        #expect(game.tilesLeft == game.rules.continueTiles)
        #expect(game.outcome == .playing)
    }

    @Test func largestRegionFindsTheBiggestPatch() {
        var board = Board(starter: tile("ffffff", id: 0))
        board.place(tile("mmmfmm", id: 1), at: east)
        board.place(tile("ffffff", id: 2), at: Hex(-3, 0))
        #expect(board.largestRegion(of: .forest) == [.origin, east])
        #expect(board.largestRegion(of: .village).isEmpty)
    }
}

@Suite struct CoinModeTests {
    @Test func wildcardMatchesEverySide() {
        var board = Board(starter: tile("ffffff", id: 0))
        board.place(tile("cccccc", id: 1), at: Hex(1, -1))
        let evaluation = board.evaluate(Tile(id: 5, edges: Array(repeating: .wild, count: 6)), at: east)
        #expect(evaluation.isLegal)
        #expect(evaluation.clashingEdges.isEmpty)
        #expect(evaluation.matchingEdges.count == 2)
    }

    @Test func wildcardMayTouchRivers() {
        let board = Board(starter: tile("wmmwmm", id: 0))
        #expect(board.canPlace(Tile(id: 5, edges: Array(repeating: .wild, count: 6)), at: east))
    }

    @Test func wildcardJoinsTwoForests() {
        var board = Board(starter: tile("ffffff", id: 0))
        board.place(tile("ffffff", id: 1), at: Hex(2, 0))
        #expect(board.largestRegion(of: .forest).count == 1)
        board.place(Tile(id: 5, edges: Array(repeating: .wild, count: 6)), at: east)
        #expect(board.largestRegion(of: .forest).count == 3)
    }

    @Test func coinQuestsPayCoinsAndTheStackOnlyCountsDown() throws {
        let questTile = tile("ffffff", quest: QuestSpec(terrain: .forest, target: 2))
        var game = ValleyGame(rules: .coins(valley: 1), board: Board(starter: tile("ffffff", id: 0)), queue: [questTile], tilesLeft: 5)
        let placed = game.placeCurrent(at: east)
        let result = try #require(placed)
        #expect(result.completedQuests.count == 1)
        #expect(result.tilesAwarded == 0)
        #expect(result.coins == game.rules.questCoins(for: 2) + result.evaluation.matchingEdges.count * game.rules.coinsPerMatch)
        #expect(game.coins == result.coins)
        #expect(game.tilesLeft == 4)
    }

    @Test func coinValleysHold36TilesAndGrowTheirQuests() {
        #expect(ValleyGame(seed: 1, rules: .coins(valley: 1)).tilesLeft == 36)
        #expect(Rules.coins(valley: 1).questBase(afterPlacing: 0) < Rules.coins(valley: 9).questBase(afterPlacing: 0))
        #expect(Rules.coins(valley: 99).questTargetBonus == Rules.coins(valley: 19).questTargetBonus)
    }

    @Test func swapDealsANewTileWithoutChangingTheCount() {
        var game = ValleyGame(seed: 3, rules: .coins(valley: 1))
        let before = game.current
        game.swapCurrent()
        #expect(game.current?.id != before?.id)
        #expect(game.tilesLeft == 36)
    }

    @Test func wildcardReplacesTheCurrentTile() {
        var game = ValleyGame(seed: 3, rules: .coins(valley: 1))
        game.makeCurrentWild()
        #expect(game.current?.isWild == true)
        #expect(game.tilesLeft == 36)
    }
}

/// Economy check, not a pass/fail test: enable it to see what a typical Coin valley
/// earns, and how often it runs out of room, when a bot chases the active quests
/// while keeping room open (a stand-in for a player who plans ahead).
@Test(.disabled("Run by hand when tuning Coin mode"), arguments: [1, 5, 10])
func coinEconomyReport(valley: Int) {
    let runs = 300
    var totalCoins = 0
    var totalQuests = 0
    var nearMissRuns = 0
    var outOfRoomRuns = 0
    var tilesLeftWhenStuck = 0
    for seed in 1...runs {
        var game = ValleyGame(seed: UInt64(seed), rules: .coins(valley: valley))
        while !game.isOver {
            let focus = game.activeQuests.sorted { $0.remaining < $1.remaining }.map(\.terrain)
            guard let move = roomKeepingMove(in: game, focus: focus) else { break }
            game.rotateCurrent(clockwiseSteps: move.steps)
            game.placeCurrent(at: move.slot)
        }
        totalCoins += game.coins
        totalQuests += game.quests.filter { $0.status == .completed }.count
        if !game.nearMisses.isEmpty { nearMissRuns += 1 }
        if game.outcome == .outOfRoom {
            outOfRoomRuns += 1
            tilesLeftWhenStuck += game.tilesLeft
        }
    }
    let stuckAverage = outOfRoomRuns == 0 ? 0 : tilesLeftWhenStuck / outOfRoomRuns
    print("ECONOMY valley \(valley): \(totalCoins / runs) coins/valley, \(Double(totalQuests) / Double(runs)) quests/valley, near miss in \(nearMissRuns * 100 / runs)%, out of room in \(outOfRoomRuns * 100 / runs)% (avg \(stuckAverage) tiles left)")
}

/// Grows quest regions like `GreedyBot`, but also values keeping open slots, as a planning player would.
private func roomKeepingMove(in game: ValleyGame, focus: [Terrain]) -> (slot: Hex, steps: Int)? {
    guard let tile = game.current else { return nil }
    var best: (slot: Hex, steps: Int, value: Int)?
    for slot in game.board.openSlots.sorted(by: { ($0.r, $0.q) < ($1.r, $1.q) }) {
        for steps in 0..<6 {
            let turned = tile.rotatedClockwise(steps)
            let evaluation = game.board.evaluate(turned, at: slot)
            guard evaluation.isLegal else { continue }
            var board = game.board
            board.place(turned, at: slot)
            var value = evaluation.matchingEdges.count * 3 + board.openSlots.count * 2
            for terrain in focus where turned.contains(terrain) {
                value += 4 * game.board.region(of: terrain, from: slot, placing: turned).count
            }
            if value > (best?.value ?? -1) { best = (slot, steps, value) }
        }
    }
    return best.map { ($0.slot, $0.steps) }
}

@Suite struct CraterTests {
    @Test(arguments: 1...30)
    func cratersHaveAnIrregularFloorRingedByTheRim(seed: UInt64) {
        let crater = Crater.generate(seed: seed, radius: 4, peakCount: 12, room: 37)
        #expect((45...100).contains(crater.floor.count))
        #expect(crater.floor.isDisjoint(with: crater.rim))
        #expect(crater.floor.isSuperset(of: [.origin] + Hex.origin.neighbors))
        // Every floor hex is bordered only by floor or rim: no gaps in the wall.
        for hex in crater.floor {
            #expect(hex.neighbors.allSatisfy { crater.floor.contains($0) || crater.rim.contains($0) })
        }
    }

    @Test func calmCratersAreRoundAndAllAlike() {
        let first = Crater.generate(seed: 1, radius: 4, roughness: 0, peakCount: 0, room: 37)
        let second = Crater.generate(seed: 2, radius: 4, roughness: 0, peakCount: 0, room: 37)
        #expect(first.floor == second.floor)
        #expect(Set(Hex.within(radius: 3)).isSubset(of: first.floor))
    }

    /// With the center free to wander, some valleys start near a wall; the start area always stays open.
    @Test func offsetCratersCanStartNearAWall() {
        let wallDistances = (1...40).map { seed -> Int in
            let crater = Crater.generate(seed: UInt64(seed), radius: 4, roughness: 0.3, maxOffset: 2, peakCount: 0, room: 37)
            #expect(crater.floor.isSuperset(of: [.origin] + Hex.origin.neighbors))
            #expect(crater.reachableFloor >= 37)
            return crater.rim.map { $0.distance(to: .origin) }.min() ?? 0
        }
        let centered = Crater.generate(seed: 1, radius: 4, roughness: 0.3, maxOffset: 0, peakCount: 0, room: 37)
        let centeredDistance = centered.rim.map { $0.distance(to: .origin) }.min() ?? 0
        #expect(wallDistances.contains { $0 < centeredDistance })
        #expect(wallDistances.allSatisfy { $0 >= 2 })
    }

    @Test func coinCratersGetRougherAndWanderFurther() {
        #expect(Rules.coins(valley: 1).craterRoughness < Rules.coins(valley: 10).craterRoughness)
        #expect(Rules.coins(valley: 10).craterRoughness == 1)
        #expect(Rules.coins(valley: 1).craterOffset == 1)
        #expect(Rules.coins(valley: 3).craterOffset == 2)
    }

    @Test func craterShapesVary() {
        let shapes = Set((1...10).map { Crater.generate(seed: $0, radius: 4, peakCount: 0, room: 37).floor })
        #expect(shapes.count == 10)
        #expect(shapes.contains { $0 != Set(Hex.within(radius: 4)) })
    }

    @Test(arguments: 1...40)
    func everyCraterLeavesRoomForTheWholeStack(seed: UInt64) {
        let crater = Crater.generate(seed: seed, radius: 4, peakCount: 20, room: 37)
        #expect(crater.reachableFloor >= 37)
        #expect(!crater.peaks.contains(.origin))
        #expect(crater.peaks.isDisjoint(with: Hex.origin.neighbors))
        #expect(crater.peaks.isSubset(of: crater.floor))
    }

    @Test func craterPeaksFollowTheRequestedCount() {
        let peaks = (1...20).map { Crater.generate(seed: UInt64($0), radius: 4, peakCount: 12, room: 37).peaks.count }
        let average = Double(peaks.reduce(0, +)) / Double(peaks.count)
        #expect((10...16).contains(average))
    }

    @Test func sameSeedBuildsTheSameCrater() {
        #expect(Crater.generate(seed: 9, radius: 4, peakCount: 12, room: 37) == Crater.generate(seed: 9, radius: 4, peakCount: 12, room: 37))
    }

    @Test func mountainsBlockPlacementAndAppearWhenATileTouchesThem() {
        let crater = Crater(radius: 4, floor: Set(Hex.within(radius: 4)), rim: [], peaks: [Hex(2, 0)])
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        #expect(board.revealedMountains.isEmpty)
        #expect(!board.openSlots.contains(Hex(2, 0)))
        board.place(tile("mmmmmm", id: 1), at: east)
        #expect(board.revealedMountains == [Hex(2, 0)])
        #expect(!board.openSlots.contains(Hex(2, 0)))
        #expect(!board.canPlace(tile("mmmmmm"), at: Hex(2, 0)))
    }

    @Test func tilesStayInsideTheRim() {
        let floor = Set(Hex.within(radius: 4))
        let crater = Crater(radius: 4, floor: floor, rim: Set(Hex.within(radius: 5)).subtracting(floor), peaks: [])
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        for q in 1...4 { board.place(tile("mmmmmm", id: q), at: Hex(q, 0)) }
        #expect(!board.openSlots.contains(Hex(5, 0)))
        #expect(board.revealedMountains.contains(Hex(5, 0)))
    }

    @Test func matchRuleNeedsOneMatchingSide() {
        let crater = Crater(radius: 4, floor: Set(Hex.within(radius: 4)), rim: [], peaks: [])
        let board = Board(starter: tile("ffffff", id: 0), crater: crater, requiresMatch: true)
        #expect(!board.canPlace(tile("cccccc"), at: east))
        #expect(board.canPlace(tile("cccfcc"), at: east))
    }

    @Test func dynamiteClearsARevealedFloorMountainButNotTheRim() {
        let crater = Crater(radius: 4, floor: Set(Hex.within(radius: 4)), rim: [Hex(5, 0)], peaks: [Hex(2, 0), Hex(3, -3)])
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        board.place(tile("mmmmmm", id: 1), at: east)
        let clearedRevealed = board.clearMountain(at: Hex(2, 0))
        #expect(clearedRevealed)
        #expect(board.openSlots.contains(Hex(2, 0)))
        let clearedHidden = board.clearMountain(at: Hex(3, -3))
        #expect(!clearedHidden, "hidden in fog")
        let clearedRim = board.clearMountain(at: Hex(5, 0))
        #expect(!clearedRim, "the rim stays")
    }

    @Test func lanternRevealsEveryMountain() {
        let crater = Crater.generate(seed: 4, radius: 4, peakCount: 12, room: 37)
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        board.revealAll()
        #expect(board.revealedMountains == crater.mountains)
    }

    @Test func revealedMountainsCountTowardAPerfectFit() {
        let crater = Crater(radius: 4, floor: Set(Hex.within(radius: 4)), rim: [], peaks: [Hex(2, 0), Hex(2, -1), Hex(1, 1), Hex(0, 1)])
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        board.place(tile("mmmmmm", id: 1), at: Hex(1, -1))
        board.revealAll()
        // East of the origin: neighbors are two mountains east, the origin, (1,-1), and two more mountains below.
        #expect(board.evaluate(tile("mmmmmm"), at: east).isPerfect)
    }

    @Test func coinValleyStartsInACraterWithRoomToPlay() {
        let game = ValleyGame(seed: 11, rules: .coins(valley: 1))
        #expect((45...100).contains(game.board.floor?.count ?? 0))
        #expect(!game.board.mountains.isEmpty)
        #expect(game.outcome == .playing)
    }

    @Test func aTileThatFitsNowhereLeavesTheValleyOutOfRoomUntilRescued() {
        let crater = Crater(radius: 4, floor: Set(Hex.within(radius: 4)), rim: [], peaks: [])
        var rules = Rules.coins(valley: 1)
        rules.startingTiles = 5
        var game = ValleyGame(rules: rules, board: Board(starter: tile("ffffff", id: 0), crater: crater, requiresMatch: true), queue: [tile("cccccc")], tilesLeft: 5)
        #expect(game.outcome == .outOfRoom)
        game.discardCurrent()
        #expect(game.tilesLeft == 5, "Coin mode has no free discard")
        game.makeCurrentWild()
        #expect(game.outcome == .playing)
    }
}

@Suite struct ReviewFixTests {
    /// Buying tiles after finishing the stack can't turn a finished valley into a loss.
    @Test func aBoughtTileThatFitsNowhereStillLeavesTheValleyFinished() {
        let crater = Crater(radius: 4, floor: Set(Hex.within(radius: 4)), rim: [], peaks: [])
        var rules = Rules.coins(valley: 1)
        rules.startingTiles = 1
        var game = ValleyGame(rules: rules, board: Board(starter: tile("ffffff", id: 0), crater: crater, requiresMatch: true), queue: [tile("mmmfmm")], tilesLeft: 1)
        game.placeCurrent(at: east)
        #expect(game.outcome == .outOfTiles)
        #expect(game.hasFinishedStack)
        #expect(game.canContinue)

        game.continueRun(adding: 1)
        // Whatever the new tile is, the finished valley never becomes out of room.
        #expect(game.outcome != .outOfRoom)
    }

    @Test func continuingNeedsAnEmptyStack() {
        let crater = Crater(radius: 4, floor: Set(Hex.within(radius: 4)), rim: [], peaks: [])
        var rules = Rules.coins(valley: 1)
        rules.startingTiles = 1
        var game = ValleyGame(rules: rules, board: Board(starter: tile("ffffff", id: 0), crater: crater, requiresMatch: true), queue: [tile("mmmfmm")], tilesLeft: 1)
        game.placeCurrent(at: east)
        game.continueRun(adding: 3)
        let afterFirst = game.tilesLeft
        game.continueRun(adding: 3)
        #expect(game.tilesLeft == afterFirst, "a second continue before the stack is empty does nothing")
    }

    @Test func previewDoesNotGiveAwayFoggedMountains() {
        let crater = Crater(radius: 4, floor: Set(Hex.within(radius: 4)), rim: [], peaks: [Hex(2, 0), Hex(1, 1), Hex(2, -1), Hex(0, 1)])
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        board.place(tile("mmmmmm", id: 1), at: Hex(1, -1))
        #expect(!board.revealedMountains.contains(Hex(2, 0)))
        #expect(!board.evaluate(tile("mmmmmm"), at: east).isPerfect)
    }

    @Test func placingRevealsMountainsAndThenCountsThePerfectFit() throws {
        let crater = Crater(radius: 4, floor: Set(Hex.within(radius: 4)), rim: [], peaks: [Hex(2, 0), Hex(1, 1), Hex(2, -1), Hex(0, 1)])
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        board.place(tile("mmmmmm", id: 1), at: Hex(1, -1))
        var game = ValleyGame(rules: .coins(valley: 1), board: board, queue: [tile("mmmmmm")], tilesLeft: 5)
        let placed = game.placeCurrent(at: east)
        let result = try #require(placed)
        #expect(result.evaluation.isPerfect)
        #expect(result.coins == game.rules.coinsPerPerfect + result.evaluation.matchingEdges.count * game.rules.coinsPerMatch)
    }
}

@Suite struct LakeTests {
    private let floor = Set(Hex.within(radius: 4))

    @Test func lakesBlockPlacementAndAppearWhenATileTouchesThem() {
        let crater = Crater(radius: 4, floor: floor, rim: [], peaks: [], lakes: [Hex(2, 0)])
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        #expect(board.revealedLakes.isEmpty)
        board.place(tile("mmmmmm", id: 1), at: east)
        #expect(board.revealedLakes == [Hex(2, 0)])
        #expect(!board.openSlots.contains(Hex(2, 0)))
    }

    @Test func aRiverIntoASeenLakeMatchesAndLandMayBorderIt() {
        let crater = Crater(radius: 4, floor: floor, rim: [], peaks: [], lakes: [Hex(2, -1)])
        var board = Board(starter: tile("ffffff", id: 0), crater: crater, requiresMatch: true)
        board.place(tile("ffffff", id: 1), at: Hex(1, -1))
        #expect(board.revealedLakes.contains(Hex(2, -1)))
        // East of the origin, edge 1 faces the lake at (2, -1).
        let river = board.evaluate(tile("mwmfmm"), at: east)
        #expect(river.isLegal)
        #expect(river.matchingEdges.contains(1))
        let land = board.evaluate(tile("mfmfmm"), at: east)
        #expect(land.isLegal)
        #expect(!land.matchingEdges.contains(1))
        #expect(!land.clashingEdges.contains(1))
    }

    @Test func aLakeJoinsTheRiversThatFlowIntoIt() {
        let crater = Crater(radius: 4, floor: floor, rim: [], peaks: [], lakes: [Hex(2, 0)])
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        board.place(tile("wmmmmm", id: 1), at: east)          // river edge 0 flows east into the lake
        board.place(tile("mmmmmm", id: 2), at: Hex(2, -1))
        board.place(tile("mmmmwm", id: 3), at: Hex(3, -1))    // river edge 4 flows southwest into the lake
        let rivers = board.region(of: .water, from: east)
        #expect(rivers == [east, Hex(2, 0), Hex(3, -1)])
        #expect(board.largestRegion(of: .water).count == 3)
    }

    @Test func aLakesOpenSidesKeepARiverQuestAlive() {
        let crater = Crater(radius: 4, floor: floor, rim: [], peaks: [], lakes: [Hex(2, 0)])
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        board.place(tile("wmmmmm", id: 1), at: east)
        let rivers = board.region(of: .water, from: east)
        #expect(board.openEdgeCount(of: rivers, terrain: .water) > 0)
    }

    @Test func previewIgnoresAHiddenLakeButPlacingRevealsAndCountsIt() throws {
        let crater = Crater(radius: 4, floor: floor, rim: [], peaks: [], lakes: [Hex(2, 0)])
        let board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        let preview = board.evaluate(tile("wmmmmm"), at: east)
        #expect(!preview.matchingEdges.contains(0), "the lake is still in fog")

        var game = ValleyGame(rules: .coins(valley: 1), board: board, queue: [tile("wmmmmm")], tilesLeft: 5)
        let placed = game.placeCurrent(at: east)
        let result = try #require(placed)
        #expect(result.evaluation.matchingEdges.contains(0), "placing revealed the lake the river flows into")
    }

    @Test func lanternRevealsLakesToo() {
        let crater = Crater.generate(seed: 6, radius: 4, peakCount: 8, lakeCount: 2, room: 37)
        var board = Board(starter: tile("mmmmmm", id: 0), crater: crater, requiresMatch: false)
        board.revealAll()
        #expect(board.revealedLakes == crater.lakes)
    }

    @Test(arguments: 1...30)
    func cratersPlaceLakesApartAndStillLeaveRoom(seed: UInt64) {
        let crater = Crater.generate(seed: seed, radius: 4, peakCount: 14, lakeCount: 3, room: 37)
        #expect(crater.lakes.count == 3)
        #expect(crater.lakes.isDisjoint(with: crater.peaks))
        #expect(crater.lakes.isDisjoint(with: Hex.origin.neighbors + [.origin]))
        for lake in crater.lakes {
            #expect(lake.neighbors.allSatisfy { !crater.lakes.contains($0) })
        }
        #expect(crater.reachableFloor >= 37)
    }

    @Test func coinValleysHideTwoLakesThenThree() {
        #expect(Rules.coins(valley: 1).lakeCount == 2)
        #expect(Rules.coins(valley: 6).lakeCount == 3)
        #expect(ValleyGame(seed: 12, rules: .coins(valley: 1)).board.lakes.count == 2)
    }
}
