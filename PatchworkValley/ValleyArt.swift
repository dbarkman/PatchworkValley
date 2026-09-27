import UIKit
import ValleyCore

/// Draws a finished valley as a picture, with the same tile art as the board, so a
/// saved valley looks just like it did in play. Plain Core Graphics, so it works off screen
/// and at any size, off the main thread.
nonisolated enum ValleyArt {
    private static let geometry = HexGeometry(radius: 44)

    /// The valley on the board's color, with a margin, `longestSide` pixels on its longer edge.
    static func image(of picture: ValleyPicture, longestSide: CGFloat) -> UIImage {
        let centers = picture.hexes.map { geometry.center(of: $0) }
        let margin = geometry.radius
        let minX = (centers.map(\.x).min() ?? 0) - geometry.tileSize.width / 2 - margin
        let maxX = (centers.map(\.x).max() ?? 0) + geometry.tileSize.width / 2 + margin
        let minY = (centers.map(\.y).min() ?? 0) - geometry.tileSize.height / 2 - margin
        let maxY = (centers.map(\.y).max() ?? 0) + geometry.tileSize.height / 2 + margin
        let scale = longestSide / max(maxX - minX, maxY - minY)
        let size = CGSize(width: ((maxX - minX) * scale).rounded(), height: ((maxY - minY) * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            Palette.board.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            // The tile art is drawn in y-up space, like SpriteKit's.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -minX, y: -minY)

            for hex in picture.rim {
                draw(TileDrawing.mountainLayers(rim: true, geometry: geometry), at: hex, in: cg)
            }
            for hex in picture.peaks {
                draw(TileDrawing.mountainLayers(rim: false, geometry: geometry), at: hex, in: cg)
            }
            for hex in picture.lakes {
                draw(TileDrawing.lakeLayers(geometry: geometry), at: hex, in: cg)
            }
            for tile in picture.tiles {
                draw(TileDrawing.layers(for: tile.edges, geometry: geometry), at: tile.hex, in: cg)
            }
        }
    }

    private static func draw(_ layers: [TileDrawing.Layer], at hex: Hex, in cg: CGContext) {
        let center = geometry.center(of: hex)
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        for layer in layers {
            if let fill = layer.fill {
                cg.addPath(layer.path)
                cg.setFillColor(fill.cgColor)
                cg.fillPath()
            }
            if let stroke = layer.stroke, layer.lineWidth > 0 {
                cg.addPath(layer.path)
                cg.setStrokeColor(stroke.cgColor)
                cg.setLineWidth(layer.lineWidth)
                cg.setLineCap(layer.lineCap)
                cg.strokePath()
            }
        }
        cg.restoreGState()
    }
}
