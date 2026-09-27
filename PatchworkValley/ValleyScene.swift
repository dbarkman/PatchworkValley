import SpriteKit
import ValleyCore

/// Renders the valley and turns touches into model calls. Holds no game state:
/// `sync` reconciles the nodes with whatever the model says.
final class ValleyScene: SKScene {
    weak var model: GameModel?

    let geometry = HexGeometry(radius: 44)

    private let cameraNode = SKCameraNode()
    private let slotLayer = SKNode()
    private let mountainLayer = SKNode()
    private let tileLayer = SKNode()
    private let ghostLayer = SKNode()
    private let badgeLayer = SKNode()
    private let effectLayer = SKNode()

    private var tileSprites: [Hex: SKSpriteNode] = [:]
    private var mountainSprites: [Hex: SKSpriteNode] = [:]
    private var lakeSprites: [Hex: SKSpriteNode] = [:]
    private var peakTexture: SKTexture?
    private var rimTexture: SKTexture?
    private var lakeTexture: SKTexture?
    private var slotSprites: [Hex: SKSpriteNode] = [:]
    private var badges: [Int: QuestBadge] = [:]
    private var tileTextures: [[Terrain]: SKTexture] = [:]
    private var slotTexture: SKTexture?
    private var flashTexture: SKTexture?
    private var ghost: GhostNode?
    private weak var gestureView: SKView?

    private static let zoomRange: ClosedRange<CGFloat> = 0.7...3

    /// Where the HUD ends at the top and the tray begins at the bottom, in view points,
    /// so the camera can frame the valley in the space between them.
    var hudTop: CGFloat = 0
    var hudBottom: CGFloat = 0

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = Palette.board
        for (depth, layer) in [slotLayer, mountainLayer, tileLayer, ghostLayer, badgeLayer, effectLayer].enumerated() {
            // Layers sit 10 apart so the small depths nodes use inside a layer never reach the next one.
            layer.zPosition = CGFloat(depth) * 10
            addChild(layer)
        }
        addChild(cameraNode)
        camera = cameraNode
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMove(to view: SKView) {
        if gestureView !== view {
            gestureView = view
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
            view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))
            view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch)))
        }
        sync()
    }

    // MARK: - Reconciling with the model

    /// Brings every node in line with the model. Pass the latest placement, or a
    /// mountain that was just blasted, to animate it.
    func sync(placement: PlacementResult? = nil, blasted: Hex? = nil) {
        guard let view, let model else { return }
        let game = model.game
        syncTiles(game.board, placement: placement, in: view)
        syncMountains(game.board, blasted: blasted, aiming: model.isAimingDynamite, in: view)
        syncLakes(game.board, in: view)
        syncSlots(game, in: view)
        syncBadges(game, placement: placement)
        syncGhost(model, in: view)
        if let placement {
            playEffects(for: placement, board: game.board, in: view)
        }
    }

    func recenter() {
        cameraNode.run(.group([
            .move(to: .zero, duration: 0.35),
            .scale(to: 1, duration: 0.35),
        ]))
    }

    /// Zooms and pans so the whole valley (tiles, open spots, and the mountains and
    /// lakes found so far) fits between the HUD and the tray.
    func fitValley() {
        guard let view, let board = model?.game.board else { return }
        let hexes = Set(board.tiles.keys).union(board.openSlots).union(board.revealedMountains).union(board.revealedLakes)
        let centers = hexes.map { geometry.center(of: $0) }
        guard let minX = centers.map(\.x).min(), let maxX = centers.map(\.x).max(),
              let minY = centers.map(\.y).min(), let maxY = centers.map(\.y).max() else { return }
        let width = maxX - minX + geometry.tileSize.width
        let height = maxY - minY + geometry.tileSize.height

        let top = hudTop
        let bottom = hudBottom > top ? hudBottom : view.bounds.height
        let freeWidth = max(view.bounds.width - 24, 100)
        let freeHeight = max(bottom - top - 16, 100)
        let scale = min(max(width / freeWidth, height / freeHeight, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)

        // Put the valley's middle in the middle of the free band, not the middle of the screen.
        let freeMiddle = (top + bottom) / 2
        let target = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2 + (freeMiddle - view.bounds.midY) * scale)
        let move = SKAction.group([.move(to: target, duration: 0.35), .scale(to: scale, duration: 0.35)])
        move.timingMode = .easeInEaseOut
        cameraNode.run(move)
    }

    private func syncTiles(_ board: Board, placement: PlacementResult?, in view: SKView) {
        // Drop sprites whose hex emptied or now holds a different tile (a mode switch or new level
        // swaps in a whole new board, and the starter always sits at the origin). Textures are
        // cached per edge list, so a different texture means a different tile.
        for (hex, sprite) in tileSprites {
            if let tile = board[hex], sprite.texture === texture(for: tile.edges, in: view) { continue }
            tileSprites[hex] = nil
            sprite.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
        }
        for (hex, tile) in board.tiles where tileSprites[hex] == nil {
            let sprite = SKSpriteNode(texture: texture(for: tile.edges, in: view), size: geometry.tileSize)
            sprite.position = geometry.center(of: hex)
            tileLayer.addChild(sprite)
            tileSprites[hex] = sprite

            sprite.alpha = 0
            if placement?.hex == hex {
                sprite.setScale(0.7)
                sprite.run(.group([
                    .fadeIn(withDuration: 0.12),
                    .sequence([.scale(to: 1.08, duration: 0.14), .scale(to: 1, duration: 0.1)]),
                ]))
            } else {
                sprite.run(.fadeIn(withDuration: 0.25))
            }
        }
    }

    // MARK: - Mountains

    private func syncMountains(_ board: Board, blasted: Hex?, aiming: Bool, in view: SKView) {
        for (hex, sprite) in mountainSprites where !board.revealedMountains.contains(hex) {
            mountainSprites[hex] = nil
            if hex == blasted {
                explode(sprite)
            } else {
                sprite.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            }
        }
        // Mountains seen for the first time rise out of the fog, a few at a time when a Lantern lights them all.
        let fresh = board.revealedMountains.filter { mountainSprites[$0] == nil }
        for (index, hex) in fresh.sorted(by: { ($0.r, $0.q) < ($1.r, $1.q) }).enumerated() {
            let isRim = board.floor?.contains(hex) == false
            let sprite = SKSpriteNode(texture: mountainTexture(rim: isRim, in: view), size: geometry.tileSize)
            sprite.position = geometry.center(of: hex)
            mountainLayer.addChild(sprite)
            mountainSprites[hex] = sprite
            rise(sprite, delay: fresh.count > 3 ? Double(index) * 0.03 : 0)
        }
        // While aiming Dynamite, the mountains it can reach pulse.
        let targets = aiming ? board.clearableMountains : []
        for (hex, sprite) in mountainSprites {
            if targets.contains(hex) {
                guard sprite.action(forKey: "aim") == nil else { continue }
                sprite.run(.repeatForever(.sequence([
                    .group([.scale(to: 1.08, duration: 0.35), .colorize(with: .orange, colorBlendFactor: 0.45, duration: 0.35)]),
                    .group([.scale(to: 1, duration: 0.35), .colorize(withColorBlendFactor: 0, duration: 0.35)]),
                ])), withKey: "aim")
            } else if sprite.action(forKey: "aim") != nil {
                sprite.removeAction(forKey: "aim")
                sprite.run(.group([.scale(to: 1, duration: 0.15), .colorize(withColorBlendFactor: 0, duration: 0.15)]))
            }
        }
    }

    private func mountainTexture(rim: Bool, in view: SKView) -> SKTexture {
        if let cached = rim ? rimTexture : peakTexture { return cached }
        let texture = render(TileDrawing.mountainLayers(rim: rim, geometry: geometry), in: view)
        if rim { rimTexture = texture } else { peakTexture = texture }
        return texture
    }

    // MARK: - Lakes

    private func syncLakes(_ board: Board, in view: SKView) {
        for (hex, sprite) in lakeSprites where !board.revealedLakes.contains(hex) {
            lakeSprites[hex] = nil
            sprite.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
        }
        for hex in board.revealedLakes where lakeSprites[hex] == nil {
            if lakeTexture == nil { lakeTexture = render(TileDrawing.lakeLayers(geometry: geometry), in: view) }
            let sprite = SKSpriteNode(texture: lakeTexture, size: geometry.tileSize)
            sprite.position = geometry.center(of: hex)
            mountainLayer.addChild(sprite)
            lakeSprites[hex] = sprite
            shimmer(sprite)
        }
    }

    /// A lake comes out of the fog with a ripple spreading across it.
    private func shimmer(_ sprite: SKSpriteNode) {
        sprite.alpha = 0
        sprite.setScale(0.85)
        sprite.run(.group([.fadeIn(withDuration: 0.25), .scale(to: 1, duration: 0.3)]))
        let ripple = SKShapeNode(circleOfRadius: geometry.radius * 0.3)
        ripple.strokeColor = Palette.snow.withAlphaComponent(0.8)
        ripple.lineWidth = 2
        ripple.fillColor = .clear
        ripple.position = sprite.position
        effectLayer.addChild(ripple)
        ripple.run(.sequence([
            .group([.scale(to: 2.2, duration: 0.7), .fadeOut(withDuration: 0.7)]),
            .removeFromParent(),
        ]))
    }

    /// Draws a list of layers into a texture, each layer at its own depth.
    private func render(_ layers: [TileDrawing.Layer], in view: SKView) -> SKTexture {
        let art = SKNode()
        for (depth, layer) in layers.enumerated() {
            let shape = SKShapeNode(path: layer.path)
            shape.zPosition = CGFloat(depth)
            shape.fillColor = layer.fill ?? .clear
            shape.strokeColor = layer.stroke ?? .clear
            shape.lineWidth = layer.lineWidth
            shape.lineCap = layer.lineCap
            art.addChild(shape)
        }
        return view.texture(from: art, crop: geometry.bounds) ?? SKTexture()
    }

    /// A mountain pushes up out of the fog with a puff of dust.
    private func rise(_ sprite: SKSpriteNode, delay: TimeInterval) {
        let home = sprite.position
        sprite.alpha = 0
        sprite.setScale(0.5)
        sprite.position = CGPoint(x: home.x, y: home.y - geometry.radius * 0.3)
        let lift = SKAction.group([
            .fadeIn(withDuration: 0.18),
            .move(to: home, duration: 0.3),
            .sequence([.scale(to: 1.06, duration: 0.22), .scale(to: 1, duration: 0.1)]),
        ])
        lift.timingMode = .easeOut
        // The puff rides on the sprite's own actions, so it's cancelled if the mountain goes away first.
        sprite.run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in self?.puff(at: home, color: Palette.dust, count: 6) },
            lift,
        ]))
    }

    /// Dynamite: the mountain bursts apart in a flash and flying rock.
    private func explode(_ sprite: SKSpriteNode) {
        let center = sprite.position
        sprite.run(.sequence([
            .group([.scale(to: 1.3, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent(),
        ]))
        let flash = SKShapeNode(circleOfRadius: geometry.radius * 0.8)
        flash.fillColor = Palette.blast
        flash.strokeColor = .clear
        flash.position = center
        flash.setScale(0.2)
        effectLayer.addChild(flash)
        flash.run(.sequence([
            .group([.scale(to: 1.4, duration: 0.25), .fadeOut(withDuration: 0.3)]),
            .removeFromParent(),
        ]))
        puff(at: center, color: Palette.rock, count: 10, reach: 1.2)
    }

    /// Small particles thrown outward from `point`, fading as they go.
    private func puff(at point: CGPoint, color: UIColor, count: Int, reach: CGFloat = 0.6) {
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.3...0.3)
            let size = geometry.radius * CGFloat.random(in: 0.07...0.13)
            let bit = SKShapeNode(circleOfRadius: size)
            bit.fillColor = color
            bit.strokeColor = .clear
            bit.position = CGPoint(x: point.x, y: point.y - geometry.radius * 0.35)
            effectLayer.addChild(bit)
            let distance = geometry.radius * reach * CGFloat.random(in: 0.6...1)
            let drift = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance * 0.5 + geometry.radius * 0.15, duration: 0.5)
            drift.timingMode = .easeOut
            bit.run(.sequence([.group([drift, .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }
    }

    private func syncSlots(_ game: ValleyGame, in view: SKView) {
        let open = game.isOver ? [] : game.board.openSlots
        for (hex, sprite) in slotSprites where !open.contains(hex) {
            slotSprites[hex] = nil
            sprite.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        }
        for hex in open {
            let sprite = slotSprites[hex] ?? makeSlot(at: hex, in: view)
            // Brighter where the current tile fits in some rotation.
            let fits = game.current.map { game.board.bestRotation(for: $0, at: hex) != nil } ?? false
            sprite.removeAction(forKey: "fade")
            sprite.run(.fadeAlpha(to: fits ? 0.5 : 0.12, duration: 0.2), withKey: "fade")
        }
    }

    private func makeSlot(at hex: Hex, in view: SKView) -> SKSpriteNode {
        if slotTexture == nil {
            let outline = SKShapeNode(path: geometry.outlinePath(inset: 3))
            outline.strokeColor = Palette.slot
            outline.fillColor = Palette.slot.withAlphaComponent(0.12)
            outline.lineWidth = 2
            slotTexture = view.texture(from: outline, crop: geometry.bounds)
        }
        let sprite = SKSpriteNode(texture: slotTexture, size: geometry.tileSize)
        sprite.position = geometry.center(of: hex)
        sprite.alpha = 0
        slotLayer.addChild(sprite)
        slotSprites[hex] = sprite
        return sprite
    }

    private func syncBadges(_ game: ValleyGame, placement: PlacementResult?) {
        let active = Dictionary(uniqueKeysWithValues: game.activeQuests.map { ($0.id, $0) })
        for (id, badge) in badges where active[id] == nil {
            badges[id] = nil
            let completed = placement?.completedQuests.contains { $0.id == id } ?? false
            badge.dismiss(completed: completed)
        }
        for quest in active.values {
            if let badge = badges[quest.id] {
                badge.update(remaining: quest.remaining)
            } else {
                let badge = QuestBadge(quest: quest, radius: geometry.radius * 0.3)
                badge.position = badgePosition(for: quest, on: game.board)
                badgeLayer.addChild(badge)
                badges[quest.id] = badge
                badge.appear()
            }
        }
    }

    /// Where a quest's badge sits: on the part of its tile showing the quest's terrain.
    private func badgePosition(for quest: Quest, on board: Board) -> CGPoint {
        let center = geometry.center(of: quest.anchor)
        let directions = board[quest.anchor].map { tile in (0..<6).filter { tile.edge($0) == quest.terrain } } ?? []
        var pull = directions.reduce(CGVector.zero) { sum, direction in
            let out = geometry.outward(direction)
            return CGVector(dx: sum.dx + out.dx, dy: sum.dy + out.dy)
        }
        // Opposite wedges (a straight river, say) cancel out; lean toward the first one instead.
        if hypot(pull.dx, pull.dy) < 0.3, let first = directions.first {
            pull = geometry.outward(first)
        }
        let length = max(hypot(pull.dx, pull.dy), 0.001)
        let reach = directions.isEmpty ? 0 : geometry.radius * 0.5
        return CGPoint(x: center.x + pull.dx / length * reach, y: center.y + pull.dy / length * reach)
    }

    private func syncGhost(_ model: GameModel, in view: SKView) {
        guard let slot = model.selectedSlot,
              let tile = model.game.current,
              let evaluation = model.ghostEvaluation else {
            ghost?.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
            ghost = nil
            return
        }

        // Draw the tile as it was before the player's turns, then spin the node, so rotation animates.
        let unturned = tile.rotatedClockwise(-model.rotationTurns)
        let angle = -CGFloat(model.rotationTurns) * .pi / 3
        let position = geometry.center(of: slot)

        if let ghost {
            ghost.show(texture: texture(for: unturned.edges, in: view), evaluation: evaluation)
            ghost.run(.move(to: position, duration: 0.12))
            ghost.spin(to: angle)
        } else {
            let ghost = GhostNode(geometry: geometry)
            ghost.position = position
            ghost.show(texture: texture(for: unturned.edges, in: view), evaluation: evaluation)
            ghost.spin(to: angle, animated: false)
            ghost.alpha = 0
            ghost.run(.fadeIn(withDuration: 0.12))
            ghostLayer.addChild(ghost)
            self.ghost = ghost
        }
    }

    private func playEffects(for placement: PlacementResult, board: Board, in view: SKView) {
        let center = geometry.center(of: placement.hex)
        let above = CGPoint(x: center.x, y: center.y + geometry.radius * 0.4)
        if model?.mode == .coins {
            if placement.coins > 0 { floatText("+\(placement.coins)", at: above, color: Palette.coin) }
        } else if placement.points > 0 {
            floatText("+\(placement.points)", at: above, color: .white)
        }
        for quest in placement.completedQuests {
            flash(board.region(of: quest.terrain, from: quest.anchor), from: quest.anchor, in: view)
        }
        for goal in placement.metGoals {
            flash(board.largestRegion(of: goal.terrain), from: placement.hex, in: view)
        }
        if model?.game.outcome == .won {
            flash(Set(board.tiles.keys), from: placement.hex, in: view, delay: 0.35)
        }
    }

    /// Ripples a white flash across `region`, spreading out from `origin`.
    private func flash(_ region: Set<Hex>, from origin: Hex, in view: SKView, delay: TimeInterval = 0) {
        let anchor = geometry.center(of: origin)
        for hex in region {
            let spot = geometry.center(of: hex)
            let distance = hypot(spot.x - anchor.x, spot.y - anchor.y)
            flash(at: spot, delay: delay + distance / (geometry.radius * 12), in: view)
        }
    }

    private func floatText(_ text: String, at point: CGPoint, color: UIColor) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = geometry.radius * 0.5
        label.fontColor = color
        label.position = point
        label.setScale(0.6)
        effectLayer.addChild(label)
        label.run(.sequence([
            .group([
                .scale(to: 1, duration: 0.15),
                .moveBy(x: 0, y: geometry.radius * 0.9, duration: 0.8),
                .sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.35)]),
            ]),
            .removeFromParent(),
        ]))
    }

    private func flash(at point: CGPoint, delay: TimeInterval, in view: SKView) {
        if flashTexture == nil {
            let shape = SKShapeNode(path: geometry.outlinePath())
            shape.fillColor = .white
            shape.strokeColor = .clear
            flashTexture = view.texture(from: shape, crop: geometry.bounds)
        }
        let sprite = SKSpriteNode(texture: flashTexture, size: geometry.tileSize)
        sprite.position = point
        sprite.alpha = 0
        effectLayer.addChild(sprite)
        sprite.run(.sequence([
            .wait(forDuration: delay),
            .fadeAlpha(to: 0.55, duration: 0.12),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
        ]))
    }

    private func texture(for edges: [Terrain], in view: SKView) -> SKTexture {
        if let cached = tileTextures[edges] { return cached }
        let texture = render(TileDrawing.layers(for: edges, geometry: geometry), in: view)
        tileTextures[edges] = texture
        return texture
    }

    // MARK: - Gestures

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let point = convertPoint(fromView: recognizer.location(in: view))
        model?.tap(geometry.hex(at: point))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let translation = recognizer.translation(in: view)
        cameraNode.position.x -= translation.x * cameraNode.xScale
        cameraNode.position.y += translation.y * cameraNode.yScale
        recognizer.setTranslation(.zero, in: view)
    }

    /// Zooms around the point between the fingers, so what's under them stays put.
    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let fingers = recognizer.location(in: view)
        let before = convertPoint(fromView: fingers)
        let scale = cameraNode.xScale / recognizer.scale
        cameraNode.setScale(min(max(scale, Self.zoomRange.lowerBound), Self.zoomRange.upperBound))
        let after = convertPoint(fromView: fingers)
        cameraNode.position.x += before.x - after.x
        cameraNode.position.y += before.y - after.y
        recognizer.scale = 1
    }
}

/// The translucent preview of the current tile on the selected slot. Stitches
/// sew each matching seam; a red outline means the tile can't go here.
private final class GhostNode: SKNode {
    private let geometry: HexGeometry
    private let sprite: SKSpriteNode
    private let outline: SKShapeNode
    private let stitches = SKNode()

    init(geometry: HexGeometry) {
        self.geometry = geometry
        sprite = SKSpriteNode(color: .clear, size: geometry.tileSize)
        sprite.alpha = 0.85
        outline = SKShapeNode(path: geometry.outlinePath(inset: 1.5))
        outline.lineWidth = 3
        outline.fillColor = .clear
        super.init()
        // The view ignores sibling order, so depth is explicit: art, then outline, then stitches on top.
        sprite.zPosition = 0
        outline.zPosition = 1
        stitches.zPosition = 2
        addChild(sprite)
        addChild(outline)
        addChild(stitches)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(texture: SKTexture, evaluation: PlacementEvaluation) {
        sprite.texture = texture
        outline.strokeColor = evaluation.isLegal ? Palette.legal : Palette.illegal
        sewStitches(along: evaluation.isLegal ? evaluation.matchingEdges : [])
    }

    /// Stitches crossing each matching seam, as if sewing the two patches together,
    /// sewn in one at a time once the spin settles.
    private func sewStitches(along directions: [Int]) {
        stitches.removeAllChildren()
        let perSeam = 4
        let length = geometry.radius * 0.19
        for (seamIndex, direction) in directions.enumerated() {
            let start = geometry.corner(direction - 1)
            let end = geometry.corner(direction)
            // Perpendicular to the seam, so each stitch spans both tiles.
            let angle = atan2(end.y - start.y, end.x - start.x) + .pi / 2
            for index in 0..<perSeam {
                let t = CGFloat(index + 1) / CGFloat(perSeam + 1)
                let stitch = makeStitch(length: length)
                stitch.position = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                stitch.zRotation = angle
                stitch.alpha = 0
                stitch.setScale(0.2)
                let delay = 0.14 + Double(seamIndex) * 0.06 + Double(index) * 0.035
                stitch.run(.sequence([
                    .wait(forDuration: delay),
                    .group([.fadeIn(withDuration: 0.08), .scale(to: 1, duration: 0.1)]),
                ]))
                stitches.addChild(stitch)
            }
        }
    }

    /// One stitch: a short thread over a soft shadow so it reads on every terrain color.
    private func makeStitch(length: CGFloat) -> SKNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -length / 2, y: 0))
        path.addLine(to: CGPoint(x: length / 2, y: 0))

        let shadow = SKShapeNode(path: path)
        shadow.strokeColor = Palette.stitchShadow
        shadow.lineWidth = 4
        shadow.lineCap = .round

        let thread = SKShapeNode(path: path)
        thread.strokeColor = Palette.stitch
        thread.lineWidth = 2.5
        thread.lineCap = .round
        thread.zPosition = 1

        let stitch = SKNode()
        stitch.addChild(shadow)
        stitch.addChild(thread)
        return stitch
    }

    /// Spins only the tile art; the outline and stitches stay upright.
    func spin(to angle: CGFloat, animated: Bool = true) {
        sprite.removeAction(forKey: "spin")
        if animated {
            let action = SKAction.rotate(toAngle: angle, duration: 0.16, shortestUnitArc: false)
            action.timingMode = .easeOut
            sprite.run(action, withKey: "spin")
        } else {
            sprite.zRotation = angle
        }
    }
}

/// A quest marker on the board: the terrain's color with the tiles still needed.
private final class QuestBadge: SKNode {
    private let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")

    init(quest: Quest, radius: CGFloat) {
        super.init()
        let disc = SKShapeNode(circleOfRadius: radius)
        disc.fillColor = quest.terrain == .meadow ? .darkGray : quest.terrain.detailColor
        disc.strokeColor = .white
        disc.lineWidth = 2.5
        addChild(disc)

        label.fontSize = radius * 1.05
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.text = "\(quest.remaining)"
        label.zPosition = 1
        addChild(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func appear() {
        setScale(0.2)
        alpha = 0
        run(.group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.2)]))
    }

    func update(remaining: Int) {
        let text = "\(remaining)"
        guard label.text != text else { return }
        label.text = text
        run(.sequence([.scale(to: 1.25, duration: 0.1), .scale(to: 1, duration: 0.12)]))
    }

    func dismiss(completed: Bool) {
        let exit: SKAction = completed
            ? .group([.scale(to: 1.8, duration: 0.3), .fadeOut(withDuration: 0.3)])
            : .group([.scale(to: 0.4, duration: 0.25), .fadeOut(withDuration: 0.25)])
        run(.sequence([exit, .removeFromParent()]))
    }
}
