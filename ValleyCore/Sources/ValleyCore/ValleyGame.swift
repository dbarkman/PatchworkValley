/// Tuning knobs for a run.
public struct Rules: Sendable {
    public var startingTiles = 30
    /// Tiles the player can see: the current one plus a preview.
    public var visibleTiles = 2
    public var matchPoints = 10
    public var perfectPoints = 50
    public var perfectBonusTiles = 1
    public var riverChance = 0.15
    public var questChance = 0.22
    public var maxActiveQuests = 3
    public var continueTiles = 5
    /// A quest this many tiles or fewer from done counts as a near miss when the run ends.
    public var nearMissGap = 3

    public init() {}

    /// Quest targets grow as the valley grows.
    public func questBase(afterPlacing placed: Int) -> Int { 4 + placed / 10 }
    public func questReward(for target: Int) -> Int { 3 + target / 3 }
    public func questPoints(for target: Int) -> Int { target * 10 }
}

public struct Quest: Hashable, Sendable, Identifiable {
    public enum Status: Hashable, Sendable { case active, completed, failed }

    /// The id of the tile that carried the quest.
    public let id: Int
    public let terrain: Terrain
    public let target: Int
    /// Where the quest tile was placed; the quest tracks the region touching it.
    public let anchor: Hex
    public internal(set) var progress = 1
    public internal(set) var status = Status.active

    public var remaining: Int { max(0, target - progress) }
}

/// What one placement did, for scoring feedback and animation.
public struct PlacementResult: Sendable {
    public let hex: Hex
    public let tile: Tile
    public let evaluation: PlacementEvaluation
    public let points: Int
    public let tilesAwarded: Int
    public let completedQuests: [Quest]
    public let failedQuests: [Quest]
}

/// One run of Patchwork Valley. Place tiles until none are left; quests and
/// perfect fits earn more tiles.
public struct ValleyGame: Sendable {
    public let rules: Rules
    public private(set) var board: Board
    public private(set) var score = 0
    /// Tiles still to play, including the current one.
    public private(set) var tilesLeft: Int
    public private(set) var tilesPlaced = 0
    /// Every quest this run, in the order started.
    public private(set) var quests: [Quest] = []
    private var queue: [Tile] = []
    private var generator: TileGenerator

    public init(seed: UInt64, rules: Rules = Rules()) {
        var generator = TileGenerator(seed: seed, riverChance: rules.riverChance, questChance: rules.questChance)
        self.rules = rules
        board = Board(starter: generator.makeStarterTile())
        self.generator = generator
        tilesLeft = rules.startingTiles
        refillQueue()
    }

    /// Starts from a prepared board and tile queue. Tests use this to set up exact situations.
    init(rules: Rules = Rules(), board: Board, queue: [Tile], tilesLeft: Int, seed: UInt64 = 1) {
        self.rules = rules
        self.board = board
        self.queue = queue
        self.tilesLeft = tilesLeft
        generator = TileGenerator(seed: seed, riverChance: rules.riverChance, questChance: rules.questChance)
        refillQueue()
    }

    public var current: Tile? { queue.first }
    public var next: Tile? { queue.dropFirst().first }
    public var isGameOver: Bool { tilesLeft == 0 }
    public var activeQuests: [Quest] { quests.filter { $0.status == .active } }

    /// The current tile fits nowhere, in any rotation.
    public var isStuck: Bool {
        guard let current else { return false }
        return !board.hasLegalPlacement(for: current)
    }

    /// Active quests that were close when the run ended, closest first.
    public var nearMisses: [Quest] {
        activeQuests
            .filter { (1...rules.nearMissGap).contains($0.remaining) }
            .sorted { $0.remaining < $1.remaining }
    }

    public func evaluateCurrent(at hex: Hex) -> PlacementEvaluation? {
        current.map { board.evaluate($0, at: hex) }
    }

    /// Points for edge matches and a perfect fit. Quest points are added on completion.
    public func points(for evaluation: PlacementEvaluation) -> Int {
        evaluation.matchingEdges.count * rules.matchPoints + (evaluation.isPerfect ? rules.perfectPoints : 0)
    }

    public mutating func rotateCurrent(clockwiseSteps steps: Int = 1) {
        guard !queue.isEmpty else { return }
        queue[0].rotateClockwise(steps)
    }

    /// Places the current tile. Returns nil and changes nothing when the placement is illegal.
    @discardableResult
    public mutating func placeCurrent(at hex: Hex) -> PlacementResult? {
        guard let tile = current else { return nil }
        let evaluation = board.evaluate(tile, at: hex)
        guard evaluation.isLegal else { return nil }

        board.place(tile, at: hex)
        queue.removeFirst()
        tilesLeft -= 1
        tilesPlaced += 1

        var earned = points(for: evaluation)
        var awarded = evaluation.isPerfect ? rules.perfectBonusTiles : 0

        if let spec = tile.quest {
            quests.append(Quest(id: tile.id, terrain: spec.terrain, target: spec.target, anchor: hex))
        }

        var completed: [Quest] = []
        var failed: [Quest] = []
        for index in quests.indices where quests[index].status == .active {
            let quest = quests[index]
            let region = board.region(of: quest.terrain, from: quest.anchor)
            quests[index].progress = region.count
            if region.count >= quest.target {
                quests[index].status = .completed
                awarded += rules.questReward(for: quest.target)
                earned += rules.questPoints(for: quest.target)
                completed.append(quests[index])
            } else if board.openEdgeCount(of: region, terrain: quest.terrain) == 0 {
                quests[index].status = .failed
                failed.append(quests[index])
            }
        }

        score += earned
        tilesLeft += awarded
        refillQueue()

        return PlacementResult(
            hex: hex,
            tile: tile,
            evaluation: evaluation,
            points: earned,
            tilesAwarded: awarded,
            completedQuests: completed,
            failedQuests: failed
        )
    }

    /// Throws away a tile that fits nowhere. It still costs a tile.
    public mutating func discardCurrent() {
        guard isStuck else { return }
        queue.removeFirst()
        tilesLeft -= 1
        refillQueue()
    }

    /// Adds tiles to a finished run so it keeps going.
    public mutating func continueRun(adding count: Int? = nil) {
        guard isGameOver else { return }
        tilesLeft += count ?? rules.continueTiles
        refillQueue()
    }

    private mutating func refillQueue() {
        while queue.count < min(tilesLeft, rules.visibleTiles) {
            let pendingQuests = activeQuests.count + queue.filter { $0.quest != nil }.count
            queue.append(generator.makeTile(
                allowQuest: pendingQuests < rules.maxActiveQuests,
                questBase: rules.questBase(afterPlacing: tilesPlaced)
            ))
        }
    }
}
