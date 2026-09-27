import CoreGraphics
import UIKit
import ValleyCore

/// The drawing of one tile as plain paths, so SpriteKit (the board) and
/// SwiftUI Canvas (the tray preview) render identical tiles.
struct TileDrawing {
    struct Layer {
        let path: CGPath
        var fill: UIColor?
        var stroke: UIColor?
        var lineWidth: CGFloat = 0
        var lineCap: CGLineCap = .butt
    }

    static func layers(for edges: [Terrain], geometry: HexGeometry) -> [Layer] {
        var layers: [Layer] = []
        let r = geometry.radius

        // Ground: one wedge per edge. River edges sit on meadow banks; wildcard edges are a patchwork of every terrain.
        for direction in 0..<6 {
            let color = switch edges[direction] {
            case .water: Terrain.meadow.uiColor
            case .wild: wildPatchwork[direction].uiColor
            default: edges[direction].uiColor
            }
            // Stroking with the fill color hides hairline seams between wedges.
            layers.append(Layer(path: geometry.wedgePath(direction), fill: color, stroke: color, lineWidth: 1))
        }

        for direction in 0..<6 {
            layers += details(for: edges[direction], direction: direction, geometry: geometry)
        }

        let riverEdges = (0..<6).filter { edges[$0] == .water }
        if !riverEdges.isEmpty {
            let river = CGMutablePath()
            for direction in riverEdges {
                river.move(to: .zero)
                river.addLine(to: geometry.edgeMidpoint(direction))
            }
            let width = r * 0.3
            layers.append(Layer(path: river, stroke: Terrain.water.uiColor, lineWidth: width))
            // Two strips meet in a rounded bend; a lone strip ends in a lake.
            let pond = riverEdges.count == 1 ? r * 0.62 : width
            let joint = CGPath(ellipseIn: CGRect(x: -pond / 2, y: -pond / 2, width: pond, height: pond), transform: nil)
            layers.append(Layer(path: joint, fill: Terrain.water.uiColor, stroke: riverEdges.count == 1 ? Terrain.water.detailColor : nil, lineWidth: 1.5))
        }

        if edges.contains(.wild) {
            layers.append(Layer(path: star(radius: r * 0.3), fill: Terrain.wild.uiColor, stroke: Terrain.wild.detailColor, lineWidth: 1.5))
        }

        layers.append(Layer(path: geometry.outlinePath(inset: 0.75), stroke: Palette.rim, lineWidth: 1.5))
        return layers
    }

    /// A mountain hex: stony ground with snow-capped peaks. The rim is darker, a wall rather than a lone peak.
    static func mountainLayers(rim: Bool, geometry: HexGeometry) -> [Layer] {
        let r = geometry.radius
        let ground = rim ? Palette.rimStone : Palette.stone
        var layers = [Layer(path: geometry.outlinePath(), fill: ground, stroke: ground, lineWidth: 1)]
        // Back peak, then two in front: (center x, base y, half-width, height) in radius units.
        let peaks: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0.05, -0.1, 0.42, 0.78), (-0.33, -0.35, 0.36, 0.6), (0.38, -0.38, 0.34, 0.52)]
        for (x, base, half, height) in peaks {
            let left = CGPoint(x: (x - half) * r, y: base * r)
            let top = CGPoint(x: x * r, y: (base + height) * r)
            let right = CGPoint(x: (x + half) * r, y: base * r)
            let mountain = CGMutablePath()
            mountain.addLines(between: [left, top, right])
            mountain.closeSubpath()
            layers.append(Layer(path: mountain, fill: rim ? Palette.rimRock : Palette.rock, stroke: Palette.rockEdge, lineWidth: 1))

            // Snow on the top third.
            let snowline: CGFloat = 0.34
            let snow = CGMutablePath()
            snow.addLines(between: [
                CGPoint(x: top.x - half * r * snowline, y: top.y - height * r * snowline),
                top,
                CGPoint(x: top.x + half * r * snowline, y: top.y - height * r * snowline),
            ])
            snow.closeSubpath()
            layers.append(Layer(path: snow, fill: Palette.snow))
        }
        layers.append(Layer(path: geometry.outlinePath(inset: 0.75), stroke: Palette.rim, lineWidth: 1.5))
        return layers
    }

    /// Wedge colors for a wildcard, one terrain per side.
    private static let wildPatchwork: [Terrain] = [.forest, .field, .village, .water, .meadow, .field]

    /// A five-pointed star centered on the tile.
    private static func star(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for point in 0..<10 {
            let distance = point.isMultiple(of: 2) ? radius : radius * 0.45
            let angle = CGFloat(point) * .pi / 5 + .pi / 2
            let corner = CGPoint(x: distance * cos(angle), y: distance * sin(angle))
            point == 0 ? path.move(to: corner) : path.addLine(to: corner)
        }
        path.closeSubpath()
        return path
    }

    private static func details(for terrain: Terrain, direction: Int, geometry: HexGeometry) -> [Layer] {
        let r = geometry.radius
        let out = geometry.outward(direction)
        let across = CGVector(dx: -out.dy, dy: out.dx)
        // Roughly the wedge's centroid.
        let anchor = CGPoint(x: out.dx * r * 0.55, y: out.dy * r * 0.55)

        func offset(_ point: CGPoint, along vector: CGVector, by distance: CGFloat) -> CGPoint {
            CGPoint(x: point.x + vector.dx * distance, y: point.y + vector.dy * distance)
        }

        switch terrain {
        case .forest:
            return [-1, 1].map { side in
                let center = offset(anchor, along: across, by: CGFloat(side) * r * 0.14)
                let size = r * 0.24
                let tree = CGPath(ellipseIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size), transform: nil)
                return Layer(path: tree, fill: terrain.detailColor)
            }

        case .field:
            let rows = CGMutablePath()
            for step in [-1, 0, 1] {
                let middle = offset(anchor, along: out, by: CGFloat(step) * r * 0.1)
                rows.move(to: offset(middle, along: across, by: -r * 0.14))
                rows.addLine(to: offset(middle, along: across, by: r * 0.14))
            }
            return [Layer(path: rows, stroke: terrain.detailColor, lineWidth: r * 0.045, lineCap: .round)]

        case .village:
            let size = r * 0.2
            let wall = CGPath(
                rect: CGRect(x: anchor.x - size / 2, y: anchor.y - size / 2, width: size, height: size * 0.8),
                transform: nil
            )
            let roof = CGMutablePath()
            roof.move(to: CGPoint(x: anchor.x - size * 0.65, y: anchor.y + size * 0.3))
            roof.addLine(to: CGPoint(x: anchor.x + size * 0.65, y: anchor.y + size * 0.3))
            roof.addLine(to: CGPoint(x: anchor.x, y: anchor.y + size * 0.85))
            roof.closeSubpath()
            return [
                Layer(path: wall, fill: Palette.houseWall),
                Layer(path: roof, fill: terrain.detailColor),
            ]

        case .meadow, .water, .wild:
            return []
        }
    }
}
