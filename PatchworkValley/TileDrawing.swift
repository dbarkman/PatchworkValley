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
            // Round the bend where the two strips meet in the middle.
            let joint = CGPath(ellipseIn: CGRect(x: -width / 2, y: -width / 2, width: width, height: width), transform: nil)
            layers.append(Layer(path: joint, fill: Terrain.water.uiColor))
        }

        if edges.contains(.wild) {
            layers.append(Layer(path: star(radius: r * 0.3), fill: Terrain.wild.uiColor, stroke: Terrain.wild.detailColor, lineWidth: 1.5))
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
