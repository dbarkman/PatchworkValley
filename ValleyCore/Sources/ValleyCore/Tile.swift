public enum Terrain: String, CaseIterable, Hashable, Sendable {
    case meadow, forest, field, village, water

    /// Terrains a quest can ask the player to grow.
    public static let questable: [Terrain] = [.forest, .field, .village, .water]
}

/// A quest printed on a tile: grow the region of `terrain` it joins to `target` tiles.
public struct QuestSpec: Hashable, Sendable {
    public let terrain: Terrain
    public let target: Int

    public init(terrain: Terrain, target: Int) {
        self.terrain = terrain
        self.target = target
    }
}

/// A hex tile. Edge `i` faces the neighbor in direction `i` (see `Hex`).
public struct Tile: Hashable, Sendable, Identifiable {
    public let id: Int
    public private(set) var edges: [Terrain]
    public let quest: QuestSpec?

    public init(id: Int, edges: [Terrain], quest: QuestSpec? = nil) {
        precondition(edges.count == 6, "A hex tile has six edges")
        self.id = id
        self.edges = edges
        self.quest = quest
    }

    public func edge(_ direction: Int) -> Terrain { edges[Hex.wrap(direction)] }

    public func contains(_ terrain: Terrain) -> Bool { edges.contains(terrain) }

    /// Rotates 60° clockwise per step; negative steps rotate counter-clockwise.
    public mutating func rotateClockwise(_ steps: Int = 1) {
        let shift = Hex.wrap(steps)
        let old = edges
        edges = (0..<6).map { old[($0 + shift) % 6] }
    }

    public func rotatedClockwise(_ steps: Int = 1) -> Tile {
        var copy = self
        copy.rotateClockwise(steps)
        return copy
    }
}
