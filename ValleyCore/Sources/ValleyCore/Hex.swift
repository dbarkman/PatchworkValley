/// Axial coordinate on a pointy-top hex grid.
///
/// Direction `i` points `60° × i` counter-clockwise from east, so directions
/// `i` and `i + 3` are opposites. A tile's edge `i` faces its neighbor in
/// direction `i`.
public struct Hex: Hashable, Sendable, CustomStringConvertible {
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

    public var description: String { "(\(q), \(r))" }
}
