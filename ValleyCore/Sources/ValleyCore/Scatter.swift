/// Zen's hidden peaks and lakes on the open plane: single peaks and short ridges, and
/// lakes set apart from each other, out to `radius` steps from the start. There's no rim,
/// the plane is clear beyond `radius`, and the start is never walled in.
public struct Scatter: Hashable, Sendable {
    public let peaks: Set<Hex>
    public let lakes: Set<Hex>

    public init(peaks: Set<Hex>, lakes: Set<Hex>) {
        self.peaks = peaks
        self.lakes = lakes
    }

    /// About `peakShare` of the hexes within `radius` get a peak and `lakeShare` a lake.
    public static func generate(seed: UInt64, radius: Int, peakShare: Double, lakeShare: Double) -> Scatter {
        var rng = SplitMix64(seed: seed)
        let area = Hex.within(radius: radius)
        // The start and its neighbors stay open, so the first placements always have somewhere to go.
        let protected = Set([Hex.origin] + Hex.origin.neighbors)
        let sites = area.filter { $0.distance(to: .origin) >= 2 }
        let peakTarget = Int((Double(area.count) * peakShare).rounded())
        let lakeTarget = Int((Double(area.count) * lakeShare).rounded())

        var peaks: Set<Hex> = []
        for _ in 0..<(peakTarget * 4) where peaks.count < peakTarget {
            // Mostly single peaks and short ridges: calmer than a crater.
            let roll = Int.random(in: 0..<10, using: &rng)
            let length = roll < 5 ? 1 : roll < 9 ? Int.random(in: 2...3, using: &rng) : 4
            var cell = sites[Int.random(in: 0..<sites.count, using: &rng)]
            var direction = Int.random(in: 0..<6, using: &rng)
            var ridge: Set<Hex> = []
            for _ in 0..<length {
                if cell.distance(to: .origin) <= radius, !protected.contains(cell) { ridge.insert(cell) }
                // Ridges mostly run straight, with the odd bend.
                direction = Hex.wrap(direction + [0, 0, 0, 1, -1][Int.random(in: 0..<5, using: &rng)])
                cell = cell.neighbor(direction)
            }
            let candidate = peaks.union(ridge)
            if isOpen(radius: radius, blocked: candidate) { peaks = candidate }
        }

        // Lakes sit apart from each other, so each one is its own find.
        var lakes: Set<Hex> = []
        for _ in 0..<(lakeTarget * 10) where lakes.count < lakeTarget {
            let cell = sites[Int.random(in: 0..<sites.count, using: &rng)]
            guard !peaks.contains(cell), !lakes.contains(cell),
                  !cell.neighbors.contains(where: lakes.contains) else { continue }
            if isOpen(radius: radius, blocked: peaks.union(lakes).union([cell])) { lakes.insert(cell) }
        }
        return Scatter(peaks: peaks, lakes: lakes)
    }

    /// The start still reaches the edge of the scattered area, so the valley can always grow.
    static func isOpen(radius: Int, blocked: Set<Hex>) -> Bool {
        var seen: Set<Hex> = [.origin]
        var pending = [Hex.origin]
        while let hex = pending.popLast() {
            if hex.distance(to: .origin) >= radius { return true }
            for next in hex.neighbors where !blocked.contains(next) && !seen.contains(next) {
                seen.insert(next)
                pending.append(next)
            }
        }
        return false
    }
}
