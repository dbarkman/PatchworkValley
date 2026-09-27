/// Small, fast, seedable RNG so a seed always replays the same valley.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Deterministic tile factory. Land edges come in 1–3 contiguous bands; a river
/// crosses a tile on two edges, or ends in a lake on one.
public struct TileGenerator: Sendable {
    private var rng: SplitMix64
    private var nextID = 1
    private let riverChance: Double
    private let questChance: Double
    /// Share of water tiles that are lakes (one river edge into a pond) rather than rivers.
    private let lakeChance: Double

    private static let landWeights: [(Terrain, Int)] = [(.meadow, 3), (.forest, 3), (.field, 2), (.village, 1)]
    private static let bandWeights: [(Int, Int)] = [(1, 2), (2, 5), (3, 3)]
    /// Clockwise distance from a river's first edge to its second: straight runs are twice as common as bends.
    private static let riverTurnWeights: [(Int, Int)] = [(3, 2), (2, 1), (4, 1)]

    public init(seed: UInt64, riverChance: Double, questChance: Double, lakeChance: Double = 0) {
        rng = SplitMix64(seed: seed)
        self.riverChance = riverChance
        self.questChance = questChance
        self.lakeChance = lakeChance
    }

    /// The first tile of every valley: land only, no river, no quest.
    public mutating func makeStarterTile() -> Tile {
        Tile(id: 0, edges: makeLandEdges())
    }

    /// A tile with no quest; `assignQuest` adds one once the tile is dealt.
    public mutating func makeTile() -> Tile {
        var edges = makeLandEdges()
        if chance(riverChance) {
            if lakeChance > 0 && chance(lakeChance) {
                edges[Int.random(in: 0..<6, using: &rng)] = .water
            } else {
                addRiver(to: &edges)
            }
        }
        // One more draw per tile: the designed levels' seeds depend on this exact stream.
        _ = chance(questChance)
        defer { nextID += 1 }
        return Tile(id: nextID, edges: edges)
    }

    /// Maybe gives `tile` a quest, sized so the tiles still to come can finish it.
    /// `supply` counts the upcoming tiles that carry each terrain.
    public mutating func assignQuest(to tile: Tile, base: Int, supply: [Terrain: Int]) -> Tile {
        guard chance(questChance) else { return tile }
        var options: [QuestSpec] = []
        for terrain in Terrain.questable where tile.contains(terrain) {
            let wanted = terrain == .water
                ? max(3, base / 2 + Int.random(in: 0...2, using: &rng))
                : base + Int.random(in: 0...4, using: &rng)
            // The quest tile itself, plus most of the matching tiles still to come.
            let share = terrain == .water ? 0.6 : 0.7
            let reachable = 1 + Int(Double(supply[terrain, default: 0]) * share)
            let target = min(wanted, reachable)
            if target >= 3 { options.append(QuestSpec(terrain: terrain, target: target)) }
        }
        guard let quest = options.randomElement(using: &rng) else { return tile }
        return Tile(id: tile.id, edges: tile.edges, quest: quest)
    }

    /// A crater's first tile: all four land terrains in bands, so the first tile
    /// dealt always has a side it can match.
    public mutating func makeCraterStarterTile() -> Tile {
        let bands: [Terrain] = [.meadow, .meadow, .forest, .field, .field, .village]
        let turn = Int.random(in: 0..<6, using: &rng)
        return Tile(id: 0, edges: (0..<6).map { bands[($0 + turn) % 6] })
    }

    /// A tile from the Wildcard power-up: every edge matches anything.
    public mutating func makeWildTile() -> Tile {
        defer { nextID += 1 }
        return Tile(id: nextID, edges: Array(repeating: .wild, count: 6))
    }

    private mutating func makeLandEdges() -> [Terrain] {
        let bandCount = pick(Self.bandWeights)
        var lengths = Array(repeating: 1, count: bandCount)
        for _ in 0..<(6 - bandCount) {
            lengths[Int.random(in: 0..<bandCount, using: &rng)] += 1
        }

        // Neighboring bands differ, including the last band wrapping around to the first.
        var terrains: [Terrain] = []
        for index in 0..<bandCount {
            var terrain = pick(Self.landWeights)
            while (index > 0 && terrain == terrains[index - 1])
                || (index == bandCount - 1 && index > 0 && terrain == terrains[0]) {
                terrain = pick(Self.landWeights)
            }
            terrains.append(terrain)
        }

        var edges = Array(repeating: Terrain.meadow, count: 6)
        var direction = Int.random(in: 0..<6, using: &rng)
        for (terrain, length) in zip(terrains, lengths) {
            for _ in 0..<length {
                edges[direction] = terrain
                direction = (direction + 1) % 6
            }
        }
        return edges
    }

    private mutating func addRiver(to edges: inout [Terrain]) {
        let start = Int.random(in: 0..<6, using: &rng)
        let turn = pick(Self.riverTurnWeights)
        edges[start] = .water
        edges[(start + turn) % 6] = .water
    }

    private mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &rng) < probability
    }

    private mutating func pick<T>(_ weighted: [(T, Int)]) -> T {
        let total = weighted.reduce(0) { $0 + $1.1 }
        var roll = Int.random(in: 0..<total, using: &rng)
        for (value, weight) in weighted {
            if roll < weight { return value }
            roll -= weight
        }
        return weighted[weighted.count - 1].0
    }
}
