/// How a tile would sit at a given spot.
public struct PlacementEvaluation: Hashable, Sendable {
    /// The spot is open and every river edge meets a river edge.
    public let isLegal: Bool
    /// Directions whose edge matches the neighbor's facing edge.
    public let matchingEdges: [Int]
    /// Directions whose edge differs from the neighbor's facing edge.
    public let clashingEdges: [Int]

    /// All six sides have neighbors and all six match.
    public var isPerfect: Bool { isLegal && matchingEdges.count == 6 }
}

/// The placed tiles of a valley. Tiles only ever get added.
public struct Board: Sendable {
    public private(set) var tiles: [Hex: Tile] = [:]
    /// Empty hexes touching the valley: the only places a tile can go.
    public private(set) var openSlots: Set<Hex> = []

    public init(starter: Tile) {
        place(starter, at: .origin)
    }

    public subscript(hex: Hex) -> Tile? { tiles[hex] }

    public func evaluate(_ tile: Tile, at hex: Hex) -> PlacementEvaluation {
        var matching: [Int] = []
        var clashing: [Int] = []
        var isLegal = openSlots.contains(hex)
        for direction in 0..<6 {
            guard let neighbor = tiles[hex.neighbor(direction)] else { continue }
            let mine = tile.edge(direction)
            let theirs = neighbor.edge(Hex.opposite(direction))
            if mine == theirs {
                matching.append(direction)
            } else {
                clashing.append(direction)
            }
            // Rivers must flow into rivers.
            if (mine == .water) != (theirs == .water) { isLegal = false }
        }
        return PlacementEvaluation(isLegal: isLegal, matchingEdges: matching, clashingEdges: clashing)
    }

    public func canPlace(_ tile: Tile, at hex: Hex) -> Bool {
        evaluate(tile, at: hex).isLegal
    }

    /// Clockwise steps that give `tile` its best legal fit at `hex`, or nil when no rotation fits.
    public func bestRotation(for tile: Tile, at hex: Hex) -> Int? {
        var best: (steps: Int, matches: Int)?
        for steps in 0..<6 {
            let evaluation = evaluate(tile.rotatedClockwise(steps), at: hex)
            guard evaluation.isLegal, evaluation.matchingEdges.count > (best?.matches ?? -1) else { continue }
            best = (steps, evaluation.matchingEdges.count)
        }
        return best?.steps
    }

    public func hasLegalPlacement(for tile: Tile) -> Bool {
        openSlots.contains { bestRotation(for: tile, at: $0) != nil }
    }

    /// Hexes joined to `start` through touching edges of `terrain`.
    public func region(of terrain: Terrain, from start: Hex) -> Set<Hex> {
        region(of: terrain, from: start) { tiles[$0] }
    }

    /// The region `tile` would join if it were placed at `hex`, without placing it.
    public func region(of terrain: Terrain, from hex: Hex, placing tile: Tile) -> Set<Hex> {
        region(of: terrain, from: hex) { $0 == hex ? tile : tiles[$0] }
    }

    /// The biggest connected region of `terrain` anywhere on the board.
    public func largestRegion(of terrain: Terrain) -> Set<Hex> {
        var seen: Set<Hex> = []
        var largest: Set<Hex> = []
        for (hex, tile) in tiles where tile.contains(terrain) && !seen.contains(hex) {
            let region = region(of: terrain, from: hex)
            seen.formUnion(region)
            if region.count > largest.count { largest = region }
        }
        return largest
    }

    private func region(of terrain: Terrain, from start: Hex, lookup: (Hex) -> Tile?) -> Set<Hex> {
        guard let startTile = lookup(start), startTile.contains(terrain) else { return [] }
        var region: Set<Hex> = [start]
        var pending = [start]
        while let hex = pending.popLast() {
            guard let tile = lookup(hex) else { continue }
            for direction in 0..<6 where tile.edge(direction) == terrain {
                let next = hex.neighbor(direction)
                guard !region.contains(next),
                      let nextTile = lookup(next),
                      nextTile.edge(Hex.opposite(direction)) == terrain else { continue }
                region.insert(next)
                pending.append(next)
            }
        }
        return region
    }

    /// Edges of `terrain` in `region` that face an empty hex. Zero means the region can never grow.
    public func openEdgeCount(of region: Set<Hex>, terrain: Terrain) -> Int {
        var count = 0
        for hex in region {
            guard let tile = tiles[hex] else { continue }
            for direction in 0..<6 where tile.edge(direction) == terrain && tiles[hex.neighbor(direction)] == nil {
                count += 1
            }
        }
        return count
    }

    mutating func place(_ tile: Tile, at hex: Hex) {
        tiles[hex] = tile
        openSlots.remove(hex)
        for neighbor in hex.neighbors where tiles[neighbor] == nil {
            openSlots.insert(neighbor)
        }
    }
}
