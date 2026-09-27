import CoreGraphics
import ValleyCore

/// Pixel math for pointy-top hexes in y-up space (SpriteKit's, and Canvas after a y-flip).
///
/// Corner `k` sits at `30° + 60° × k`, so edge `i` runs from corner `i - 1` to corner `i`
/// and its midpoint lies in direction `i`, matching `Hex.neighbor(i)`.
struct HexGeometry {
    /// Center to corner.
    let radius: CGFloat

    var tileSize: CGSize { CGSize(width: radius * 3.squareRoot(), height: radius * 2) }

    /// The tile's bounding box, centered on the origin.
    var bounds: CGRect {
        CGRect(x: -tileSize.width / 2, y: -tileSize.height / 2, width: tileSize.width, height: tileSize.height)
    }

    func center(of hex: Hex) -> CGPoint {
        CGPoint(
            x: radius * 3.squareRoot() * (CGFloat(hex.q) + CGFloat(hex.r) / 2),
            y: -radius * 1.5 * CGFloat(hex.r)
        )
    }

    func hex(at point: CGPoint) -> Hex {
        let r = -point.y / (1.5 * radius)
        let q = point.x / (3.squareRoot() * radius) - r / 2
        return Self.round(q: q, r: r)
    }

    func corner(_ k: Int, radius cornerRadius: CGFloat? = nil) -> CGPoint {
        point(atDegrees: 60 * CGFloat(k) + 30, distance: cornerRadius ?? radius)
    }

    func edgeMidpoint(_ direction: Int) -> CGPoint {
        point(atDegrees: 60 * CGFloat(direction), distance: radius * 3.squareRoot() / 2)
    }

    /// The triangle between the center and edge `direction`.
    func wedgePath(_ direction: Int) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: corner(direction - 1))
        path.addLine(to: corner(direction))
        path.closeSubpath()
        return path
    }

    func outlinePath(inset: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: (0..<6).map { corner($0, radius: radius - inset) })
        path.closeSubpath()
        return path
    }

    /// Unit vector pointing out through edge `direction`.
    func outward(_ direction: Int) -> CGVector {
        let radians = 60 * CGFloat(direction) * .pi / 180
        return CGVector(dx: cos(radians), dy: sin(radians))
    }

    private func point(atDegrees degrees: CGFloat, distance: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: distance * cos(radians), y: distance * sin(radians))
    }

    /// Cube rounding: round all three axes, then fix the one that drifted most.
    private static func round(q: CGFloat, r: CGFloat) -> Hex {
        let s = -q - r
        var roundedQ = q.rounded()
        var roundedR = r.rounded()
        let roundedS = s.rounded()
        let dq = abs(roundedQ - q)
        let dr = abs(roundedR - r)
        let ds = abs(roundedS - s)
        if dq > dr && dq > ds {
            roundedQ = -roundedR - roundedS
        } else if dr > ds {
            roundedR = -roundedQ - roundedS
        }
        return Hex(Int(roundedQ), Int(roundedR))
    }
}
