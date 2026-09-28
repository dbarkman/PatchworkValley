import SpriteKit
import SwiftUI
import ValleyCore

struct GameView: View {
    @State private var model = GameModel()

    var body: some View {
        ZStack {
            SpriteView(scene: model.scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            if model.showsIntroFog {
                IntroFog()
                    .transition(.opacity.animation(.easeInOut(duration: 0.8)))
            }

            GlimpseFrameLayer(frame: model.glimpseFrame)


            // Cards sit under the HUD so the menu stays reachable from any card.
            if let overlay = model.overlay {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                OverlayCard(overlay: overlay, model: model)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            VStack(spacing: 12) {
                if model.hud.topBar {
                    TopBar(model: model)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { model.scene.hudTop = $0 }
                        .layoutPriority(1)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                // A demo's own bubble says what to tap.
                if model.isAimingDynamite && model.demoPowerUp == nil {
                    AimingBanner(model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let toast = model.toast {
                    ToastView(toast: toast)
                        .id(toast.id)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                // The intro's power-ups page fills the space above the bubble; otherwise the board shows through.
                if model.showsPowerUpShowcase {
                    PowerUpShowcase()
                        .frame(maxHeight: .infinity)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    Spacer()
                }
                // The coach speaks above the tray; it steps aside while a big coin payout pours in.
                if let line = model.coachLine, !model.isBigPayoutInFlight {
                    CoachBubble(
                        line: line,
                        stepIndex: model.coachStepIndex,
                        dotCount: model.coachDotCount,
                        nudges: model.coachNudges,
                        onSkip: model.showsCoachSkip ? { model.skipCoach() } : nil,
                        onGo: model.coachGoTitle != nil ? { model.coachGo() } : nil,
                        goTitle: model.coachGoTitle ?? "Let's go"
                    )
                    // The valley is framed above the bubble while it shows.
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                        model.scene.coachTop = $0
                        model.fitValleyAboveCoachIfNeeded()
                    }
                    .onDisappear { model.scene.coachTop = 0 }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if model.isViewingValley {
                    ViewingBar(model: model)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                            model.scene.hudBottom = $0
                            model.fitValleyAboveViewingBar()
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if model.overlay == nil && model.hud.tray {
                    TileTray(model: model)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { model.scene.hudBottom = $0 }
                        .layoutPriority(1)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            CoinFlightLayer(flights: model.coinFlights, target: model.coinTarget)
        }
        .animation(.snappy, value: model.overlay)
        .animation(.snappy, value: model.toast)
        .animation(.snappy, value: model.mode)
        .animation(.snappy, value: model.isAimingDynamite)
        .animation(.snappy, value: model.isViewingValley)
        .animation(.snappy, value: model.coachStep)
        .animation(.snappy, value: model.tip)
        .animation(.snappy, value: model.coachLine)
        .animation(.snappy, value: model.isBigPayoutInFlight)
        .task { model.beginFirstRunIfNeeded() }
    }
}

/// Coins streaming from a placed tile up to the coin chip, over everything else.
private struct CoinFlightLayer: View {
    let flights: [CoinFlight]
    /// The chip's coin icon, where coins land, as it is now.
    let target: CGPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(flights) { flight in
                    ForEach(0..<flight.count, id: \.self) { index in
                        FlyingCoin(flight: flight, index: index, target: target)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One coin of a flight: it pops off the tile a little to the side, arcs up to the chip, and shrinks as it lands.
private struct FlyingCoin: View {
    let flight: CoinFlight
    let index: Int
    let target: CGPoint
    @State private var progress: CGFloat = 0
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 20

    var body: some View {
        Image(systemName: "centsign.circle.fill")
            .font(.system(size: size))
            .foregroundStyle(Color(red: 0.45, green: 0.33, blue: 0.0), .yellow)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .modifier(CoinPath(progress: progress, from: start, to: target))
            .onAppear {
                withAnimation(.easeIn(duration: CoinFlight.travel).delay(Double(index) * flight.stagger)) {
                    progress = 1
                }
            }
    }

    /// Coins leave from a little ring around the tile's center, each at its own angle.
    private var start: CGPoint {
        let angle = Double(index) * 2.4
        let reach = size * 0.8
        return CGPoint(x: flight.from.x + cos(angle) * reach, y: flight.from.y + sin(angle) * reach)
    }
}

/// Moves a coin along a curve from `from` to `to` as `progress` goes from 0 to 1. Hidden until it sets off.
private struct CoinPath: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGPoint
    let to: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        // Rise first, then swing across to the chip.
        let control = CGPoint(x: from.x + (to.x - from.x) * 0.15, y: to.y + (from.y - to.y) * 0.25)
        let t = progress
        let point = CGPoint(
            x: (1 - t) * (1 - t) * from.x + 2 * (1 - t) * t * control.x + t * t * to.x,
            y: (1 - t) * (1 - t) * from.y + 2 * (1 - t) * t * control.y + t * t * to.y
        )
        return content
            .scaleEffect(1 - 0.35 * t)
            // Hidden until it sets off, and melting into the chip over the last stretch.
            .opacity(t == 0 ? 0 : min(1, (1 - t) * 8))
            .position(point)
    }
}

/// Shown in place of the tile tray while looking over a finished valley.
private struct ViewingBar: View {
    let model: GameModel

    var body: some View {
        VStack(spacing: 12) {
            Text(model.tip == .save ? Tip.save.line : "Every hidden mountain and lake, revealed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button {
                    model.saveValleyToGallery()
                } label: {
                    Label(saveTitle, systemImage: model.isValleySaved ? "checkmark" : "photo.badge.plus")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isValleySaved || model.isSavingValley)
                .coachMark(model.tip == .save)

                Button("Done") { model.doneViewing() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.snappy, value: model.isValleySaved)
        .animation(.snappy, value: model.isSavingValley)
    }

    private var saveTitle: String {
        model.isValleySaved ? "Saved" : model.isSavingValley ? "Saving…" : "Save to Gallery"
    }
}

/// Shown while Dynamite waits for the player to pick a mountain.
private struct AimingBanner: View {
    let model: GameModel

    var body: some View {
        HStack(spacing: 12) {
            Label("Tap a glowing mountain to blast it", systemImage: PowerUp.dynamite.symbolName)
                .font(.headline)
            Button("Cancel") { model.cancelDynamite() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - Top bar

private struct TopBar: View {
    let model: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if model.hud.menu {
                    GameMenu(model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if model.mode == .coins {
                    CoinsChip(model: model)
                        .coachMark(model.coachMarksCoins)
                } else {
                    Stat(symbol: "star.fill", value: model.game.score, tint: .yellow)
                }
                if model.hud.tilesLeft {
                    TilesLeft(model: model)
                        .coachMark(model.coachMarksTilesLeft)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            HStack(alignment: .top, spacing: 8) {
                if model.hud.quests {
                    objectives
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if model.hud.fit {
                    Button("Fit valley", systemImage: "arrow.down.right.and.arrow.up.left") { model.fitValley() }
                        .labelStyle(.iconOnly)
                        .font(.headline)
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy, value: model.game.goals)
        .animation(.snappy, value: model.questChips)
    }

    @ViewBuilder private var objectives: some View {
        if model.mode == .levels {
            if !model.hasFinishedAllLevels { goals }
        } else if !model.questChips.isEmpty {
            HStack(spacing: 8) {
                ForEach(model.questChips) { quest in
                    QuestChip(quest: quest)
                        .coachMark(model.coachMarksQuestChip)
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

/// The mode switch, restart and gallery, labeled with where the player is.
private struct GameMenu: View {
    let model: GameModel
    @State private var confirming: Confirmation?
    @State private var isShowingGallery = false

    /// The destructive menu actions, which ask first.
    private enum Confirmation {
        case restart, resetPlayer
    }

    var body: some View {
        Menu {
            Picker("Mode", selection: Binding(get: { model.mode }, set: { model.switchMode(to: $0) })) {
                ForEach(GameMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            Button(restartTitle, systemImage: "arrow.counterclockwise") {
                confirming = .restart
            }
            Button("Gallery", systemImage: "photo.on.rectangle.angled") {
                isShowingGallery = true
            }
            if model.mode == .coins {
                Button("How to Play", systemImage: "questionmark.circle") {
                    model.replayCoach()
                }
                .disabled(!model.canReplayCoach)
            }
            Section {
                Button("Reset Player", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                    confirming = .resetPlayer
                }
            }
            // Kept in every build while the game is in testing.
            Section("Debug") {
                switch model.mode {
                case .coins:
                    Button("Add 500 Coins", systemImage: "centsign.circle") { model.debugAddCoins(500) }
                    Button("Next Valley", systemImage: "forward.end") { model.debugJumpValley(to: model.valley + 1) }
                    Button("Previous Valley", systemImage: "backward.end") { model.debugJumpValley(to: model.valley - 1) }
                case .levels:
                    Button("Next Level", systemImage: "forward.end") { model.debugJump(to: model.level + 1) }
                    Button("Previous Level", systemImage: "backward.end") { model.debugJump(to: model.level - 1) }
                case .zen:
                    EmptyView()
                }
            }
        } label: {
            Label(menuTitle, systemImage: "line.3.horizontal")
                .font(.headline)
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: Double(model.mode == .coins ? model.valley : model.level)))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
        .animation(.snappy, value: model.level)
        .animation(.snappy, value: model.valley)
        .sheet(isPresented: $isShowingGallery) {
            GalleryView(gallery: model.gallery)
        }
        .confirmationDialog(
            confirming == .resetPlayer ? "Start over as a new player?" : restartTitle,
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { confirmation in
            switch confirmation {
            case .restart:
                Button(restartTitle, role: .destructive) { model.restart() }
            case .resetPlayer:
                Button("Reset Player", role: .destructive) { model.resetPlayer() }
            }
        } message: { confirmation in
            switch confirmation {
            case .restart:
                Text("This valley will be lost.")
            case .resetPlayer:
                Text("Your rewards, valley, level and best score go back to the start, as if the game were just installed.")
            }
        }
    }

    private var menuTitle: String {
        switch model.mode {
        case .coins: "Valley \(model.valley)"
        case .levels: model.hasFinishedAllLevels ? "Levels" : "Level \(model.level)"
        case .zen: "Zen"
        }
    }

    private var restartTitle: String {
        switch model.mode {
        case .coins: "Restart Valley"
        case .levels: model.hasFinishedAllLevels ? "Start Over" : "Restart Level"
        case .zen: "New Valley"
        }
    }
}

/// The Coin mode wallet, with a brief "+N" whenever a placement earns coins.
private struct CoinsChip: View {
    let model: GameModel

    var body: some View {
        Label {
            Text(model.walletShown, format: .number)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(model.walletShown)))
        } icon: {
            Image(systemName: "centsign.circle.fill")
                .foregroundStyle(.yellow)
                // Flying coins land on this icon.
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .global)
                    return CGPoint(x: frame.midX, y: frame.midY)
                } action: { model.coinChipMoved(to: $0) }
        }
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        // A small pop as each coin lands.
        .keyframeAnimator(initialValue: 1.0, trigger: model.coinLandings) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.08, duration: 0.05)
                CubicKeyframe(1.0, duration: 0.1)
            }
        }
        // Earned coins rise from just below the chip into its total (the Dynamic Island sits above it);
        // spent ones fall out of the bottom.
        .overlay(alignment: .bottom) {
            if let change = model.coinChange {
                CoinChangeText(amount: change.amount)
                    .alignmentGuide(.bottom) { $0[.top] }
                    .id(change.id)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: model.walletShown)
        .animation(.snappy, value: model.coinChange)
        .accessibilityLabel("\(model.wallet) coins")
    }
}

/// "+N" in gold drifting up into the coin chip from just below it, or "−N" in red falling out of it,
/// fading as it goes.
private struct CoinChangeText: View {
    let amount: Int
    @State private var isGone = false
    @ScaledMetric(relativeTo: .headline) private var drift: CGFloat = 26

    var body: some View {
        Text(amount > 0 ? "+\(amount)" : "−\(-amount)")
            .font(.headline.bold())
            .foregroundStyle(amount > 0 ? Color.yellow : Color.red)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .fixedSize()
            // A gain starts a drift below the chip and rises toward it; a spend starts at the chip and falls.
            .offset(y: amount > 0 ? (isGone ? 0 : drift) : (isGone ? drift : 0))
            .opacity(isGone ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1)) { isGone = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

/// A quest's progress. When it ends, it turns green with a check (done) or red with a cross (closed off) before leaving.
private struct QuestChip: View {
    let quest: Quest

    var body: some View {
        Label {
            Text("\(quest.progress)/\(quest.target)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(quest.progress)))
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(iconColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().fill(tint.opacity(0.3)))
        }
        .animation(.snappy, value: quest.progress)
        .animation(.snappy, value: quest.status)
        .accessibilityLabel(accessibilityText)
    }

    private var symbol: String {
        switch quest.status {
        case .active: quest.terrain.symbolName
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch quest.status {
        case .active: quest.terrain.color
        case .completed: .green
        case .failed: .red
        }
    }

    private var tint: Color {
        switch quest.status {
        case .active: .clear
        case .completed: .green
        case .failed: .red
        }
    }

    private var accessibilityText: String {
        let name = quest.terrain.displayName
        return switch quest.status {
        case .active: "\(name) quest, \(quest.progress) of \(quest.target)"
        case .completed: "\(name) quest complete"
        case .failed: "\(name) quest closed off at \(quest.progress) of \(quest.target)"
        }
    }
}

/// A quest a finished valley ended without: how far it got, and whether the last tile closed it off.
private struct QuestOutcomeRow: View {
    let quest: Quest

    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: quest.status == .failed ? "xmark.circle.fill" : quest.terrain.symbolName)
                .foregroundStyle(quest.status == .failed ? .red : quest.terrain.color)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
        .font(.subheadline.weight(.semibold))
    }

    private var text: String {
        let name = quest.terrain.displayName
        return quest.status == .failed
            ? "\(name) closed off at \(quest.progress) of \(quest.target)"
            : "\(name) \(quest.progress) of \(quest.target) · \(quest.remaining) short"
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
        VStack(spacing: 12) {
            tiles
            if model.mode == .coins && model.hud.powerUps {
                PowerUpBar(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.snappy, value: model.game.current?.id)
        .animation(.snappy, value: model.selectedSlot)
        .animation(.snappy, value: model.hud)
    }

    private var tiles: some View {
        HStack(spacing: 16) {
            if let tile = model.game.current {
                // Draw the tile as it was before the player's turns and rotate the view, so each turn animates.
                TilePreview(tile: tile.rotatedClockwise(-model.rotationTurns))
                    .rotationEffect(.degrees(60 * Double(model.rotationTurns)))
                    .animation(.snappy, value: model.rotationTurns)
                    .overlay(alignment: .topTrailing) {
                        if let quest = tile.quest {
                            QuestTag(quest: quest)
                                .coachMark(model.coachMarksQuestTag)
                        }
                    }
                    .frame(width: currentSize, height: currentSize)
                    .id(tile.id)
                    .transition(.scale.combined(with: .opacity))
                    .onTapGesture { model.rotate() }
                    .accessibilityLabel("Current tile. Tap to rotate.")
            }

            if model.hud.next {
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
                .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                status
                    .font(.subheadline)
                    .multilineTextAlignment(.trailing)
                HStack(spacing: 8) {
                    if model.hud.rotate {
                        Button("Rotate", systemImage: "arrow.clockwise") { model.rotate() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            .transition(.scale.combined(with: .opacity))
                    }
                    if model.game.isStuck && model.game.rules.allowsDiscard {
                        Button("Discard") { model.discard() }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    } else {
                        Button("Place") { model.place() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canPlace)
                            .coachMark(model.coachMarksPlace, hand: model.coachHandOnPlace)
                    }
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        if model.game.isStuck {
            Text("This tile fits nowhere")
                .foregroundStyle(.orange)
        } else if model.demoPowerUp != nil {
            // Demo tiles pay nothing; the valley that follows is the real one.
            Text("Practice tile")
                .foregroundStyle(.secondary)
        } else if let reward = model.projectedReward {
            Label {
                Text("+\(reward)")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(reward)))
            } icon: {
                if model.mode == .coins {
                    Image(systemName: "centsign.circle.fill").foregroundStyle(.yellow)
                }
            }
            .font(.headline)
        } else if let evaluation = model.ghostEvaluation {
            Text(evaluation.matchingEdges.isEmpty && model.game.board.requiresMatch ? "Match at least one side" : "Rivers must connect")
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
            case .valleyIntro: valleyIntro
            case .valleyDone: valleyDone
            case .valleyStuck: valleyStuck
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

    @ViewBuilder private var valleyIntro: some View {
        Text("Valley \(model.valley)")
            .font(.largeTitle.bold())
        Label("\(model.game.tilesLeft) tiles", systemImage: "hexagon.fill")
            .font(.headline)
            .foregroundStyle(.secondary)
        if let powerUp = PowerUp.introduced(inValley: model.valley) {
            VStack(spacing: 6) {
                Text("New power-up")
                    .font(.caption.bold())
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Label(powerUp.title, systemImage: powerUp.symbolName)
                    .font(.title3.weight(.semibold))
                Text(powerUp.blurb)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Label("\(powerUp.price) coins", systemImage: "centsign.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 4)
        } else {
            Text("Quests pay rewards. Spend them on power-ups.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        Text("Every tile must match a side. Mountains and lakes hide in the fog, and rivers can flow into lakes.")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        Button {
            model.beginValley()
        } label: {
            // A valley that brings a new power-up opens with a free try of it.
            Text(model.pendingDemo != nil ? "Try it" : "Play").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder private var valleyDone: some View {
        Text("Valley \(model.valley) complete!")
            .font(.title2.bold())
        Label("\(model.game.coins) coins earned", systemImage: "centsign.circle.fill")
            .font(.title3.weight(.semibold))
        Text("Plus a \(CoinEconomy.valleyBonus) coin finishing bonus")
            .foregroundStyle(.secondary)
        // Quests the valley ends without; +3 tiles is offered when one is within three tiles.
        let unfinished = model.game.unfinishedQuests
        if !unfinished.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(unfinished) { quest in
                    QuestOutcomeRow(quest: quest)
                }
            }
            .padding(.vertical, 4)
        }
        if model.offersMoreTiles {
            continueButton
        }
        if model.tip == .viewValley {
            Text(Tip.viewValley.line)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .transition(.opacity)
        }
        Button {
            model.viewValley()
        } label: {
            Label("View valley", systemImage: "binoculars.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .coachMark(model.tip == .viewValley)
        Button {
            model.nextValley()
        } label: {
            Text("Next valley").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        // When a +3 tiles offer is showing, it leads; moving on is the quieter choice.
        .tint(model.offersMoreTiles ? .secondary : .accentColor)
        .controlSize(.large)
    }

    @ViewBuilder private var valleyStuck: some View {
        Text("No room for this tile")
            .font(.title2.bold())
        if let tile = model.game.current {
            TilePreview(tile: tile)
                .frame(width: 64, height: 64)
        }
        Text(model.canRescue ? "It doesn't match anywhere it could go. Rescue it:" : "It doesn't match anywhere it could go.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        if model.tip == .noRoom {
            Text(Tip.noRoom.line)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .transition(.opacity)
        }
        let rescues = [PowerUp.swap, .undo, .wildcard, .dynamite].filter(model.isUnlocked)
        if !rescues.isEmpty {
            HStack(spacing: 8) {
                ForEach(rescues) { powerUp in
                    PowerUpButton(powerUp: powerUp, model: model)
                }
            }
        }
        // On bought tiles the valley is already done, so it can end as done instead of being replayed.
        if model.game.hasFinishedStack {
            Button {
                model.finishValley()
            } label: {
                Text("Finish valley").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.canRescue ? .secondary : .accentColor)
            .controlSize(.large)
        } else {
            Button {
                model.restart()
            } label: {
                Text("Retry valley").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.canRescue ? .secondary : .accentColor)
            .controlSize(.large)
        }
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
                Group {
                    if model.mode != .coins {
                        Text("Free while we prototype")
                    } else if model.canAffordMoreTiles {
                        Label("\(CoinEconomy.continuePrice) coins", systemImage: "centsign.circle.fill")
                    } else {
                        Text("Needs \(CoinEconomy.continuePrice) coins")
                    }
                }
                .font(.caption)
                .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.canAffordMoreTiles)
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

/// Coin mode's power-ups, each showing its price. Locked ones stay hidden until their valley introduces them.
private struct PowerUpBar: View {
    let model: GameModel

    var body: some View {
        HStack(spacing: 6) {
            // A demo shows only the power-up it's about.
            ForEach(model.demoPowerUp.map { [$0] } ?? PowerUp.allCases.filter(model.isUnlocked)) { powerUp in
                PowerUpButton(powerUp: powerUp, model: model)
            }
        }
    }
}

private struct PowerUpButton: View {
    let powerUp: PowerUp
    let model: GameModel

    var body: some View {
        Button {
            model.use(powerUp)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: powerUp.symbolName)
                    .font(.headline)
                Text(powerUp.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Label("\(powerUp.price)", systemImage: "centsign.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .coachMark(model.coachPowerUp == powerUp || (model.tip == .swap && powerUp == .swap), hand: model.coachPowerUp == powerUp)
        // Dynamite with nothing to blast looks off but still answers a tap, to say why.
        .tint(explainsOnTap ? .secondary : nil)
        .opacity(explainsOnTap ? 0.55 : 1)
        .disabled(!model.canUse(powerUp) && !explainsOnTap)
        .accessibilityLabel("\(powerUp.title), \(powerUp.price) coins")
        .animation(.snappy, value: explainsOnTap)
    }

    private var explainsOnTap: Bool {
        powerUp == .dynamite && model.hasNoDynamiteTarget
    }
}

extension PowerUp {
    var title: String {
        switch self {
        case .undo: "Undo"
        case .swap: "Swap"
        case .wildcard: "Wildcard"
        case .dynamite: "Dynamite"
        case .lantern: "Lantern"
        }
    }

    var symbolName: String {
        switch self {
        case .undo: "arrow.uturn.backward"
        case .swap: "arrow.triangle.2.circlepath"
        case .wildcard: "sparkles"
        case .dynamite: "burst.fill"
        case .lantern: "lightbulb.fill"
        }
    }

    /// A few words for the intro's power-ups page.
    var pitch: String {
        switch self {
        case .undo: "Take back your last tile"
        case .swap: "Trade your tile for another"
        case .wildcard: "A patch that matches anything"
        case .dynamite: "Blast a mountain out of the way"
        case .lantern: "Light up what the fog hides"
        }
    }

    var blurb: String {
        switch self {
        case .undo: "Take back your last tile, and the rewards it earned."
        case .swap: "Trade the tile in your hand for a fresh one."
        case .wildcard: "Turn the tile in your hand into a patch that matches anything."
        case .dynamite: "Blast a mountain you can see, opening the ground beneath it."
        case .lantern: "Light up every mountain and lake in the valley. The fog returns after your next tile."
        }
    }
}

#Preview {
    GameView()
}
