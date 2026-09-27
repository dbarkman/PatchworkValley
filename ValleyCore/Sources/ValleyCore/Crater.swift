import Foundation

/// A Coin mode valley's shape: an irregular floor ringed by a mountain rim, with
/// single peaks, ridges and lakes on the floor. Tiles only go on open floor, and
/// the generator always leaves room for the whole stack.
public struct Crater: Hashable, Sendable {
    /// The floor's average radius, in hex steps. The outline wanders about two steps either way.
    public let radius: Int
    /// Every hex inside the rim, peaks and lakes included.
    public let floor: Set<Hex>
    /// The ring of mountains around the floor.
    public let rim: Set<Hex>
    /// Mountains standing on the floor.
    public let peaks: Set<Hex>
    /// Lakes on the floor: rivers can flow into them, and land can border them.
    public let lakes: Set<Hex>

    public init(radius: Int, floor: Set<Hex>, rim: Set<Hex>, peaks: Set<Hex>, lakes: Set<Hex> = []) {
        self.radius = radius
        self.floor = floor
        self.rim = rim
        self.peaks = peaks
        self.lakes = lakes
    }

    public var mountains: Set<Hex> { rim.union(peaks) }

    /// Open floor connected to the starting tile.
    public var reachableFloor: Int { Self.reachable(floor: floor, blocked: peaks.union(lakes)) }

    /// Builds a crater of `radius` with about `peakCount` peaks and `lakeCount` lakes,
    /// keeping at least `room` open floor cells connected to the start (the stack plus the starter).
    /// `roughness` (0 to 1) sets how far the outline wanders, from round to ragged, and the
    /// crater's center can sit up to `maxOffset` steps from the start, so play may begin near a wall.
    public static func generate(
        seed: UInt64,
        radius: Int,
        roughness: Double = 1,
        maxOffset: Int = 0,
        peakCount: Int,
        lakeCount: Int = 0,
        room: Int
    ) -> Crater {
        var rng = SplitMix64(seed: seed)
        let floorList = outline(radius: radius, roughness: roughness, maxOffset: maxOffset, room: room, rng: &rng)
        let floor = Set(floorList)
        let rim = Set(floorList.flatMap(\.neighbors)).subtracting(floor)
        // The start and its neighbors stay open, so the first placements always have somewhere to go.
        let protected = Set([Hex.origin] + Hex.origin.neighbors)
        let sites = floorList.filter { $0.distance(to: .origin) >= 2 }
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
            if reachable(floor: floor, blocked: candidate) >= room {
                peaks = candidate
            }
        }

        // Lakes sit apart from each other, so each one is its own find.
        var lakes: Set<Hex> = []
        for _ in 0..<100 where lakes.count < lakeCount {
            let cell = sites[Int.random(in: 0..<sites.count, using: &rng)]
            guard !peaks.contains(cell), !protected.contains(cell), !lakes.contains(cell),
                  !cell.neighbors.contains(where: lakes.contains) else { continue }
            if reachable(floor: floor, blocked: peaks.union(lakes).union([cell])) >= room {
                lakes.insert(cell)
            }
        }
        return Crater(radius: radius, floor: floor, rim: rim, peaks: peaks, lakes: lakes)
    }

    /// An organic floor: its edge wanders in and out around its center, following a few
    /// overlapping waves scaled by `roughness`, so every crater has its own bays and points.
    /// Returned in a fixed order, connected, and always holding the start area and at least
    /// `room` hexes plus a little slack.
    private static func outline(radius: Int, roughness: Double, maxOffset: Int, room: Int, rng: inout SplitMix64) -> [Hex] {
        let startArea = [Hex.origin] + Hex.origin.neighbors
        var attempts = 0
        while true {
            attempts += 1
            // A wandering center can squeeze the start; after enough misses, center it so this always ends.
            let offsetLimit = attempts > 30 ? 0 : maxOffset
            var center = Hex.origin
            for _ in 0..<Int.random(in: 0...offsetLimit, using: &rng) {
                center = center.neighbor(Int.random(in: 0..<6, using: &rng))
            }
            let waves = (2...4).map { frequency in
                (amplitude: roughness * Double.random(in: 0.2...0.6, using: &rng),
                 frequency: Double(frequency),
                 phase: Double.random(in: 0..<(2 * .pi), using: &rng))
            }
            let candidates = Hex.within(radius: radius + 2).map { Hex($0.q + center.q, $0.r + center.r) }
            let floor = candidates.filter { hex in
                // Position relative to the center, in hex steps: neighbors are one step apart.
                let q = Double(hex.q - center.q)
                let r = Double(hex.r - center.r)
                let x = q + r / 2
                let y = -r * 3.squareRoot() / 2
                let reach = Double(radius) + 0.3 + waves.reduce(0) { $0 + $1.amplitude * sin($1.frequency * atan2(y, x) + $1.phase) }
                return (x * x + y * y).squareRoot() <= reach
            }
            let floorSet = Set(floor)
            guard startArea.allSatisfy(floorSet.contains) else { continue }
            // Keep only floor joined to the start, in case the edge pinched off a sliver.
            let connected = reachableSet(floor: floorSet, blocked: [])
            let kept = floor.filter(connected.contains)
            if kept.count >= room + 8 { return kept }
        }
    }

    private static func reachable(floor: Set<Hex>, blocked: Set<Hex>) -> Int {
        reachableSet(floor: floor, blocked: blocked).count
    }

    private static func reachableSet(floor: Set<Hex>, blocked: Set<Hex>) -> Set<Hex> {
        var seen: Set<Hex> = [.origin]
        var pending = [Hex.origin]
        while let hex = pending.popLast() {
            for next in hex.neighbors where floor.contains(next) && !blocked.contains(next) && !seen.contains(next) {
                seen.insert(next)
                pending.append(next)
            }
        }
        return seen
    }
}
