/// A finished valley with nothing in fog, for the gallery: every tile where it lies, plus
/// every mountain and lake, found or not. Plain data, so it can be saved and drawn again at any size.
public struct ValleyPicture: Codable, Hashable, Sendable {
    public struct PlacedTile: Codable, Hashable, Sendable {
        public let hex: Hex
        public let edges: [Terrain]

        public init(hex: Hex, edges: [Terrain]) {
            self.hex = hex
            self.edges = edges
        }
    }

    public let tiles: [PlacedTile]
    /// Mountains standing on the floor, or anywhere on the open plane.
    public let peaks: [Hex]
    /// The crater's ring of mountains; empty on the open plane.
    public let rim: [Hex]
    public let lakes: [Hex]

    public init(tiles: [PlacedTile], peaks: [Hex], rim: [Hex], lakes: [Hex]) {
        self.tiles = tiles
        self.peaks = peaks
        self.rim = rim
        self.lakes = lakes
    }

    /// Everything on `board`, fog or not. Lists are sorted so the same board always saves the same way.
    public init(board: Board) {
        let order: (Hex, Hex) -> Bool = { ($0.r, $0.q) < ($1.r, $1.q) }
        let floor = board.floor
        tiles = board.tiles
            .map { PlacedTile(hex: $0.key, edges: $0.value.edges) }
            .sorted { order($0.hex, $1.hex) }
        peaks = board.mountains.filter { floor?.contains($0) ?? true }.sorted(by: order)
        rim = board.mountains.filter { hex in floor.map { !$0.contains(hex) } ?? false }.sorted(by: order)
        lakes = board.lakes.sorted(by: order)
    }

    /// Every hex the picture covers.
    public var hexes: [Hex] { tiles.map(\.hex) + peaks + rim + lakes }
}
