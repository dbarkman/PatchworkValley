import Observation
import SwiftUI
import ValleyCore

enum GameMode: String, CaseIterable, Identifiable {
    /// Fixed stacks of tiles with goals to meet.
    case levels
    /// One endless valley for a high score; quests earn more tiles.
    case zen

    var id: Self { self }
    var title: String { self == .levels ? "Levels" : "Zen" }
    var symbolName: String { self == .levels ? "flag.checkered" : "leaf" }
}

/// The card covering the board, if any.
enum Overlay: Equatable {
    case levelIntro, levelWon, levelLost, allLevelsDone, zenOver
}

/// Short feedback shown over the board after a notable placement.
struct Toast: Equatable {
    let id: Int
    let message: String
    let symbolName: String
}

/// A brief "+N" on the tile counter when a placement earns tiles.
struct TileGain: Equatable {
    let id: Int
    let amount: Int
}

/// Owns both modes' runs and the player's in-progress choice. Views read it; the
/// scene renders it and forwards taps to it.
@Observable
final class GameModel {
    private(set) var mode: GameMode
    /// The level being played, or the next one up after a win. One past the last level means all are done.
    private(set) var level: Int
    private(set) var zenBest: Int
    /// The current Zen run beat the saved best.
    private(set) var isNewZenBest = false
    private(set) var levelGame: ValleyGame
    private(set) var zenGame: ValleyGame
    private(set) var isShowingLevelIntro = true
    /// The open slot the ghost tile sits on, waiting for Place.
    private(set) var selectedSlot: Hex?
    /// Clockwise turns applied to the current tile, so views can animate the spin.
    private(set) var rotationTurns = 0
    private(set) var toast: Toast?
    private(set) var tileGain: TileGain?

    @ObservationIgnored let scene: ValleyScene
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var feedbackCount = 0

    private enum Key {
        static let mode = "mode"
        static let level = "level"
        static let zenBest = "zenBest"
    }

    init() {
        let defaults = UserDefaults.standard
        let level = min(max(1, defaults.integer(forKey: Key.level)), LevelDesigner.levelCount + 1)
        mode = GameMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .levels
        self.level = level
        zenBest = defaults.integer(forKey: Key.zenBest)
        levelGame = ValleyGame(level: LevelDesigner.level(min(level, LevelDesigner.levelCount)))
        zenGame = Self.makeZenGame()
        scene = ValleyScene(size: CGSize(width: 390, height: 844))
        scene.model = self
    }

    /// The run on screen.
    private(set) var game: ValleyGame {
        get { mode == .levels ? levelGame : zenGame }
        set {
            if mode == .levels {
                levelGame = newValue
            } else {
                zenGame = newValue
            }
        }
    }

    var hasFinishedAllLevels: Bool { level > LevelDesigner.levelCount }

    var overlay: Overlay? {
        if mode == .levels && hasFinishedAllLevels { return .allLevelsDone }
        return switch (mode, game.outcome) {
        case (.levels, .playing): isShowingLevelIntro ? .levelIntro : nil
        case (.levels, .won): .levelWon
        case (.levels, .outOfTiles): .levelLost
        case (.zen, .outOfTiles): .zenOver
        case (.zen, _): nil
        }
    }

    var ghostEvaluation: PlacementEvaluation? {
        selectedSlot.flatMap { game.evaluateCurrent(at: $0) }
    }

    var canPlace: Bool { ghostEvaluation?.isLegal == true }

    var projectedPoints: Int? {
        ghostEvaluation.flatMap { $0.isLegal ? game.points(for: $0) : nil }
    }

    // MARK: - Playing

    /// First tap on a slot moves the ghost there in its best rotation; tapping the ghost again cycles fitting rotations.
    func tap(_ hex: Hex) {
        guard overlay == nil, let tile = game.current, game.board.openSlots.contains(hex) else { return }
        if hex == selectedSlot {
            let steps = (1...6).first { game.board.canPlace(tile.rotatedClockwise($0), at: hex) } ?? 1
            turn(steps)
        } else {
            selectedSlot = hex
            if let steps = game.board.bestRotation(for: tile, at: hex), steps != 0 {
                turn(steps)
            }
        }
        haptics.select()
        scene.sync()
    }

    func rotate() {
        guard overlay == nil, game.current != nil else { return }
        turn(1)
        haptics.select()
        scene.sync()
    }

    func place() {
        guard overlay == nil, let slot = selectedSlot, let result = game.placeCurrent(at: slot) else {
            haptics.warn()
            return
        }
        resetSelection()
        if result.tilesAwarded > 0 { showTileGain(result.tilesAwarded) }
        if mode == .levels, game.outcome == .won { defaults.set(level + 1, forKey: Key.level) }
        if mode == .zen, game.outcome == .outOfTiles { recordZenScore() }
        announce(result)
        scene.sync(placement: result)
    }

    func discard() {
        game.discardCurrent()
        resetSelection()
        haptics.warn()
        if mode == .zen, game.outcome == .outOfTiles { recordZenScore() }
        scene.sync()
    }

    func continueRun() {
        game.continueRun()
        haptics.success()
        scene.sync()
    }

    // MARK: - Modes and levels

    func switchMode(to newMode: GameMode) {
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Key.mode)
        resetSelection()
        clearFeedback()
        scene.sync()
        scene.recenter()
    }

    func beginLevel() {
        isShowingLevelIntro = false
        scene.sync()
    }

    func restart() {
        switch mode {
        case .levels:
            // Once every level is done, restarting means starting over.
            startLevel(hasFinishedAllLevels ? 1 : level, canRewindProgress: hasFinishedAllLevels)
        case .zen:
            zenGame = Self.makeZenGame()
            isNewZenBest = false
            resetSelection()
            clearFeedback()
            scene.sync()
            scene.recenter()
        }
    }

    func nextLevel() {
        guard level < LevelDesigner.levelCount else {
            level = LevelDesigner.levelCount + 1
            defaults.set(level, forKey: Key.level)
            haptics.success()
            return
        }
        startLevel(level + 1)
    }

    /// Replays the levels from the first one.
    func startOver() {
        startLevel(1, canRewindProgress: true)
    }

    #if DEBUG
    func debugJump(to number: Int) {
        startLevel(min(max(1, number), LevelDesigner.levelCount), canRewindProgress: true)
    }
    #endif

    /// Saved progress only moves forward, so replaying a beaten level never locks the next one again.
    private func startLevel(_ number: Int, canRewindProgress: Bool = false) {
        level = number
        let saved = defaults.integer(forKey: Key.level)
        defaults.set(canRewindProgress ? number : max(number, saved), forKey: Key.level)
        levelGame = ValleyGame(level: LevelDesigner.level(number))
        isShowingLevelIntro = true
        resetSelection()
        clearFeedback()
        scene.sync()
        scene.recenter()
    }

    private static func makeZenGame() -> ValleyGame {
        var rules = Rules()
        #if DEBUG
        // Launch with `-startingTiles 3` to reach the end of a Zen run quickly.
        let startingTiles = UserDefaults.standard.integer(forKey: "startingTiles")
        if startingTiles > 0 { rules.startingTiles = startingTiles }
        #endif
        return ValleyGame(seed: .random(in: .min ... .max), rules: rules)
    }

    private func recordZenScore() {
        guard game.score > zenBest else { return }
        zenBest = game.score
        isNewZenBest = true
        defaults.set(zenBest, forKey: Key.zenBest)
    }

    // MARK: - Feedback

    private func resetSelection() {
        selectedSlot = nil
        rotationTurns = 0
    }

    /// Toasts and tile flashes belong to the run that made them.
    private func clearFeedback() {
        toast = nil
        tileGain = nil
    }

    private func turn(_ steps: Int) {
        game.rotateCurrent(clockwiseSteps: steps)
        rotationTurns += steps
    }

    private func announce(_ result: PlacementResult) {
        switch game.outcome {
        case .won:
            haptics.success()
        case .outOfTiles:
            haptics.warn()
        case .playing:
            let notable = !result.metGoals.isEmpty || !result.completedQuests.isEmpty || result.evaluation.isPerfect
            notable ? haptics.success() : haptics.place()
        }
        // When the run ends, the card that comes up says it all.
        guard game.outcome == .playing else { return }

        if let goal = result.metGoals.first {
            show("\(goal.terrain.displayName) goal done!", symbol: "checkmark.circle.fill")
        } else if let quest = result.completedQuests.first {
            show("\(quest.terrain.displayName) complete! +\(game.rules.questReward(for: quest.target)) tiles", symbol: quest.terrain.symbolName)
        } else if result.evaluation.isPerfect {
            let reward = game.rules.perfectBonusTiles > 0 ? "+\(game.rules.perfectBonusTiles) tile" : "+\(game.rules.perfectPoints)"
            show("Perfect fit! \(reward)", symbol: "sparkles")
        } else if let quest = result.failedQuests.first {
            show("\(quest.terrain.displayName) quest closed off", symbol: "xmark.circle")
        }
    }

    private func show(_ message: String, symbol: String) {
        feedbackCount += 1
        let toast = Toast(id: feedbackCount, message: message, symbolName: symbol)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(2))
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }

    private func showTileGain(_ amount: Int) {
        feedbackCount += 1
        let gain = TileGain(id: feedbackCount, amount: amount)
        tileGain = gain
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if self.tileGain?.id == gain.id { self.tileGain = nil }
        }
    }
}

struct Haptics {
    func select() { UISelectionFeedbackGenerator().selectionChanged() }
    func place() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    func warn() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
