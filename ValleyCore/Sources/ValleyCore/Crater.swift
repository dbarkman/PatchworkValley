/// A Coin mode valley's shape: a hexagonal floor ringed by a mountain rim, with
/// single peaks and ridges standing on the floor. Tiles only go on open floor,
/// and the generator always leaves room for the whole stack.
public struct Crater: Hashable, Sendable {
    public let radius: Int
    /// Every hex inside the rim, peaks included.
    public let floor: Set<Hex>
    /// The ring of mountains around the floor.
    public let rim: Set<Hex>
    /// Mountains standing on the floor.
    public let peaks: Set<Hex>

    public var mountains: Set<Hex> { rim.union(peaks) }

    /// Open floor connected to the starting tile.
    public var reachableFloor: Int { Self.reachable(floor: floor, peaks: peaks) }

    /// Builds a crater of `radius` with about `peakCount` peaks, keeping at least
    /// `room` open floor cells connected to the start (the stack plus the starter).
    public static func generate(seed: UInt64, radius: Int, peakCount: Int, room: Int) -> Crater {
        let floorList = Hex.within(radius: radius)
        let floor = Set(floorList)
        let rim = Set(Hex.within(radius: radius + 1)).subtracting(floor)
        // The start and its neighbors stay open, so the first placements always have somewhere to go.
        let protected = Set([Hex.origin] + Hex.origin.neighbors)
        let sites = floorList.filter { $0.distance(to: .origin) >= 2 }
        var rng = SplitMix64(seed: seed)
        var peaks: Set<Hex> = []

        for _ in 0..<200 where peaks.count < peakCount {
            // Mostly single peaks and short ridges, sometimes a long ridge.
            let roll = Int.random(in: 0..<10, using: &rng)
            let length = roll < 4 ? 1 : roll < 8 ? Int.random(in: 2...4, using: &rng) : Int.random(in: 5...6, using: &rng)
            var cell = sites[Int.random(in: 0..<sites.count, using: &rng)]
            var direction = Int.random(in: 0..<6, using: &rng)
            var ridge: Set<Hex> = []
            for _ in 0..<length {
                if floor.contains(cell), !protected.contains(cell) { ridge.insert(cell) }
                // Ridges mostly run straight, with the odd bend.
                direction = Hex.wrap(direction + [0, 0, 0, 1, -1][Int.random(in: 0..<5, using: &rng)])
                cell = cell.neighbor(direction)
            }
            let candidate = peaks.union(ridge)
            if reachable(floor: floor, peaks: candidate) >= room {
                peaks = candidate
            }
        }
        return Crater(radius: radius, floor: floor, rim: rim, peaks: peaks)
    }

    private static func reachable(floor: Set<Hex>, peaks: Set<Hex>) -> Int {
        var seen: Set<Hex> = [.origin]
        var pending = [Hex.origin]
        while let hex = pending.popLast() {
            for next in hex.neighbors where floor.contains(next) && !peaks.contains(next) && !seen.contains(next) {
                seen.insert(next)
                pending.append(next)
            }
        }
        return seen.count
    }
}
