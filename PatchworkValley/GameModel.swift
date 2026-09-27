import Observation
import SwiftUI
import ValleyCore

enum GameMode: String, CaseIterable, Identifiable {
    /// Numbered 36-tile valleys whose quests pay coins, spent on power-ups.
    case coins
    /// Fixed stacks of tiles with goals to meet.
    case levels
    /// One endless valley for a high score; quests earn more tiles.
    case zen

    var id: Self { self }

    var title: String {
        switch self {
        case .coins: "Coins"
        case .levels: "Levels"
        case .zen: "Zen"
        }
    }

    var symbolName: String {
        switch self {
        case .coins: "centsign.circle"
        case .levels: "flag.checkered"
        case .zen: "leaf"
        }
    }
}

/// The card covering the board, if any.
enum Overlay: Equatable {
    case valleyIntro, valleyDone, valleyStuck
    case levelIntro, levelWon, levelLost, allLevelsDone
    case zenOver
}

/// A Coin mode run as it was before its last placement, for Undo.
struct UndoPoint {
    let game: ValleyGame
    /// Coins that placement earned, which Undo takes back.
    let coins: Int
}

/// Short feedback shown over the board after a notable placement.
struct Toast: Equatable {
    let id: Int
    let message: String
    let symbolName: String
}

/// A brief "+N" on a counter when a placement earns tiles or coins.
struct Gain: Equatable {
    let id: Int
    let amount: Int
}

/// Owns both modes' runs and the player's in-progress choice. Views read it; the
/// scene renders it and forwards taps to it.
@Observable
final class GameModel {
    private(set) var mode: GameMode
    /// The Coin mode valley being played.
    private(set) var valley: Int
    private(set) var wallet: Int
    private(set) var coinGame: ValleyGame
    private(set) var isShowingValleyIntro = true
    private(set) var undoPoint: UndoPoint?
    /// Dynamite is bought and waiting for the player to tap a mountain.
    private(set) var isAimingDynamite = false
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
    private(set) var tileGain: Gain?
    private(set) var coinGain: Gain?

    @ObservationIgnored let scene: ValleyScene
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var feedbackCount = 0

    private enum Key {
        static let mode = "mode"
        static let valley = "valley"
        static let wallet = "wallet"
        static let level = "level"
        static let zenBest = "zenBest"
    }

    init() {
        let defaults = UserDefaults.standard
        let valley = max(1, defaults.integer(forKey: Key.valley))
        let level = min(max(1, defaults.integer(forKey: Key.level)), LevelDesigner.levelCount + 1)
        mode = GameMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .coins
        self.valley = valley
        wallet = defaults.object(forKey: Key.wallet) == nil ? CoinEconomy.startingWallet : defaults.integer(forKey: Key.wallet)
        coinGame = Self.makeCoinGame(valley: valley)
        self.level = level
        zenBest = defaults.integer(forKey: Key.zenBest)
        levelGame = ValleyGame(level: LevelDesigner.level(min(level, LevelDesigner.levelCount)))
        zenGame = Self.makeZenGame()
        scene = ValleyScene(size: CGSize(width: 390, height: 844))
        scene.model = self
    }

    /// The run on screen.
    private(set) var game: ValleyGame {
        get {
            switch mode {
            case .coins: coinGame
            case .levels: levelGame
            case .zen: zenGame
            }
        }
        set {
            switch mode {
            case .coins: coinGame = newValue
            case .levels: levelGame = newValue
            case .zen: zenGame = newValue
            }
        }
    }

    var hasFinishedAllLevels: Bool { level > LevelDesigner.levelCount }

    var overlay: Overlay? {
        if mode == .levels && hasFinishedAllLevels { return .allLevelsDone }
        return switch (mode, game.outcome) {
        case (.coins, .outOfTiles): .valleyDone
        case (.coins, .outOfRoom): isAimingDynamite ? nil : .valleyStuck
        case (.coins, _): isShowingValleyIntro ? .valleyIntro : nil
        case (.levels, .playing): isShowingLevelIntro ? .levelIntro : nil
        case (.levels, .won): .levelWon
        case (.levels, .outOfTiles): .levelLost
        // Levels allow discards, so they never run out of room.
        case (.levels, .outOfRoom): nil
        case (.zen, .outOfTiles): .zenOver
        case (.zen, _): nil
        }
    }

    var ghostEvaluation: PlacementEvaluation? {
        selectedSlot.flatMap { game.evaluateCurrent(at: $0) }
    }

    var canPlace: Bool { ghostEvaluation?.isLegal == true }

    /// What placing the ghost would earn now: coins in Coin mode, points elsewhere.
    var projectedReward: Int? {
        guard let evaluation = ghostEvaluation, evaluation.isLegal else { return nil }
        return mode == .coins ? game.coins(for: evaluation) : game.points(for: evaluation)
    }

    // MARK: - Playing

    /// First tap on a slot moves the ghost there in its best rotation; tapping the ghost again cycles fitting rotations.
    func tap(_ hex: Hex) {
        if isAimingDynamite {
            blast(hex)
            return
        }
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
        let before = game
        guard overlay == nil, let slot = selectedSlot, let result = game.placeCurrent(at: slot) else {
            haptics.warn()
            return
        }
        resetSelection()
        if result.tilesAwarded > 0 { showTileGain(result.tilesAwarded) }
        if mode == .coins {
            undoPoint = UndoPoint(game: before, coins: result.coins)
            if result.coins > 0 {
                addCoins(result.coins)
                showCoinGain(result.coins)
            }
            // Bank a finished valley right away, so quitting on the end card never loses it.
            if !before.hasFinishedStack && game.hasFinishedStack {
                addCoins(CoinEconomy.valleyBonus)
                defaults.set(valley + 1, forKey: Key.valley)
            }
        }
        if mode == .levels, game.outcome == .won { defaults.set(level + 1, forKey: Key.level) }
        if mode == .zen, game.outcome == .outOfTiles { recordZenScore() }
        announce(result)
        scene.sync(placement: result)
    }

    func discard() {
        guard game.rules.allowsDiscard else { return }
        game.discardCurrent()
        resetSelection()
        haptics.warn()
        if mode == .zen, game.outcome == .outOfTiles { recordZenScore() }
        scene.sync()
    }

    var canAffordMoreTiles: Bool {
        mode != .coins || wallet >= CoinEconomy.continuePrice
    }

    /// The end card offers more tiles only when the stack is empty and a quest or goal is close.
    var offersMoreTiles: Bool {
        game.canContinue && !game.nearMisses.isEmpty
    }

    /// "+N tiles" after running out: free in Levels and Zen, bought with coins in Coin mode.
    func continueRun() {
        guard canAffordMoreTiles else {
            haptics.warn()
            return
        }
        guard game.canContinue else { return }
        if mode == .coins {
            addCoins(-CoinEconomy.continuePrice)
            undoPoint = nil
        }
        game.continueRun()
        haptics.success()
        scene.sync()
    }

    // MARK: - Power-ups

    func isUnlocked(_ powerUp: PowerUp) -> Bool {
        valley >= powerUp.unlockValley
    }

    /// Power-ups work during play and from the out-of-room card, as a rescue.
    func canUse(_ powerUp: PowerUp) -> Bool {
        guard mode == .coins, overlay == nil || overlay == .valleyStuck, !isAimingDynamite,
              isUnlocked(powerUp), game.current != nil else { return false }
        let board = game.board
        switch powerUp {
        case .undo:
            // Undo also takes back the coins the placement earned.
            guard let undoPoint else { return false }
            return wallet - undoPoint.coins >= powerUp.price
        case .swap:
            return wallet >= powerUp.price
        case .wildcard:
            return wallet >= powerUp.price && game.current?.isWild == false
        case .dynamite:
            return wallet >= powerUp.price && !board.clearableMountains.isEmpty
        case .lantern:
            return wallet >= powerUp.price && board.revealedMountains != board.mountains
        }
    }

    /// Any power-up that could get an out-of-room valley going again.
    var canRescue: Bool {
        [PowerUp.undo, .swap, .wildcard, .dynamite].contains(where: canUse)
    }

    func use(_ powerUp: PowerUp) {
        guard canUse(powerUp) else {
            haptics.warn()
            return
        }
        switch powerUp {
        case .undo:
            guard let undoPoint else { return }
            coinGame = undoPoint.game
            addCoins(-undoPoint.coins)
        case .swap:
            coinGame.swapCurrent()
        case .wildcard:
            coinGame.makeCurrentWild()
        case .dynamite:
            // Paid for when a mountain is actually blasted.
            isAimingDynamite = true
            resetSelection()
            haptics.select()
            scene.sync()
            return
        case .lantern:
            coinGame.lightCrater()
        }
        addCoins(-powerUp.price)
        undoPoint = nil
        resetSelection()
        haptics.success()
        scene.sync()
    }

    func cancelDynamite() {
        isAimingDynamite = false
        scene.sync()
    }

    private func blast(_ hex: Hex) {
        guard coinGame.clearMountain(at: hex) else {
            haptics.warn()
            return
        }
        addCoins(-PowerUp.dynamite.price)
        isAimingDynamite = false
        undoPoint = nil
        haptics.success()
        scene.sync(blasted: hex)
    }

    // MARK: - Valleys

    func beginValley() {
        isShowingValleyIntro = false
        scene.sync()
    }

    /// Deals the next valley. The finishing bonus was banked when the stack ran out.
    func nextValley() {
        startValley(valley + 1)
    }

    /// Saved progress only moves forward, so replaying a finished valley never loses the next one.
    private func startValley(_ number: Int, canRewindProgress: Bool = false) {
        valley = number
        let saved = defaults.integer(forKey: Key.valley)
        defaults.set(canRewindProgress ? number : max(number, saved), forKey: Key.valley)
        coinGame = Self.makeCoinGame(valley: number)
        isShowingValleyIntro = true
        isAimingDynamite = false
        undoPoint = nil
        resetSelection()
        clearFeedback()
        scene.sync()
        scene.recenter()
    }

    private static func makeCoinGame(valley: Int) -> ValleyGame {
        ValleyGame(seed: .random(in: .min ... .max), rules: .coins(valley: valley))
    }

    private func addCoins(_ amount: Int) {
        wallet = max(0, wallet + amount)
        defaults.set(wallet, forKey: Key.wallet)
    }

    // MARK: - Modes and levels

    func switchMode(to newMode: GameMode) {
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Key.mode)
        isAimingDynamite = false
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
        case .coins:
            startValley(valley)
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
    func debugAddCoins(_ amount: Int) {
        addCoins(amount)
    }

    func debugJumpValley(to number: Int) {
        startValley(max(1, number), canRewindProgress: true)
    }

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

    /// Toasts and counter flashes belong to the run that made them.
    private func clearFeedback() {
        toast = nil
        tileGain = nil
        coinGain = nil
    }

    private func turn(_ steps: Int) {
        // A wildcard looks and plays the same every way round, so it doesn't turn.
        guard game.current?.isWild == false else { return }
        game.rotateCurrent(clockwiseSteps: steps)
        rotationTurns += steps
    }

    private func announce(_ result: PlacementResult) {
        switch game.outcome {
        case .won:
            haptics.success()
        case .outOfTiles, .outOfRoom:
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
            let reward = game.rules.questsRewardTiles
                ? "+\(game.rules.questReward(for: quest.target)) tiles"
                : "+\(game.rules.questCoins(for: quest.target)) coins"
            show("\(quest.terrain.displayName) complete! \(reward)", symbol: quest.terrain.symbolName)
        } else if result.evaluation.isPerfect {
            let reward = if game.rules.perfectBonusTiles > 0 {
                "+\(game.rules.perfectBonusTiles) tile"
            } else if game.rules.coinsPerPerfect > 0 {
                "+\(game.rules.coinsPerPerfect) coins"
            } else {
                "+\(game.rules.perfectPoints)"
            }
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
        let gain = Gain(id: feedbackCount, amount: amount)
        tileGain = gain
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if self.tileGain?.id == gain.id { self.tileGain = nil }
        }
    }

    private func showCoinGain(_ amount: Int) {
        feedbackCount += 1
        let gain = Gain(id: feedbackCount, amount: amount)
        coinGain = gain
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if self.coinGain?.id == gain.id { self.coinGain = nil }
        }
    }
}

struct Haptics {
    func select() { UISelectionFeedbackGenerator().selectionChanged() }
    func place() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    func warn() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
