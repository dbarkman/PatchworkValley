import Testing
@testable import ValleyCore

@Suite struct PowerUpDemoTests {
    /// Open slots where `tile` fits in some rotation.
    private func fittingSlots(for tile: Tile, on board: Board) -> [Hex] {
        board.openSlots.filter { board.bestRotation(for: tile, at: $0) != nil }
    }

    /// Turns the tile in hand to its best rotation at `hex` and places it, as the app does.
    private func placeBest(at hex: Hex, in game: inout ValleyGame) throws -> PlacementResult {
        let tile = try #require(game.current)
        let steps = try #require(game.board.bestRotation(for: tile, at: hex))
        game.rotateCurrent(clockwiseSteps: steps)
        let placed = game.placeCurrent(at: hex)
        return try #require(placed)
    }

    /// The bot plays the rest of the stack from here without running out of room.
    private func finishes(_ game: ValleyGame) -> Bool {
        var game = game
        Tutorial.playOut(&game)
        return game.outcome == .outOfTiles && game.tilesLeft == 0
    }

    @Test func everyPowerUpAfterSwapHasADemo() {
        #expect(PowerUpDemo.demoed == [.undo, .wildcard, .dynamite, .lantern])
        #expect(PowerUpDemo.demoed == PowerUp.allCases.filter { $0 != .swap })
    }

    @Test(arguments: PowerUpDemo.demoed)
    func aDemoIsTheSameEveryTime(_ powerUp: PowerUp) {
        var first = PowerUpDemo.makeGame(for: powerUp)
        var second = PowerUpDemo.makeGame(for: powerUp)
        #expect(first.current == second.current)
        #expect(first.next == second.next)
        #expect(first.board.tiles == second.board.tiles)
        #expect(first.board.floor == second.board.floor)
        #expect(first.board.mountains == second.board.mountains)
        #expect(first.board.lakes == second.board.lakes)
        #expect(PowerUpDemo.spot(for: powerUp, in: first) == PowerUpDemo.spot(for: powerUp, in: second))
        #expect(PowerUpDemo.target(for: powerUp, in: first) == PowerUpDemo.target(for: powerUp, in: second))
        #expect(Tutorial.playOut(&first) == Tutorial.playOut(&second))
    }

    /// A demo is a valley of its power-up's number that pays no coins and sets no quests. Its tile
    /// fits somewhere, except in the Wildcard demo, where it fits nowhere until it turns wild.
    @Test(arguments: PowerUpDemo.demoed)
    func aDemoStartsQuietAndPaysNothing(_ powerUp: PowerUp) throws {
        let game = PowerUpDemo.makeGame(for: powerUp)
        #expect(game.outcome == (powerUp == .wildcard ? .outOfRoom : .playing))
        #expect(game.quests.isEmpty)
        #expect(game.tilesLeft == game.rules.startingTiles)
        #expect(game.rules.startingTiles == 6)
        #expect(game.rules.questTargetBonus == Rules.coins(valley: powerUp.unlockValley).questTargetBonus)
        #expect(game.board.requiresMatch && !game.rules.allowsDiscard)
        let tile = try #require(game.current)
        #expect(fittingSlots(for: tile, on: game.board).isEmpty == (powerUp == .wildcard))
        for slot in game.board.openSlots {
            for steps in 0..<6 {
                let evaluation = game.board.evaluate(tile.rotatedClockwise(steps), at: slot)
                guard evaluation.isLegal else { continue }
                #expect(game.coins(for: evaluation) == 0)
            }
        }
    }

    /// A player who keeps going can place the whole stack, and it never pays a coin or sets a quest.
    @Test(arguments: PowerUpDemo.demoed)
    func theWholeDemoStackFits(_ powerUp: PowerUp) {
        var game = PowerUpDemo.makeGame(for: powerUp)
        // The Wildcard demo's first tile only goes down once it's wild.
        if powerUp == .wildcard { game.makeCurrentWild() }
        let dealt = Tutorial.playOut(&game)
        #expect(dealt.count == game.rules.startingTiles)
        #expect(game.outcome == .outOfTiles)
        #expect(game.coins == 0)
        #expect(game.quests.isEmpty)
    }

    /// The crater looks like a real one: a rim all round, and peaks and lakes on the floor, in the fog.
    @Test(arguments: PowerUpDemo.demoed)
    func aDemoCraterLooksReal(_ powerUp: PowerUp) throws {
        let board = PowerUpDemo.makeGame(for: powerUp).board
        let floor = try #require(board.floor)
        #expect((36...50).contains(floor.count))
        #expect(board.lakes.isSubset(of: floor))
        #expect(floor.allSatisfy { hex in hex.neighbors.allSatisfy { floor.contains($0) || board.mountains.contains($0) } }, "the rim closes the floor in")
        #expect(board.mountains.intersection(floor).count >= 3)
        #expect(board.lakes.count == 2)
        #expect(Hex.origin.neighbors.allSatisfy(board.openSlots.contains), "the start and its neighbors are open floor")
        #expect(board.revealedLakes.isEmpty)
        #expect(board.clearableMountains.isEmpty)
    }

    @Test func undoPlacesTheFirstTileAtItsSpot() throws {
        var game = PowerUpDemo.makeGame(for: .undo)
        let before = game
        let spot = try #require(PowerUpDemo.spot(for: .undo, in: game))
        let tile = try #require(game.current)
        #expect(game.board.bestRotation(for: tile, at: spot) != nil)
        _ = try placeBest(at: spot, in: &game)
        #expect(game.outcome == .playing)
        #expect(finishes(game))
        #expect(PowerUpDemo.spot(for: .undo, in: game) == nil, "the spot is taken")
        // Undo is the app restoring its copy of the run: the spot is back for the same tile.
        #expect(PowerUpDemo.spot(for: .undo, in: before) == spot)
        #expect(PowerUpDemo.target(for: .undo, in: before) == nil)
    }

    @Test func wildcardTurnsATileThatFitsNowhereIntoOneThatFitsAnywhere() throws {
        var game = PowerUpDemo.makeGame(for: .wildcard)
        let tile = try #require(game.current)
        let starter = try #require(game.board[.origin])
        #expect(tile.edges.allSatisfy { $0 == .village })
        #expect(!starter.contains(.village), "no village to match")
        #expect(fittingSlots(for: tile, on: game.board).isEmpty)
        #expect(game.outcome == .outOfRoom)
        #expect(PowerUpDemo.spot(for: .wildcard, in: game) == nil)
        #expect(PowerUpDemo.target(for: .wildcard, in: game) == nil)
        game.makeCurrentWild()
        let wild = try #require(game.current)
        #expect(wild.isWild)
        #expect(wild.id != tile.id, "the tray sees a new tile")
        #expect(game.outcome == .playing)
        #expect(fittingSlots(for: wild, on: game.board).count == game.board.openSlots.count)
        #expect(finishes(game))
    }

    @Test func dynamiteUncoversAMountainToBlast() throws {
        var game = PowerUpDemo.makeGame(for: .dynamite)
        let spot = try #require(PowerUpDemo.spot(for: .dynamite, in: game))
        let target = try #require(PowerUpDemo.target(for: .dynamite, in: game))
        #expect(game.board.clearableMountains.isEmpty)
        #expect(game.board.isInFog(target))
        _ = try placeBest(at: spot, in: &game)
        #expect(game.board.clearableMountains == [target])
        #expect(PowerUpDemo.target(for: .dynamite, in: game) == target)
        let blasted = game.clearMountain(at: target)
        #expect(blasted)
        #expect(!game.board.mountains.contains(target))
        #expect(game.board.isBuildable(target))
        #expect(game.board.openSlots.contains(target))
        #expect(PowerUpDemo.target(for: .dynamite, in: game) == nil)
        #expect(game.outcome == .playing)
        #expect(finishes(game))
    }

    @Test func lanternLightsEveryHiddenPeakAndLake() throws {
        var game = PowerUpDemo.makeGame(for: .lantern)
        let floor = try #require(game.board.floor)
        let peaks = game.board.mountains.intersection(floor)
        #expect(peaks.count >= 3)
        #expect(game.board.lakes.count >= 2)
        let seen = game.board.revealedMountains.intersection(peaks).count + game.board.revealedLakes.count
        #expect(seen <= 1)
        #expect(PowerUpDemo.spot(for: .lantern, in: game) == nil)
        #expect(PowerUpDemo.target(for: .lantern, in: game) == nil)
        game.lightCrater()
        #expect(game.board.revealedMountains == game.board.mountains)
        #expect(game.board.revealedLakes == game.board.lakes)
        #expect(finishes(game))
    }

    /// The tile in hand has a river, and only the Lantern shows the lake it can flow into.
    @Test func theLanternShowsWhereTheRiverCanGo() throws {
        var game = PowerUpDemo.makeGame(for: .lantern)
        let tile = try #require(game.current)
        #expect(tile.contains(.water))
        func flowsIntoALake(_ board: Board) -> Bool {
            board.openSlots.contains { slot in
                (0..<6).contains { steps in
                    let turned = tile.rotatedClockwise(steps)
                    let evaluation = board.evaluate(turned, at: slot)
                    return evaluation.isLegal && evaluation.matchingEdges.contains { board.revealedLakes.contains(slot.neighbor($0)) }
                }
            }
        }
        #expect(!flowsIntoALake(game.board))
        game.lightCrater()
        #expect(flowsIntoALake(game.board))
    }
}
