import SpriteKit
import SwiftUI
import ValleyCore

struct GameView: View {
    @State private var model = GameModel()

    var body: some View {
        ZStack {
            SpriteView(scene: model.scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            // Cards sit under the HUD so the menu stays reachable from any card.
            if let overlay = model.overlay {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                OverlayCard(overlay: overlay, model: model)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            VStack(spacing: 12) {
                TopBar(model: model)
                if let toast = model.toast {
                    ToastView(toast: toast)
                        .id(toast.id)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                if model.overlay == nil {
                    TileTray(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .animation(.snappy, value: model.overlay)
        .animation(.snappy, value: model.toast)
        .animation(.snappy, value: model.mode)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    let model: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GameMenu(model: model)
                Spacer(minLength: 0)
                Stat(symbol: "star.fill", value: model.game.score, tint: .yellow)
                TilesLeft(model: model)
            }
            objectives
        }
        .animation(.snappy, value: model.game.goals)
        .animation(.snappy, value: model.game.activeQuests)
    }

    @ViewBuilder private var objectives: some View {
        if model.mode == .levels {
            if !model.hasFinishedAllLevels { goals }
        } else if !model.game.activeQuests.isEmpty {
            HStack(spacing: 8) {
                ForEach(model.game.activeQuests) { quest in
                    QuestChip(quest: quest)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private var goals: some View {
        HStack(spacing: 8) {
            ForEach(model.game.goals) { goal in
                GoalChip(goal: goal)
            }
        }
    }
}

/// The mode switch and restart, labeled with where the player is.
private struct GameMenu: View {
    let model: GameModel
    @State private var isConfirmingRestart = false

    var body: some View {
        Menu {
            Picker("Mode", selection: Binding(get: { model.mode }, set: { model.switchMode(to: $0) })) {
                ForEach(GameMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            Button(restartTitle, systemImage: "arrow.counterclockwise") {
                isConfirmingRestart = true
            }
            #if DEBUG
            Section("Debug") {
                Button("Next Level", systemImage: "forward.end") { model.debugJump(to: model.level + 1) }
                Button("Previous Level", systemImage: "backward.end") { model.debugJump(to: model.level - 1) }
            }
            #endif
        } label: {
            Label(menuTitle, systemImage: "line.3.horizontal")
                .font(.headline)
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: Double(model.level)))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
        .animation(.snappy, value: model.level)
        .confirmationDialog(restartTitle, isPresented: $isConfirmingRestart, titleVisibility: .visible) {
            Button(restartTitle, role: .destructive) { model.restart() }
        } message: {
            Text("This valley will be lost.")
        }
    }

    private var menuTitle: String {
        switch model.mode {
        case .levels: model.hasFinishedAllLevels ? "Levels" : "Level \(model.level)"
        case .zen: "Zen"
        }
    }

    private var restartTitle: String {
        switch model.mode {
        case .levels: model.hasFinishedAllLevels ? "Start Over" : "Restart Level"
        case .zen: "New Valley"
        }
    }
}

private struct Stat: View {
    let symbol: String
    let value: Int
    let tint: Color

    var body: some View {
        Label {
            Text(value, format: .number)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .animation(.snappy, value: value)
    }
}

/// Tiles remaining, with a brief "+N" whenever a placement earns tiles.
private struct TilesLeft: View {
    let model: GameModel

    var body: some View {
        let tiles = model.game.tilesLeft
        Label {
            HStack(spacing: 4) {
                Text(tiles, format: .number)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(tiles)))
                Text("left")
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "hexagon.fill").foregroundStyle(tiles <= 3 ? .orange : .mint)
        }
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(alignment: .bottom) {
            if let gain = model.tileGain {
                Text("+\(gain.amount)")
                    .font(.headline.bold())
                    .foregroundStyle(.mint)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .alignmentGuide(.bottom) { $0[.top] - 4 }
                    .id(gain.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: tiles)
        .animation(.snappy, value: model.tileGain)
        .accessibilityLabel("\(tiles) tiles left")
    }
}

private struct GoalChip: View {
    let goal: Goal

    var body: some View {
        Label {
            Text("\(min(goal.progress, goal.target))/\(goal.target)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(goal.progress)))
        } icon: {
            Image(systemName: goal.isMet ? "checkmark.circle.fill" : goal.terrain.symbolName)
                .foregroundStyle(goal.isMet ? .green : goal.terrain.color)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .animation(.snappy, value: goal.progress)
        .accessibilityLabel("\(goal.terrain.displayName) goal, \(min(goal.progress, goal.target)) of \(goal.target)")
    }
}

private struct QuestChip: View {
    let quest: Quest

    var body: some View {
        Label {
            Text("\(quest.progress)/\(quest.target)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(quest.progress)))
        } icon: {
            Image(systemName: quest.terrain.symbolName).foregroundStyle(quest.terrain.color)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .animation(.snappy, value: quest.progress)
        .accessibilityLabel("\(quest.terrain.displayName) quest, \(quest.progress) of \(quest.target)")
    }
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        Label(toast.message, systemImage: toast.symbolName)
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - Tile tray

private struct TileTray: View {
    let model: GameModel
    @ScaledMetric(relativeTo: .largeTitle) private var currentSize: CGFloat = 84
    @ScaledMetric(relativeTo: .title) private var nextSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 16) {
            if let tile = model.game.current {
                // Draw the tile as it was before the player's turns and rotate the view, so each turn animates.
                TilePreview(tile: tile.rotatedClockwise(-model.rotationTurns))
                    .rotationEffect(.degrees(60 * Double(model.rotationTurns)))
                    .animation(.snappy, value: model.rotationTurns)
                    .overlay(alignment: .topTrailing) {
                        if let quest = tile.quest { QuestTag(quest: quest) }
                    }
                    .frame(width: currentSize, height: currentSize)
                    .id(tile.id)
                    .transition(.scale.combined(with: .opacity))
                    .onTapGesture { model.rotate() }
                    .accessibilityLabel("Current tile. Tap to rotate.")
            }

            VStack(spacing: 4) {
                Text("Next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let next = model.game.next {
                    TilePreview(tile: next)
                        .frame(width: nextSize, height: nextSize)
                        .id(next.id)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Color.clear.frame(width: nextSize, height: nextSize)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                status
                    .font(.subheadline)
                    .multilineTextAlignment(.trailing)
                HStack(spacing: 8) {
                    Button("Rotate", systemImage: "arrow.clockwise") { model.rotate() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                    if model.game.isStuck {
                        Button("Discard") { model.discard() }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    } else {
                        Button("Place") { model.place() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canPlace)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.snappy, value: model.game.current?.id)
        .animation(.snappy, value: model.selectedSlot)
    }

    @ViewBuilder private var status: some View {
        if model.game.isStuck {
            Text("This tile fits nowhere")
                .foregroundStyle(.orange)
        } else if let points = model.projectedPoints {
            Text("+\(points)")
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(points)))
        } else if model.selectedSlot != nil {
            Text("Rivers must connect")
                .foregroundStyle(.red)
        } else {
            Text("Tap a glowing spot")
                .foregroundStyle(.secondary)
        }
    }
}

/// A small marker on a tray tile that carries a quest.
private struct QuestTag: View {
    let quest: QuestSpec

    var body: some View {
        Label("\(quest.target)", systemImage: quest.terrain.symbolName)
            .labelStyle(.titleAndIcon)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(uiColor: quest.terrain.detailColor), in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
            .accessibilityLabel("Quest: grow \(quest.terrain.displayName.lowercased()) to \(quest.target)")
    }
}

/// Draws a tile with the same paths the board uses.
struct TilePreview: View {
    let tile: Tile

    var body: some View {
        Canvas { context, size in
            let geometry = HexGeometry(radius: min(size.height / 2, size.width / 3.squareRoot()))
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: 1, y: -1)
            for layer in TileDrawing.layers(for: tile.edges, geometry: geometry) {
                let path = Path(layer.path)
                if let fill = layer.fill {
                    context.fill(path, with: .color(Color(uiColor: fill)))
                }
                if let stroke = layer.stroke {
                    context.stroke(path, with: .color(Color(uiColor: stroke)), style: StrokeStyle(lineWidth: layer.lineWidth, lineCap: layer.lineCap))
                }
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

// MARK: - Cards

private struct OverlayCard: View {
    let overlay: Overlay
    let model: GameModel

    var body: some View {
        VStack(spacing: 14) {
            switch overlay {
            case .levelIntro: levelIntro
            case .levelWon: levelWon
            case .levelLost: levelLost
            case .allLevelsDone: allLevelsDone
            case .zenOver: zenOver
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 32)
    }

    @ViewBuilder private var levelIntro: some View {
        Text("Level \(model.level)")
            .font(.largeTitle.bold())
        Label("\(model.game.tilesLeft) tiles", systemImage: "hexagon.fill")
            .font(.headline)
            .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.game.goals) { goal in
                TerrainLabel(terrain: goal.terrain, text: "Grow a \(goal.terrain.displayName.lowercased()) of \(goal.target)")
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
        Button {
            model.beginLevel()
        } label: {
            Text("Play").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder private var levelWon: some View {
        Text("Level \(model.level) complete!")
            .font(.title2.bold())
        Text(model.game.score, format: .number)
            .font(.system(.largeTitle, design: .rounded).bold())
            .monospacedDigit()
        if model.game.tilesLeft > 0 {
            Text("+\(model.game.tilesLeft * model.game.rules.unusedTileBonus) for \(tileCount(model.game.tilesLeft)) to spare")
                .foregroundStyle(.secondary)
        }
        Button {
            model.nextLevel()
        } label: {
            Text(model.level < LevelDesigner.levelCount ? "Next level" : "Finish").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder private var levelLost: some View {
        Text("Out of tiles")
            .font(.title2.bold())
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.game.goals) { goal in
                TerrainLabel(terrain: goal.terrain, text: "\(goal.terrain.displayName) \(min(goal.progress, goal.target))/\(goal.target)", isDone: goal.isMet)
                    .font(.headline)
            }
        }
        nearMiss
        continueButton
        Button("Retry level") { model.restart() }
            .buttonStyle(.bordered)
    }

    @ViewBuilder private var allLevelsDone: some View {
        Image(systemName: "trophy.fill")
            .font(.largeTitle)
            .foregroundStyle(.yellow)
        Text("All \(LevelDesigner.levelCount) levels done!")
            .font(.title2.bold())
        Text("More levels are on the way.")
            .foregroundStyle(.secondary)
        Button {
            model.startOver()
        } label: {
            Text("Play again from level 1").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        Button("Try Zen mode") { model.switchMode(to: .zen) }
            .buttonStyle(.bordered)
    }

    @ViewBuilder private var zenOver: some View {
        Text("Out of tiles")
            .font(.title2.bold())
        Text(model.game.score, format: .number)
            .font(.system(.largeTitle, design: .rounded).bold())
            .monospacedDigit()
        Text(model.isNewZenBest ? "New best!" : "Best: \(model.zenBest.formatted())")
            .foregroundStyle(.secondary)
        nearMiss
        continueButton
        Button("New valley") { model.restart() }
            .buttonStyle(.bordered)
    }

    @ViewBuilder private var nearMiss: some View {
        if let miss = model.game.nearMisses.first {
            TerrainLabel(terrain: miss.terrain, text: "So close! Your \(miss.terrain.displayName.lowercased()) was \(tileCount(miss.remaining)) short of \(miss.target).")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.vertical, 4)
        }
    }

    private var continueButton: some View {
        Button {
            model.continueRun()
        } label: {
            VStack(spacing: 2) {
                Text("+\(model.game.rules.continueTiles) tiles")
                    .font(.headline)
                Text("Free while we prototype")
                    .font(.caption)
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func tileCount(_ count: Int) -> String {
        count == 1 ? "1 tile" : "\(count) tiles"
    }
}

/// Dark, readable text with the terrain's color carried by the icon; a green check once done.
private struct TerrainLabel: View {
    let terrain: Terrain
    let text: String
    var isDone = false

    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: isDone ? "checkmark.circle.fill" : terrain.symbolName)
                .foregroundStyle(isDone ? .green : terrain.color)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
    }
}

#Preview {
    GameView()
}
