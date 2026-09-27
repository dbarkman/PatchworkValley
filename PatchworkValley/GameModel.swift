import Observation
import SwiftUI
import ValleyCore

/// Short feedback shown over the board after a notable placement.
struct Toast: Equatable {
    let id: Int
    let message: String
    let symbolName: String
}

/// Owns the run and the player's in-progress choice. Views read it; the scene
/// renders it and forwards taps to it.
@Observable
final class GameModel {
    private(set) var game: ValleyGame
    /// The open slot the ghost tile sits on, waiting for Place.
    private(set) var selectedSlot: Hex?
    /// Clockwise turns applied to the current tile, so views can animate the spin.
    private(set) var rotationTurns = 0
    private(set) var toast: Toast?

    @ObservationIgnored let scene: ValleyScene
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private var toastCount = 0

    init() {
        game = ValleyGame(seed: .random(in: .min ... .max), rules: Self.rules)
        scene = ValleyScene(size: CGSize(width: 390, height: 844))
        scene.model = self
    }

    private static var rules: Rules {
        var rules = Rules()
        #if DEBUG
        // Launch with `-startingTiles 3` to reach the end of a run quickly.
        let startingTiles = UserDefaults.standard.integer(forKey: "startingTiles")
        if startingTiles > 0 { rules.startingTiles = startingTiles }
        #endif
        return rules
    }

    var ghostEvaluation: PlacementEvaluation? {
        selectedSlot.flatMap { game.evaluateCurrent(at: $0) }
    }

    var canPlace: Bool { ghostEvaluation?.isLegal == true }

    var projectedPoints: Int? {
        ghostEvaluation.flatMap { $0.isLegal ? game.points(for: $0) : nil }
    }

    /// First tap on a slot moves the ghost there in its best rotation; tapping the ghost again cycles fitting rotations.
    func tap(_ hex: Hex) {
        guard let tile = game.current, game.board.openSlots.contains(hex) else { return }
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
        guard game.current != nil else { return }
        turn(1)
        haptics.select()
        scene.sync()
    }

    func place() {
        guard let slot = selectedSlot, let result = game.placeCurrent(at: slot) else {
            haptics.warn()
            return
        }
        selectedSlot = nil
        rotationTurns = 0
        announce(result)
        scene.sync(placement: result)
    }

    func discard() {
        game.discardCurrent()
        selectedSlot = nil
        rotationTurns = 0
        haptics.warn()
        scene.sync()
    }

    func continueRun() {
        game.continueRun()
        haptics.success()
        scene.sync()
    }

    func newGame() {
        game = ValleyGame(seed: .random(in: .min ... .max), rules: Self.rules)
        selectedSlot = nil
        rotationTurns = 0
        toast = nil
        scene.sync()
        scene.recenter()
    }

    private func turn(_ steps: Int) {
        game.rotateCurrent(clockwiseSteps: steps)
        rotationTurns += steps
    }

    private func announce(_ result: PlacementResult) {
        if game.isGameOver {
            haptics.warn()
        } else if !result.completedQuests.isEmpty || result.evaluation.isPerfect {
            haptics.success()
        } else {
            haptics.place()
        }

        if let quest = result.completedQuests.first {
            show("\(quest.terrain.displayName) complete! +\(game.rules.questReward(for: quest.target)) tiles", symbol: quest.terrain.symbolName)
        } else if result.evaluation.isPerfect {
            show("Perfect fit! +\(game.rules.perfectBonusTiles) tile", symbol: "sparkles")
        } else if let quest = result.failedQuests.first {
            show("\(quest.terrain.displayName) quest closed off", symbol: "xmark.circle")
        }
    }

    private func show(_ message: String, symbol: String) {
        toastCount += 1
        let toast = Toast(id: toastCount, message: message, symbolName: symbol)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(2))
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }
}

struct Haptics {
    func select() { UISelectionFeedbackGenerator().selectionChanged() }
    func place() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    func warn() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
