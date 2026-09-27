/// Axial coordinate on a pointy-top hex grid.
///
/// Direction `i` points `60° × i` counter-clockwise from east, so directions
/// `i` and `i + 3` are opposites. A tile's edge `i` faces its neighbor in
/// direction `i`.
public struct Hex: Hashable, Sendable, Codable, CustomStringConvertible {
    public let q: Int
    public let r: Int

    public init(_ q: Int, _ r: Int) {
        self.q = q
        self.r = r
    }

    public static let origin = Hex(0, 0)

    private static let offsets: [(q: Int, r: Int)] = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]

    public func neighbor(_ direction: Int) -> Hex {
        let offset = Hex.offsets[Hex.wrap(direction)]
        return Hex(q + offset.q, r + offset.r)
    }

    public var neighbors: [Hex] { (0..<6).map { neighbor($0) } }

    public static func opposite(_ direction: Int) -> Int { wrap(direction + 3) }

    /// Folds any integer into a direction in `0..<6`.
    public static func wrap(_ direction: Int) -> Int { ((direction % 6) + 6) % 6 }

    /// Steps between two hexes.
    public func distance(to other: Hex) -> Int {
        let dq = q - other.q
        let dr = r - other.r
        return (abs(dq) + abs(dr) + abs(dq + dr)) / 2
    }

    /// Every hex within `radius` steps of the origin, in a fixed order.
    public static func within(radius: Int) -> [Hex] {
        var hexes: [Hex] = []
        for q in -radius...radius {
            for r in max(-radius, -q - radius)...min(radius, -q + radius) {
                hexes.append(Hex(q, r))
            }
        }
        return hexes
    }

    public var description: String { "(\(q), \(r))" }
}
