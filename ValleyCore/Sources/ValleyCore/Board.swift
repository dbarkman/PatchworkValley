/// How a tile would sit at a given spot.
public struct PlacementEvaluation: Hashable, Sendable {
    /// The spot is open and every river edge meets a river edge.
    public let isLegal: Bool
    /// Directions whose edge matches the neighbor's facing edge.
    public let matchingEdges: [Int]
    /// Directions whose edge differs from the neighbor's facing edge.
    public let clashingEdges: [Int]
    /// Every side faces a tile, a mountain or a found lake; nothing more can ever touch this spot.
    public let isEnclosed: Bool

    /// Boxed in on all sides, clashing with no neighbor, and matching at least two sides.
    public var isPerfect: Bool { isLegal && isEnclosed && clashingEdges.isEmpty && matchingEdges.count >= 2 }
}

/// The placed tiles of a valley. On the open plane tiles can spread forever, around Zen's
/// hidden peaks and lakes; in a crater (Coin mode) they stay on the floor and mountains block the way.
public struct Board: Sendable {
    public private(set) var tiles: [Hex: Tile] = [:]
    /// Empty floor touching the valley: the only places a tile can go.
    public private(set) var openSlots: Set<Hex> = []
    /// Every mountain, seen or not: a crater's rim and floor peaks, or Zen's scattered peaks. Empty in Levels.
    public private(set) var mountains: Set<Hex> = []
    /// Lakes on a crater floor or Zen's plane, seen or not. A river edge touching one counts as a match.
    public private(set) var lakes: Set<Hex> = []
    /// A Lantern lights every mountain and lake until the next tile is placed.
    public private(set) var isLit = false
    /// Mountains and lakes that have touched a tile. They stay in view for good.
    private var seenMountains: Set<Hex> = []
    private var seenLakes: Set<Hex> = []

    /// Mountains in view: those touching a tile, or every one while a Lantern is lit.
    public var revealedMountains: Set<Hex> { isLit ? mountains : seenMountains }
    /// Lakes in view: those touching a tile, or every one while a Lantern is lit.
    public var revealedLakes: Set<Hex> { isLit ? lakes : seenLakes }
    /// Hexes inside the crater rim, or nil on the open plane.
    public let floor: Set<Hex>?
    /// Every placement must match at least one neighboring edge.
    public let requiresMatch: Bool

    /// The open plane: no mountains, no edge, any placement that respects rivers.
    public init(starter: Tile) {
        floor = nil
        requiresMatch = false
        place(starter, at: .origin)
    }

    /// The open plane with hidden peaks and lakes (Zen): no rim and no match rule.
    public init(starter: Tile, scatter: Scatter) {
        floor = nil
        mountains = scatter.peaks
        lakes = scatter.lakes
        requiresMatch = false
        place(starter, at: .origin)
    }

    public init(starter: Tile, crater: Crater, requiresMatch: Bool) {
        floor = crater.floor
        mountains = crater.mountains
        lakes = crater.lakes
        self.requiresMatch = requiresMatch
        place(starter, at: .origin)
    }

    /// Floor that no mountain stands on.
    public func isBuildable(_ hex: Hex) -> Bool {
        !mountains.contains(hex) && !lakes.contains(hex) && (floor?.contains(hex) ?? true)
    }

    /// A mountain or lake the player hasn't seen yet.
    public func isInFog(_ hex: Hex) -> Bool {
        (mountains.contains(hex) && !revealedMountains.contains(hex)) || (lakes.contains(hex) && !revealedLakes.contains(hex))
    }

    /// Revealed mountains standing on the floor. The rim can't be blasted.
    public var clearableMountains: Set<Hex> {
        revealedMountains.filter { floor?.contains($0) == true }
    }

    public subscript(hex: Hex) -> Tile? { tiles[hex] }

    public func evaluate(_ tile: Tile, at hex: Hex) -> PlacementEvaluation {
        var matching: [Int] = []
        var clashing: [Int] = []
        var isLegal = openSlots.contains(hex)
        var isEnclosed = true
        for direction in 0..<6 {
            let neighborHex = hex.neighbor(direction)
            guard let neighbor = tiles[neighborHex] else {
                if revealedLakes.contains(neighborHex) {
                    // A river flows into a lake; land just borders it.
                    if tile.edge(direction).counts(as: .water) { matching.append(direction) }
                    continue
                }
                // Open floor, or anything still in fog, reads as open: the preview mustn't give the fog away.
                if isBuildable(neighborHex) || isInFog(neighborHex) { isEnclosed = false }
                continue
            }
            let mine = tile.edge(direction)
            let theirs = neighbor.edge(Hex.opposite(direction))
            if mine.counts(as: theirs) || theirs.counts(as: mine) {
                matching.append(direction)
            } else {
                clashing.append(direction)
            }
            // Rivers must flow into rivers. A wildcard edge can be a river.
            if mine != .wild && theirs != .wild && (mine == .water) != (theirs == .water) { isLegal = false }
        }
        if requiresMatch && matching.isEmpty { isLegal = false }
        return PlacementEvaluation(isLegal: isLegal, matchingEdges: matching, clashingEdges: clashing, isEnclosed: isEnclosed)
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
            if lakes.contains(hex) {
                // A lake joins every river that flows into it.
                for direction in 0..<6 {
                    let next = hex.neighbor(direction)
                    guard !region.contains(next),
                          let nextTile = lookup(next),
                          nextTile.edge(Hex.opposite(direction)).counts(as: .water) else { continue }
                    region.insert(next)
                    pending.append(next)
                }
                continue
            }
            guard let tile = lookup(hex) else { continue }
            for direction in 0..<6 where tile.edge(direction).counts(as: terrain) {
                let next = hex.neighbor(direction)
                guard !region.contains(next) else { continue }
                if terrain == .water && lakes.contains(next) {
                    region.insert(next)
                    pending.append(next)
                    continue
                }
                guard let nextTile = lookup(next),
                      nextTile.edge(Hex.opposite(direction)).counts(as: terrain) else { continue }
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
            if lakes.contains(hex) {
                // A new river can still flow into the lake from any open side.
                count += hex.neighbors.filter { tiles[$0] == nil && isBuildable($0) }.count
                continue
            }
            guard let tile = tiles[hex] else { continue }
            for direction in 0..<6 where tile.edge(direction).counts(as: terrain) {
                let next = hex.neighbor(direction)
                if tiles[next] == nil && isBuildable(next) { count += 1 }
            }
        }
        return count
    }

    mutating func place(_ tile: Tile, at hex: Hex) {
        tiles[hex] = tile
        openSlots.remove(hex)
        // Placing a tile puts a Lantern out: the fog returns to everything not touching a tile.
        isLit = false
        for neighbor in hex.neighbors where tiles[neighbor] == nil {
            if mountains.contains(neighbor) {
                // The fog lifts: a mountain or lake next to a tile comes into view.
                seenMountains.insert(neighbor)
            } else if lakes.contains(neighbor) {
                seenLakes.insert(neighbor)
            } else if isBuildable(neighbor) {
                openSlots.insert(neighbor)
            }
        }
    }

    /// Dynamite: blasts a revealed floor mountain, leaving open floor.
    @discardableResult
    mutating func clearMountain(at hex: Hex) -> Bool {
        guard clearableMountains.contains(hex) else { return false }
        mountains.remove(hex)
        seenMountains.remove(hex)
        if hex.neighbors.contains(where: { tiles[$0] != nil }) { openSlots.insert(hex) }
        return true
    }

    /// Lantern: lights every mountain and lake in the crater until the next tile is placed.
    mutating func light() {
        isLit = true
    }

    /// A copy with every mountain and lake in view, for looking over a finished valley.
    public func lit() -> Board {
        var copy = self
        copy.light()
        return copy
    }
}
