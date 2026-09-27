import SpriteKit
import SwiftUI
import ValleyCore

struct GameView: View {
    @State private var model = GameModel()

    var body: some View {
        ZStack {
            SpriteView(scene: model.scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            VStack(spacing: 12) {
                TopBar(model: model)
                if let toast = model.toast {
                    ToastView(toast: toast)
                        .id(toast.id)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                if !model.game.isGameOver {
                    TileTray(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if model.game.isGameOver {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                GameOverCard(model: model)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.game.isGameOver)
        .animation(.snappy, value: model.toast)
    }
}

private struct TopBar: View {
    let model: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Stat(symbol: "star.fill", value: model.game.score, tint: .yellow)
                Spacer()
                Stat(symbol: "hexagon.fill", value: model.game.tilesLeft, tint: model.game.tilesLeft <= 3 ? .orange : .mint)
            }
            if !model.game.activeQuests.isEmpty {
                HStack(spacing: 8) {
                    ForEach(model.game.activeQuests) { quest in
                        QuestChip(quest: quest)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.snappy, value: model.game.activeQuests)
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
        .font(.title3.bold())
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .animation(.snappy, value: value)
        .animation(.snappy, value: tint)
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

private struct GameOverCard: View {
    let model: GameModel

    var body: some View {
        VStack(spacing: 14) {
            Text("Out of tiles")
                .font(.title2.bold())
            Text(model.game.score, format: .number)
                .font(.system(.largeTitle, design: .rounded).bold())
                .monospacedDigit()
            Text("\(model.game.tilesPlaced) tiles placed")
                .foregroundStyle(.secondary)

            if let miss = model.game.nearMisses.first {
                Label(nearMissText(miss), systemImage: miss.terrain.symbolName)
                    .font(.headline)
                    .foregroundStyle(miss.terrain.color)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
            }

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

            Button("New valley") { model.newGame() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 32)
    }

    private func nearMissText(_ quest: Quest) -> String {
        let tiles = quest.remaining == 1 ? "1 tile" : "\(quest.remaining) tiles"
        return "So close! Your \(quest.terrain.displayName.lowercased()) was \(tiles) from \(quest.target)."
    }
}

#Preview {
    GameView()
}
