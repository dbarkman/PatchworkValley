import SpriteKit
import ValleyCore

/// Renders the valley and turns touches into model calls. Holds no game state:
/// `sync` reconciles the nodes with whatever the model says.
final class ValleyScene: SKScene {
    weak var model: GameModel?

    let geometry = HexGeometry(radius: 44)

    private let cameraNode = SKCameraNode()
    private let slotLayer = SKNode()
    private let tileLayer = SKNode()
    private let ghostLayer = SKNode()
    private let badgeLayer = SKNode()
    private let effectLayer = SKNode()

    private var tileSprites: [Hex: SKSpriteNode] = [:]
    private var slotSprites: [Hex: SKSpriteNode] = [:]
    private var badges: [Int: QuestBadge] = [:]
    private var tileTextures: [[Terrain]: SKTexture] = [:]
    private var slotTexture: SKTexture?
    private var flashTexture: SKTexture?
    private var ghost: GhostNode?
    private weak var gestureView: SKView?

    private static let zoomRange: ClosedRange<CGFloat> = 0.7...3

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = Palette.board
        for (depth, layer) in [slotLayer, tileLayer, ghostLayer, badgeLayer, effectLayer].enumerated() {
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

    /// Brings every node in line with the model. Pass the latest placement to animate it.
    func sync(placement: PlacementResult? = nil) {
        guard let view, let model else { return }
        let game = model.game
        syncTiles(game.board, placement: placement, in: view)
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
                // Sit near the tile's top corner so the art stays visible.
                let center = geometry.center(of: quest.anchor)
                badge.position = CGPoint(x: center.x, y: center.y + geometry.radius * 0.62)
                badgeLayer.addChild(badge)
                badges[quest.id] = badge
                badge.appear()
            }
        }
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
        if placement.points > 0 {
            floatText("+\(placement.points)", at: CGPoint(x: center.x, y: center.y + geometry.radius * 0.4))
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

    private func floatText(_ text: String, at point: CGPoint) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = geometry.radius * 0.5
        label.fontColor = .white
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
        let art = SKNode()
        // The view ignores sibling order, so each layer gets an explicit depth.
        for (depth, layer) in TileDrawing.layers(for: edges, geometry: geometry).enumerated() {
            let shape = SKShapeNode(path: layer.path)
            shape.zPosition = CGFloat(depth)
            shape.fillColor = layer.fill ?? .clear
            shape.strokeColor = layer.stroke ?? .clear
            shape.lineWidth = layer.lineWidth
            shape.lineCap = layer.lineCap
            art.addChild(shape)
        }
        let texture = view.texture(from: art, crop: geometry.bounds) ?? SKTexture()
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

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let scale = cameraNode.xScale / recognizer.scale
        cameraNode.setScale(min(max(scale, Self.zoomRange.lowerBound), Self.zoomRange.upperBound))
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
