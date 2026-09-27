/// Tuning knobs for a run.
public struct Rules: Sendable {
    public var startingTiles = 30
    /// Tiles the player can see: the current one plus a preview.
    public var visibleTiles = 2
    public var matchPoints = 10
    public var perfectPoints = 50
    public var perfectBonusTiles = 1
    public var riverChance = 0.15
    /// Share of water tiles that are lakes: a pond with one river edge, where a river can end.
    public var lakeChance = 0.35
    public var questChance = 0.22
    public var maxActiveQuests = 3
    public var continueTiles = 5
    /// A goal or quest this many tiles or fewer from done counts as a near miss when tiles run out.
    public var nearMissGap = 3
    /// Points for each tile left over when a level's goals are met.
    public var unusedTileBonus = 25
    /// Quests add tiles to the stack (Zen). When false, quests pay only points and coins, so the stack only counts down.
    public var questsRewardTiles = true
    public var coinsPerPerfect = 0
    public var coinsPerMatch = 0
    public var questCoinBase = 0
    public var questCoinsPerTile = 0
    /// Added to every quest target, so later coin valleys ask for more.
    public var questTargetBonus = 0
    /// Keep at least one quest going: when none is active or on its way, set one on a
    /// region already built (favoring big ones), or else on the next tile dealt.
    public var alwaysQuest = false
    /// When the game sets a quest to keep one going, the share that grow a region already
    /// built; the rest go on the next tile dealt.
    public var boardQuestShare = 0.5
    /// Coin mode's crater radius. Zero means the open plane.
    public var craterRadius = 0
    /// How far the crater's outline wanders, from 0 (round) to 1 (ragged).
    public var craterRoughness = 1.0
    /// How many steps the crater's center may sit from the start.
    public var craterOffset = 0
    /// Peaks and ridges standing on the crater floor.
    public var peakCount = 0
    /// Lakes hidden on the crater floor.
    public var lakeCount = 0
    /// Zen's hidden peaks and lakes on the open plane, scattered out to this many steps
    /// from the start (the plane is clear beyond). Zero means none.
    public var scatterRadius = 0
    /// Share of the scattered area holding a peak (single peaks and short ridges).
    public var scatterPeakShare = 0.0
    /// Share of the scattered area holding a lake.
    public var scatterLakeShare = 0.0
    /// Every placement must match at least one neighboring edge.
    public var requiresMatch = false
    /// A tile that fits nowhere can be thrown away for a tile (Levels, Zen). Without
    /// discards, a tile that fits nowhere means the run is out of room.
    public var allowsDiscard = true

    public init() {}

    /// Coin mode: a 36-tile valley (6 × 6) whose quests pay coins instead of tiles.
    /// Quests grow by one every three valleys, up to six bigger than valley 1's.
    public static func coins(valley: Int) -> Rules {
        var rules = Rules()
        rules.startingTiles = 36
        rules.perfectBonusTiles = 0
        rules.questsRewardTiles = false
        rules.coinsPerPerfect = 5
        rules.coinsPerMatch = 1
        rules.questCoinBase = 5
        rules.questCoinsPerTile = 2
        rules.questTargetBonus = min(6, (max(1, valley) - 1) / 3)
        rules.questChance = 0.3
        rules.alwaysQuest = true
        rules.continueTiles = 3
        // A crater about 4 steps from the start to its wall: nearly round in valley 1, fully
        // ragged by valley 10, and centered up to a step away early on (two from valley 3),
        // so play can begin near a wall. 6 peaks in valley 1, one more every two valleys up to 14.
        // See `coinEconomyReport` for how often a room-keeping bot gets stuck.
        rules.craterRadius = 4
        rules.craterRoughness = min(1, 0.1 * Double(max(1, valley)))
        rules.craterOffset = valley >= 3 ? 2 : 1
        rules.peakCount = min(14, 5 + (max(1, valley) + 1) / 2)
        // Two lakes to find, three from valley 6.
        rules.lakeCount = valley >= 6 ? 3 : 2
        rules.requiresMatch = true
        rules.allowsDiscard = false
        return rules
    }

    /// Zen: the open plane, with peaks and lakes hidden in the fog.
    public static var zen: Rules {
        var rules = Rules()
        rules.scatterRadius = 20
        rules.scatterPeakShare = 0.06
        rules.scatterLakeShare = 0.02
        return rules
    }

    /// Level play: no tile-carried quests and no bonus tiles, so the stack only counts down.
    public static var levels: Rules {
        var rules = Rules()
        rules.questChance = 0
        rules.perfectBonusTiles = 0
        rules.continueTiles = 3
        // The designed levels' seeds deal rivers only.
        rules.lakeChance = 0
        return rules
    }

    /// Quest targets grow as the valley grows.
    public func questBase(afterPlacing placed: Int) -> Int { 4 + questTargetBonus + placed / 10 }
    public func questReward(for target: Int) -> Int { 3 + target / 3 }
    public func questPoints(for target: Int) -> Int { target * 10 }
    /// Coins for finishing a quest that asked for `growth` tiles, counting the quest's own tile.
    public func questCoins(for growth: Int) -> Int { questCoinBase + questCoinsPerTile * growth }
}

/// A Zen-mode quest carried by a tile. It tracks the region touching the tile it came on.
public struct Quest: Hashable, Sendable, Identifiable {
    public enum Status: Hashable, Sendable { case active, completed, failed }

    /// The id of the tile that carried the quest; negative for quests set on the board.
    public let id: Int
    public let terrain: Terrain
    public let target: Int
    /// A hex in the region the quest tracks: where the quest tile was placed, or a tile of the region it was set on.
    public let anchor: Hex
    public internal(set) var progress = 1
    public internal(set) var status = Status.active
    /// The region's size when the quest began: 1 for a quest tile, the region's size for a board quest.
    public internal(set) var start = 1
    /// How many tiles had been placed when the quest was completed or closed off; nil while it's going.
    public internal(set) var endedAfter: Int?

    public var remaining: Int { max(0, target - progress) }
    /// Tiles the quest asked for, counting its first one; rewards follow this, not the region's full size.
    public var growth: Int { target - start + 1 }
}

/// A level objective: grow any one connected region of `terrain` to `target` tiles.
public struct Goal: Hashable, Sendable, Identifiable {
    public let terrain: Terrain
    public let target: Int
    /// Size of the largest region of `terrain`, frozen once the goal is met.
    public internal(set) var progress = 0

    public init(terrain: Terrain, target: Int) {
        self.terrain = terrain
        self.target = target
    }

    public var id: Terrain { terrain }
    public var isMet: Bool { progress >= target }
    public var remaining: Int { max(0, target - progress) }
}

/// An unfinished goal or quest that was close when the tiles ran out.
public struct NearMiss: Hashable, Sendable {
    public let terrain: Terrain
    public let remaining: Int
    public let target: Int
}

public enum Outcome: Hashable, Sendable {
    case playing
    /// Every goal is met. Only levels have goals, so only levels are won.
    case won
    /// The stack is used up. In Coin mode, that finishes the valley.
    case outOfTiles
    /// The tile in hand fits nowhere and discarding isn't allowed (Coin mode). A power-up can rescue the run.
    case outOfRoom
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
    /// Goals this placement finished.
    public let metGoals: [Goal]
    /// Quests the game set on the board after this placement, to keep one going.
    public let startedQuests: [Quest]
    /// Unused-tile bonus, paid when this placement won the level.
    public let bonusPoints: Int
    /// Coins earned, in Coin mode.
    public let coins: Int
}

/// One run of Patchwork Valley: a level (fixed tiles, goals to meet) or Zen
/// (quests earn more tiles; play until they run out).
public struct ValleyGame: Sendable {
    public let rules: Rules
    public private(set) var board: Board
    public private(set) var score = 0
    /// Coins earned this run, in Coin mode.
    public private(set) var coins = 0
    /// Tiles still to play, including the current one.
    public private(set) var tilesLeft: Int
    public private(set) var tilesPlaced = 0
    /// Every Zen quest this run, in the order started.
    public private(set) var quests: [Quest] = []
    public private(set) var goals: [Goal]
    /// The dealt stack has been used up at least once. Tiles bought after that are a bonus.
    public private(set) var hasFinishedStack = false
    private var queue: [Tile] = []
    /// Ids for quests set on the board, counting down from -1 so they never meet a tile's id.
    private var nextBoardQuestID = -1
    /// No region could take a board quest, so the next tile dealt carries one.
    private var questOwed = false
    /// The rest of the dealt stack, after the visible tiles. Tiles beyond it (bought or
    /// earned) come straight from the generator.
    private var upcoming: [Tile] = []
    private var generator: TileGenerator

    public init(seed: UInt64, rules: Rules = Rules(), goals: [Goal] = []) {
        var generator = TileGenerator(seed: seed, riverChance: rules.riverChance, questChance: rules.questChance, lakeChance: rules.lakeChance)
        self.rules = rules
        if rules.craterRadius > 0 {
            let crater = Crater.generate(
                seed: seed ^ 0xC4A7_E500,
                radius: rules.craterRadius,
                roughness: rules.craterRoughness,
                maxOffset: rules.craterOffset,
                peakCount: rules.peakCount,
                lakeCount: rules.lakeCount,
                room: rules.startingTiles + 1
            )
            board = Board(starter: generator.makeCraterStarterTile(), crater: crater, requiresMatch: rules.requiresMatch)
        } else if rules.scatterRadius > 0 {
            let scatter = Scatter.generate(
                seed: seed ^ 0x5CA7_7E50,
                radius: rules.scatterRadius,
                peakShare: rules.scatterPeakShare,
                lakeShare: rules.scatterLakeShare
            )
            board = Board(starter: generator.makeStarterTile(), scatter: scatter)
        } else {
            board = Board(starter: generator.makeStarterTile())
        }
        // Deal the whole stack up front, so quests can be sized to the tiles still to come.
        upcoming = (0..<rules.startingTiles).map { _ in generator.makeTile() }
        self.generator = generator
        tilesLeft = rules.startingTiles
        self.goals = goals
        refreshGoals()
        refillQueue()
        keepAQuestGoing()
    }

    public init(level: LevelSpec) {
        var rules = Rules.levels
        rules.startingTiles = level.tiles
        self.init(seed: level.seed, rules: rules, goals: level.goals)
    }

    /// Starts from a prepared board and tile queue. Tests use this to set up exact situations.
    init(rules: Rules = Rules(), board: Board, queue: [Tile], tilesLeft: Int, goals: [Goal] = [], seed: UInt64 = 1, hasFinishedStack: Bool = false) {
        self.rules = rules
        self.board = board
        self.queue = queue
        self.tilesLeft = tilesLeft
        self.hasFinishedStack = hasFinishedStack
        self.goals = goals
        generator = TileGenerator(seed: seed, riverChance: rules.riverChance, questChance: rules.questChance, lakeChance: rules.lakeChance)
        refreshGoals()
        refillQueue()
        keepAQuestGoing()
    }

    public var current: Tile? { queue.first }
    public var next: Tile? { queue.dropFirst().first }
    public var activeQuests: [Quest] { quests.filter { $0.status == .active } }

    /// Quests a finished run ends without: those still going, and those its last tile closed off.
    public var unfinishedQuests: [Quest] {
        quests.filter { $0.status == .active || ($0.status == .failed && $0.endedAfter == tilesPlaced) }
    }

    public var outcome: Outcome {
        if !goals.isEmpty && goals.allSatisfy(\.isMet) { return .won }
        if tilesLeft == 0 { return .outOfTiles }
        // Out of room even with bought tiles in hand: power-ups can still rescue it, and a valley
        // whose stack was finished can be ended as done (`finishValley`), so it's never a loss.
        if !rules.allowsDiscard && isStuck { return .outOfRoom }
        return .playing
    }

    /// More tiles can be bought: the stack is empty and the run is otherwise over.
    public var canContinue: Bool { tilesLeft == 0 && outcome == .outOfTiles }

    /// Power-ups can change the run while playing, or rescue it when out of room.
    private var canUsePowerUps: Bool {
        !queue.isEmpty && (outcome == .playing || outcome == .outOfRoom)
    }

    public var isOver: Bool { outcome != .playing }

    /// The current tile fits nowhere, in any rotation.
    public var isStuck: Bool {
        guard let current else { return false }
        return !board.hasLegalPlacement(for: current)
    }

    /// Unfinished goals and quests within `nearMissGap` tiles of done, closest first.
    public var nearMisses: [NearMiss] {
        let fromGoals = goals.filter { !$0.isMet }.map { NearMiss(terrain: $0.terrain, remaining: $0.remaining, target: $0.target) }
        let fromQuests = activeQuests.map { NearMiss(terrain: $0.terrain, remaining: $0.remaining, target: $0.target) }
        return (fromGoals + fromQuests)
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

    /// Coins for edge matches and a perfect fit (Coin mode). Quest coins are added on completion.
    public func coins(for evaluation: PlacementEvaluation) -> Int {
        evaluation.matchingEdges.count * rules.coinsPerMatch + (evaluation.isPerfect ? rules.coinsPerPerfect : 0)
    }

    public mutating func rotateCurrent(clockwiseSteps steps: Int = 1) {
        guard !queue.isEmpty else { return }
        queue[0].rotateClockwise(steps)
    }

    /// Places the current tile. Returns nil and changes nothing when the run is over or the placement is illegal.
    @discardableResult
    public mutating func placeCurrent(at hex: Hex) -> PlacementResult? {
        guard outcome == .playing, let tile = current else { return nil }
        let preview = board.evaluate(tile, at: hex)
        guard preview.isLegal else { return nil }

        board.place(tile, at: hex)
        queue.removeFirst()
        tilesLeft -= 1
        tilesPlaced += 1

        // Judge the placement again now that it's down: placing lifts the fog off its neighbors,
        // so a newly seen lake can take a river (a match) and newly seen mountains close sides.
        let settled = board.evaluate(tile, at: hex)
        let evaluation = PlacementEvaluation(
            isLegal: true,
            matchingEdges: settled.matchingEdges,
            clashingEdges: settled.clashingEdges,
            isEnclosed: settled.isEnclosed
        )
        var earned = points(for: evaluation)
        var awarded = evaluation.isPerfect ? rules.perfectBonusTiles : 0
        var coinsEarned = coins(for: evaluation)

        var started: [Quest] = []
        if let spec = tile.quest {
            // A quest tile asks its region to grow by the same amount wherever it lands: joining a
            // big region raises the bar instead of winning outright.
            let joined = board.region(of: spec.terrain, from: hex).count
            var quest = Quest(id: tile.id, terrain: spec.terrain, target: joined + spec.target - 1, anchor: hex, progress: joined)
            quest.start = joined
            quests.append(quest)
            if joined > 1 { started.append(quest) }
        }

        var completed: [Quest] = []
        var failed: [Quest] = []
        for index in quests.indices where quests[index].status == .active {
            let quest = quests[index]
            let region = board.region(of: quest.terrain, from: quest.anchor)
            quests[index].progress = region.count
            if region.count >= quest.target {
                quests[index].status = .completed
                quests[index].endedAfter = tilesPlaced
                if rules.questsRewardTiles { awarded += rules.questReward(for: quest.growth) }
                earned += rules.questPoints(for: quest.target)
                coinsEarned += rules.questCoins(for: quest.growth)
                completed.append(quests[index])
            } else if board.openEdgeCount(of: region, terrain: quest.terrain) == 0 {
                quests[index].status = .failed
                quests[index].endedAfter = tilesPlaced
                failed.append(quests[index])
            }
        }

        let metGoals = refreshGoals()
        tilesLeft += awarded
        if tilesLeft == 0 { hasFinishedStack = true }
        let bonus = outcome == .won ? tilesLeft * rules.unusedTileBonus : 0

        score += earned + bonus
        coins += coinsEarned
        refillQueue()
        started += keepAQuestGoing()

        return PlacementResult(
            hex: hex,
            tile: tile,
            evaluation: evaluation,
            points: earned,
            tilesAwarded: awarded,
            completedQuests: completed,
            failedQuests: failed,
            metGoals: metGoals,
            startedQuests: started,
            bonusPoints: bonus,
            coins: coinsEarned
        )
    }

    /// Swap power-up: trades the current tile for a freshly dealt one. The stack count doesn't change.
    public mutating func swapCurrent() {
        guard canUsePowerUps else { return }
        queue[0] = generator.makeTile()
        keepAQuestGoing()
    }

    /// Wildcard power-up: the current tile becomes a wildcard that matches anything. The stack count doesn't change.
    public mutating func makeCurrentWild() {
        guard canUsePowerUps else { return }
        queue[0] = generator.makeWildTile()
        keepAQuestGoing()
    }

    /// Dynamite power-up: blasts a revealed mountain on the crater floor. Returns false when there's no such mountain.
    @discardableResult
    public mutating func clearMountain(at hex: Hex) -> Bool {
        guard canUsePowerUps else { return false }
        return board.clearMountain(at: hex)
    }

    /// Lantern power-up: shows every mountain and lake in the crater until the next tile is placed.
    public mutating func lightCrater() {
        guard canUsePowerUps else { return }
        board.light()
    }

    /// Ends a valley that ran out of room on its bought tiles. Its stack was already
    /// finished, so it counts as done, and the leftover tiles are dropped.
    public mutating func finishValley() {
        guard hasFinishedStack, outcome == .outOfRoom else { return }
        queue.removeAll()
        tilesLeft = 0
    }

    /// Throws away a tile that fits nowhere. It still costs a tile.
    public mutating func discardCurrent() {
        guard rules.allowsDiscard, outcome == .playing, isStuck else { return }
        queue.removeFirst()
        tilesLeft -= 1
        if tilesLeft == 0 { hasFinishedStack = true }
        refillQueue()
    }

    /// Adds tiles to a run that ran out so it keeps going.
    public mutating func continueRun(adding count: Int? = nil) {
        guard canContinue else { return }
        tilesLeft += count ?? rules.continueTiles
        refillQueue()
    }

    /// Updates unmet goals from the board and returns the ones that just became met.
    @discardableResult
    private mutating func refreshGoals() -> [Goal] {
        var newlyMet: [Goal] = []
        for index in goals.indices where !goals[index].isMet {
            goals[index].progress = board.largestRegion(of: goals[index].terrain).count
            if goals[index].isMet { newlyMet.append(goals[index]) }
        }
        return newlyMet
    }

    private mutating func refillQueue() {
        while queue.count < min(tilesLeft, rules.visibleTiles) {
            var tile = upcoming.isEmpty ? generator.makeTile() : upcoming.removeFirst()
            let pendingQuests = activeQuests.count + queue.filter { $0.quest != nil }.count
            if rules.questChance > 0 && pendingQuests < rules.maxActiveQuests {
                tile = generator.assignQuest(to: tile, base: rules.questBase(afterPlacing: tilesPlaced), supply: supply(), force: questOwed)
                if tile.quest != nil { questOwed = false }
            }
            queue.append(tile)
        }
    }

    /// Keeps at least one quest going (when the rules ask for it): if none is active and
    /// none is on a visible tile, sets one on a region already built, favoring the biggest.
    /// If no region can grow, the next tile dealt carries a quest instead.
    @discardableResult
    private mutating func keepAQuestGoing() -> [Quest] {
        guard rules.alwaysQuest, outcome == .playing, activeQuests.isEmpty,
              !queue.contains(where: { $0.quest != nil }) else { return [] }
        // Sometimes grow what's been built, sometimes a fresh quest on the tile coming up;
        // if one kind isn't possible, try the other.
        let boardFirst = generator.roll(1...100) <= Int(rules.boardQuestShare * 100)
        if boardFirst, let quest = makeBoardQuest() {
            quests.append(quest)
            return [quest]
        }
        if giveUpcomingTileAQuest() { return [] }
        if !boardFirst, let quest = makeBoardQuest() {
            quests.append(quest)
            return [quest]
        }
        questOwed = true
        return []
    }

    /// Puts a quest on the last visible tile (the next one, or the one in hand at the end of
    /// the stack), so it shows up right away. False when that tile can't take one.
    private mutating func giveUpcomingTileAQuest() -> Bool {
        guard let index = queue.indices.last else { return false }
        let tile = generator.assignQuest(to: queue[index], base: rules.questBase(afterPlacing: tilesPlaced), supply: supply(), force: true)
        guard tile.quest != nil else { return false }
        queue[index] = tile
        return true
    }

    /// A quest to grow one of the regions on the board by a few tiles, if any can grow and
    /// the tiles still to come can supply it. Bigger regions are likelier to be chosen.
    private mutating func makeBoardQuest() -> Quest? {
        let supply = supply()
        var options: [(Quest, Int)] = []
        let hexes = board.tiles.keys.sorted { ($0.r, $0.q) < ($1.r, $1.q) }
        for terrain in Terrain.questable {
            var seen: Set<Hex> = []
            for hex in hexes where !seen.contains(hex) && board[hex]?.contains(terrain) == true {
                let region = board.region(of: terrain, from: hex)
                seen.formUnion(region)
                guard board.openEdgeCount(of: region, terrain: terrain) > 0 else { continue }
                let share = terrain == .water ? 0.6 : 0.7
                let room = Int(Double(supply[terrain, default: 0]) * share)
                let wanted = terrain == .water ? generator.roll(2...3) : generator.roll(3...5) + rules.questTargetBonus / 2
                let growth = min(wanted, room)
                guard growth >= 2 else { continue }
                // Anchor the badge on the region tile that shows the most of the terrain.
                let tiles = region.filter { board[$0] != nil }.sorted { ($0.r, $0.q) < ($1.r, $1.q) }
                guard let anchor = tiles.max(by: { sides(of: terrain, at: $0) < sides(of: terrain, at: $1) }) else { continue }
                let size = region.count
                var quest = Quest(id: nextBoardQuestID, terrain: terrain, target: size + growth, anchor: anchor, progress: size)
                quest.start = size
                options.append((quest, size))
            }
        }
        guard !options.isEmpty else { return nil }
        nextBoardQuestID -= 1
        return generator.pick(options)
    }

    private func sides(of terrain: Terrain, at hex: Hex) -> Int {
        board[hex]?.edges.filter { $0 == terrain }.count ?? 0
    }

    /// Upcoming tiles (visible and still in the stack) that carry each quest terrain.
    private func supply() -> [Terrain: Int] {
        let ahead = queue + upcoming
        return Dictionary(uniqueKeysWithValues: Terrain.questable.map { terrain in
            (terrain, ahead.filter { $0.contains(terrain) }.count)
        })
    }
}
