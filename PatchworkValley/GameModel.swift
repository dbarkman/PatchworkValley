import Observation
import SwiftUI
import ValleyCore

enum GameMode: String, CaseIterable, Identifiable {
    /// Numbered valleys (24, 30, then 36 tiles) whose quests pay coins, spent on power-ups.
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
    /// The coin flight that placement sent, which Undo stops mid-air.
    var flightID: Int?
}

/// Short feedback shown over the board after a notable placement.
struct Toast: Equatable {
    let id: Int
    let message: String
    let symbolName: String
}

/// A brief "+N" on a counter when a placement earns tiles or coins, or "−N" when coins are spent.
struct Gain: Equatable {
    let id: Int
    let amount: Int
}

/// Coins on their way from a placed tile to the coin chip, one per coin earned. `from` is in view points;
/// they land wherever the chip's coin icon is by then.
struct CoinFlight: Equatable, Identifiable {
    let id: Int
    let count: Int
    let from: CGPoint

    /// Seconds each coin takes to reach the chip.
    static let travel = 0.6

    /// Seconds between coins leaving, so a big payout pours in over under a second.
    var stagger: Double { min(0.05, 0.8 / Double(max(count, 1))) }
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
    /// "+N" rising from the coin chip as earned coins land, or "−N" falling from it when coins are spent.
    private(set) var coinChange: Gain?
    /// The total the coin chip shows. It catches up with the wallet as flying coins land.
    private(set) var walletShown: Int
    private(set) var coinFlights: [CoinFlight] = []
    /// Counts coins landing on the chip, so it can pop with each one.
    private(set) var coinLandings = 0
    /// Where flying coins land: the coin icon on the chip, in view points, kept current as the chip moves.
    private(set) var coinTarget = CGPoint.zero
    /// Coins earned but still in the air. The chip shows the wallet less these.
    @ObservationIgnored private var coinsInFlight = 0
    /// Each flight's landing task and how many of its coins are still in the air.
    @ObservationIgnored private var flightTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var flightRemaining: [Int: Int] = [:]
    /// Quests that just ended, kept on their chips for a moment to show how they ended.
    private(set) var endedQuestIDs: Set<Int> = []
    /// Looking over a finished valley, card put away, every mountain and lake in view.
    private(set) var isViewingValley = false
    /// The finished valley has been looked over, so it stays in full view behind its card.
    private(set) var hasRevealedValley = false
    /// The gallery entry saved from the finished valley, if any.
    private var savedEntryID: UUID?
    /// The finished valley is in the gallery (and hasn't been deleted from it since).
    var isValleySaved: Bool {
        savedEntryID.map { id in gallery.entries.contains { $0.id == id } } ?? false
    }
    /// Frame the whole valley once the view bar has settled, then leave the camera to the player.
    @ObservationIgnored private var needsValleyFit = false
    /// The finished valley is being drawn and written to the gallery.
    private(set) var isSavingValley = false
    /// Tells a save that finishes late whether it still belongs to the valley on screen.
    @ObservationIgnored private var saveToken = UUID()
    let gallery = Gallery()

    /// The first-run coach's step, or nil when no one is coaching.
    private(set) var coachStep: CoachStep?
    /// "How to Play" from the menu: the coach walks through the next tiles with the whole HUD in view.
    private(set) var isReplayingCoach = false
    /// The spot the coach points at for the tile in hand, fixed when its step begins.
    private(set) var coachSpot: Hex?
    /// The tile in hand turned the way the coached step wants it placed.
    private(set) var coachTile: Tile?
    /// Counts taps somewhere other than where the coach points, so the bubble can shake.
    private(set) var coachNudges = 0
    private(set) var glimpsePhase: GlimpsePhase?
    /// Where the glimpse's photo frame goes, in view points.
    private(set) var glimpseFrame: CGRect?
    /// A one-time tip showing now.
    private(set) var tip: Tip?
    @ObservationIgnored private var glimpseBoard: Board?
    @ObservationIgnored private var glimpseToken = 0
    @ObservationIgnored private var tipsSeen: Set<String> = []
    /// A new player on valley 1 who hasn't had the first run yet.
    @ObservationIgnored private var needsFirstRun = false

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
        static let tutorialDone = "tutorialDone"
        static let tipsSeen = "tipsSeen"
        static let all = [mode, valley, wallet, level, zenBest, tutorialDone, tipsSeen]
    }

    init() {
        let defaults = UserDefaults.standard
        let valley = max(1, defaults.integer(forKey: Key.valley))
        let level = min(max(1, defaults.integer(forKey: Key.level)), LevelDesigner.levelCount + 1)
        let mode = GameMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .coins
        self.mode = mode
        self.valley = valley
        let wallet = defaults.object(forKey: Key.wallet) == nil ? CoinEconomy.startingWallet : defaults.integer(forKey: Key.wallet)
        self.wallet = wallet
        walletShown = wallet
        coinGame = Self.makeCoinGame(valley: valley)
        self.level = level
        zenBest = defaults.integer(forKey: Key.zenBest)
        levelGame = ValleyGame(level: LevelDesigner.level(min(level, LevelDesigner.levelCount)))
        zenGame = Self.makeZenGame()
        tipsSeen = Set(defaults.stringArray(forKey: Key.tipsSeen) ?? [])
        // Players already past valley 1 never need the first run.
        let tutorialDone = defaults.bool(forKey: Key.tutorialDone)
        if !tutorialDone && valley >= 2 { defaults.set(true, forKey: Key.tutorialDone) }
        if !tutorialDone && valley == 1 && mode == .coins {
            // Open on the glimpse, so the HUD never shows before the first run begins.
            needsFirstRun = true
            coinGame = Tutorial.makeGame()
            isShowingValleyIntro = false
            coachStep = .glimpse
            glimpsePhase = .fogged
            glimpseBoard = Tutorial.glimpse()
        }
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
        case (.coins, .outOfTiles): isViewingValley ? nil : .valleyDone
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

    /// The board as drawn: a finished valley that's been looked over shows everything; the run itself never changes.
    var displayBoard: Board {
        if coachStep == .glimpse, let glimpseBoard, let glimpsePhase, glimpsePhase != .folding {
            return glimpsePhase == .fogged ? glimpseBoard : glimpseBoard.lit()
        }
        return mode == .coins && hasRevealedValley && game.outcome == .outOfTiles ? game.board.lit() : game.board
    }

    /// The quest chips: every quest going, plus ones that just completed or closed off, in the order they began.
    var questChips: [Quest] {
        game.quests.filter { $0.status == .active || endedQuestIDs.contains($0.id) }
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
        // A tap during the glimpse skips ahead to the first tile; one at the hand-off lets the player go.
        if coachStep == .glimpse {
            foldGlimpse()
            return
        }
        if coachStep == .handOff { finishCoach() }
        if isAimingDynamite {
            blast(hex)
            return
        }
        guard overlay == nil, let tile = game.current else { return }
        if isCoachingATile, let coachSpot, hex != coachSpot {
            nudge()
            return
        }
        guard game.board.openSlots.contains(hex) else { return }
        dismissTip()
        if hex == selectedSlot, isCoachingATile {
            // A coached tile turns straight to the way the lesson wants it, and no further.
            guard turnToCoachedRotation() else {
                nudge()
                return
            }
        } else if hex == selectedSlot {
            let steps = (1...6).first { game.board.canPlace(tile.rotatedClockwise($0), at: hex) } ?? 1
            turn(steps)
        } else {
            selectedSlot = hex
            // The turning lesson shows the tile as dealt, so the player turns it themselves.
            if coachStep != .tile(.turn), let steps = game.board.bestRotation(for: tile, at: hex), steps != 0 {
                turn(steps)
            }
        }
        haptics.select()
        scene.sync()
        if coachStep == .tile(.turn), !canPlace { scene.wiggleGhost() }
    }

    func rotate() {
        guard overlay == nil, game.current != nil else { return }
        if isCoachingATile {
            guard selectedSlot != nil, turnToCoachedRotation() else {
                nudge()
                return
            }
        } else {
            dismissTip()
            turn(1)
        }
        haptics.select()
        scene.sync()
    }

    func place() {
        // A coached tile goes where, and the way round, the lesson says.
        if isCoachingATile, selectedSlot != coachSpot || game.current != coachTile {
            nudge()
            return
        }
        let before = game
        guard overlay == nil, let slot = selectedSlot, let result = game.placeCurrent(at: slot) else {
            haptics.warn()
            return
        }
        dismissTip()
        resetSelection()
        advanceCoach()
        if result.tilesAwarded > 0 { showTileGain(result.tilesAwarded) }
        showQuestEndings(result.completedQuests + result.failedQuests)
        if mode == .coins {
            undoPoint = UndoPoint(game: before, coins: result.coins)
            var earned = result.coins
            addCoins(result.coins)
            // Bank a finished valley right away, so quitting on the end card never loses it.
            if !before.hasFinishedStack && game.hasFinishedStack {
                addCoins(CoinEconomy.valleyBonus)
                earned += CoinEconomy.valleyBonus
                defaults.set(valley + 1, forKey: Key.valley)
            }
            if earned > 0 { undoPoint?.flightID = flyCoins(earned, from: result.hex) }
        }
        if mode == .levels, game.outcome == .won { defaults.set(level + 1, forKey: Key.level) }
        if mode == .zen, game.outcome == .outOfTiles { recordZenScore() }
        announce(result, fogReturned: before.board.isLit)
        scene.sync(placement: result)
        if mode == .coins { offerTipAfterPlacing() }
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
            spend(CoinEconomy.continuePrice)
            undoPoint = nil
            // The valley isn't finished any more: the fog comes back, and the longer valley can be saved again.
            resetValleyViewing()
        }
        game.continueRun()
        haptics.success()
        scene.sync()
    }

    /// Ends a valley that ran out of room on its bought tiles, as done.
    func finishValley() {
        guard mode == .coins, game.hasFinishedStack, game.outcome == .outOfRoom else { return }
        coinGame.finishValley()
        undoPoint = nil
        resetSelection()
        haptics.success()
        scene.sync()
    }

    // MARK: - Viewing and saving a finished valley

    /// Puts the end card away and lifts the fog off the whole finished valley.
    func viewValley() {
        guard overlay == .valleyDone else { return }
        dismissTip()
        showTip(.save)
        isViewingValley = true
        hasRevealedValley = true
        needsValleyFit = true
        resetSelection()
        clearFeedback()
        haptics.select()
        scene.sync()
        scene.fitValley()
    }

    /// Called as the view bar settles: frames the valley above it the first time only,
    /// so a later change in the bar's height never undoes the player's pan and zoom.
    func fitValleyAboveViewingBar() {
        guard needsValleyFit else { return }
        needsValleyFit = false
        scene.fitValley()
    }

    /// Back to the end card. The valley stays in full view behind it.
    func doneViewing() {
        guard isViewingValley else { return }
        dismissTip()
        isViewingValley = false
        scene.sync()
    }

    func saveValleyToGallery() {
        guard isViewingValley, !isValleySaved, !isSavingValley else { return }
        dismissTip()
        let token = UUID()
        saveToken = token
        isSavingValley = true
        let picture = ValleyPicture(board: game.board)
        let (number, coins) = (valley, game.coins)
        Task {
            let entry = await gallery.add(picture, valley: number, coins: coins)
            // The player may have moved on while it saved; the entry is kept either way.
            guard saveToken == token else { return }
            isSavingValley = false
            if entry == nil {
                haptics.warn()
                show("Couldn't save this valley", symbol: "exclamationmark.triangle")
            } else {
                savedEntryID = entry?.id
                haptics.success()
                show("Saved to your gallery", symbol: "photo.on.rectangle.angled")
            }
        }
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
            return wallet >= powerUp.price && (board.revealedMountains != board.mountains || board.revealedLakes != board.lakes)
        }
    }

    /// Dynamite is on offer, but no mountain in view can be blasted: the ones found so far
    /// are all on the valley's edge (or none are found yet), whatever the wallet holds.
    var hasNoDynamiteTarget: Bool {
        mode == .coins && (overlay == nil || overlay == .valleyStuck) && !isAimingDynamite
            && isUnlocked(.dynamite) && game.current != nil && game.board.clearableMountains.isEmpty
    }

    /// Any power-up that could get an out-of-room valley going again.
    var canRescue: Bool {
        [PowerUp.swap, .undo, .wildcard, .dynamite].contains(where: canUse)
    }

    func use(_ powerUp: PowerUp) {
        dismissTip()
        if powerUp == .dynamite && hasNoDynamiteTarget {
            haptics.warn()
            show("Only mountains inside the valley can be blasted, not its edge", symbol: PowerUp.dynamite.symbolName, seconds: 3)
            return
        }
        guard canUse(powerUp) else {
            haptics.warn()
            return
        }
        // Undo also takes back the coins the placement earned. Coins still in the air never land,
        // so the chip's "−N" is the price plus only the coins that already reached it.
        var takenBack = 0
        var shownTakenBack = 0
        switch powerUp {
        case .undo:
            guard let undoPoint else { return }
            coinGame = undoPoint.game
            takenBack = undoPoint.coins
            let stillFlying = undoPoint.flightID.map(stopFlight) ?? 0
            shownTakenBack = takenBack - stillFlying
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
            show("Lantern lit until your next tile", symbol: powerUp.symbolName)
        }
        spend(powerUp.price + takenBack, shown: powerUp.price + shownTakenBack)
        undoPoint = nil
        resetSelection()
        recoachAfterPowerUp()
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
        spend(PowerUp.dynamite.price)
        isAimingDynamite = false
        undoPoint = nil
        recoachAfterPowerUp()
        haptics.success()
        scene.sync(blasted: hex)
    }

    // MARK: - Valleys

    /// Starts over as a brand-new player: Coin mode, valley 1, the starting wallet,
    /// level 1 and no Zen best, as if the game were just installed. The gallery stays.
    func resetPlayer() {
        Key.all.forEach(defaults.removeObject)
        mode = .coins
        valley = 1
        wallet = CoinEconomy.startingWallet
        stopAllFlights()
        tipsSeen = []
        tip = nil
        endCoach()
        coinGame = Tutorial.makeGame()
        isShowingValleyIntro = false
        resetValleyViewing()
        level = 1
        levelGame = ValleyGame(level: LevelDesigner.level(1))
        isShowingLevelIntro = true
        zenBest = 0
        isNewZenBest = false
        zenGame = Self.makeZenGame()
        isAimingDynamite = false
        undoPoint = nil
        resetSelection()
        clearFeedback()
        haptics.success()
        startGlimpse(animated: true)
    }

    func fitValley() {
        scene.fitValley()
    }

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
        if coachStep != nil { finishCoach() }
        valley = number
        let saved = defaults.integer(forKey: Key.valley)
        defaults.set(canRewindProgress ? number : max(number, saved), forKey: Key.valley)
        coinGame = Self.makeCoinGame(valley: number)
        isShowingValleyIntro = true
        isAimingDynamite = false
        resetValleyViewing()
        undoPoint = nil
        resetSelection()
        clearFeedback()
        scene.sync()
        scene.recenter()
    }

    private static func makeCoinGame(valley: Int) -> ValleyGame {
        var rules = Rules.coins(valley: valley)
        #if DEBUG
        // Launch with `-startingTiles 3` to reach the end of a valley quickly.
        let startingTiles = UserDefaults.standard.integer(forKey: "startingTiles")
        if startingTiles > 0 { rules.startingTiles = startingTiles }
        #endif
        return ValleyGame(seed: .random(in: .min ... .max), rules: rules)
    }

    private func addCoins(_ amount: Int) {
        wallet = max(0, wallet + amount)
        defaults.set(wallet, forKey: Key.wallet)
    }

    /// Takes coins out of the wallet; a red "−N" drops out of the chip as its total rolls down.
    /// `shown` is how far the chip's total drops, when that differs from what the wallet loses.
    private func spend(_ amount: Int, shown: Int? = nil) {
        addCoins(-amount)
        syncWalletShown()
        showCoinChange(-(shown ?? amount))
    }

    /// The chip's total: the wallet less the coins still in the air.
    private func syncWalletShown() {
        walletShown = max(0, wallet - coinsInFlight)
    }

    /// Records where the chip's coin icon sits, so flying coins land on it.
    func coinChipMoved(to point: CGPoint) {
        coinTarget = point
    }

    /// Sends one coin per coin earned from the placed tile to the chip. The chip's total
    /// counts up as they land, and "+N" rises into it. Returns the flight's id.
    private func flyCoins(_ amount: Int, from hex: Hex) -> Int {
        feedbackCount += 1
        let flight = CoinFlight(id: feedbackCount, count: amount, from: scene.screenPoint(of: hex) ?? coinTarget)
        coinFlights.append(flight)
        coinsInFlight += amount
        flightRemaining[flight.id] = amount
        syncWalletShown()
        flightTasks[flight.id] = Task {
            try? await Task.sleep(for: .seconds(CoinFlight.travel))
            guard !Task.isCancelled else { return }
            showCoinChange(amount)
            for _ in 1...amount {
                guard !Task.isCancelled, let remaining = flightRemaining[flight.id], remaining > 0 else { return }
                flightRemaining[flight.id] = remaining - 1
                coinsInFlight -= 1
                syncWalletShown()
                coinLandings += 1
                try? await Task.sleep(for: .seconds(flight.stagger))
            }
            guard !Task.isCancelled else { return }
            finishFlight(flight.id)
        }
        return flight.id
    }

    /// Stops a flight mid-air: its coins vanish and never reach the chip. Returns how many were still flying.
    @discardableResult
    private func stopFlight(_ id: Int) -> Int {
        flightTasks[id]?.cancel()
        let remaining = flightRemaining[id] ?? 0
        coinsInFlight -= remaining
        finishFlight(id)
        return remaining
    }

    private func finishFlight(_ id: Int) {
        flightTasks[id] = nil
        flightRemaining[id] = nil
        coinFlights.removeAll { $0.id == id }
        syncWalletShown()
    }

    /// Stops every flight; the chip shows the whole wallet at once.
    private func stopAllFlights() {
        flightTasks.values.forEach { $0.cancel() }
        flightTasks = [:]
        flightRemaining = [:]
        coinFlights = []
        coinsInFlight = 0
        syncWalletShown()
    }

    // MARK: - First run

    /// Which HUD parts are on screen: all of them, except during the first run, which brings them in step by step.
    var hud: HUDParts {
        guard let coachStep, !isReplayingCoach else { return .all }
        var parts = HUDParts(menu: false, tilesLeft: false, fit: false, quests: false, rotate: false, next: false, powerUps: false)
        switch coachStep {
        case .glimpse:
            parts.topBar = false
            parts.tray = false
        case .tile(.place):
            break
        case .tile(.turn):
            parts.rotate = true
        case .tile(.quest):
            parts.rotate = true
            parts.quests = true
        case .tile(.choice):
            parts.rotate = true
            parts.quests = true
            parts.next = true
        case .handOff:
            return .all
        }
        return parts
    }

    /// Coaching one of the first tiles at a fixed spot (not the player's own choice).
    private var isCoachingATile: Bool {
        if case .tile(let step) = coachStep, step != .choice { return coachSpot != nil }
        return false
    }

    /// What the coach says now. A one-time Swap tip speaks in the same bubble.
    var coachLine: String? {
        if tip == .swap { return Tip.swap.line }
        guard let coachStep else { return nil }
        switch coachStep {
        case .glimpse:
            return glimpsePhase == .framed ? "Finish it, and keep the picture." : "Build a valley like this, one tile at a time."
        case .tile(.place):
            if selectedSlot == nil { return "Tap the glowing spot." }
            return isCoachedTileReady ? "Stitches mean the sides match. Tap Place." : "Tap the tile to turn it."
        case .tile(.turn):
            if selectedSlot == nil { return "Each match pays a coin. Tap the next glowing spot." }
            return isCoachedTileReady ? "Now they match. Tap Place." : "The sides don't match. Tap the tile to turn it."
        case .tile(.quest):
            if selectedSlot != nil && !isCoachedTileReady { return "Tap the tile to turn it." }
            if let quest = game.activeQuests.first {
                let terrain = quest.terrain.displayName.lowercased()
                let tiles = quest.remaining == 1 ? "tile" : "tiles"
                return "Quest: add \(quest.remaining) more \(terrain) \(tiles) here for bonus coins."
            }
            return "Grow a quest's region to earn bonus coins."
        case .tile(.choice):
            return "Your turn. Put it anywhere that glows."
        case .handOff:
            if isReplayingCoach { return "That's the basics. Match sides, finish quests, and find what's hidden." }
            let lakes = game.rules.lakeCount
            return "\(game.tilesLeft) tiles to go. Can you find \(lakes) hidden \(lakes == 1 ? "lake" : "lakes")?"
        }
    }

    /// Which of the four coached tiles is in hand, for the bubble's dots (first run only).
    var coachStepIndex: Int? {
        guard !isReplayingCoach, case .tile(let step) = coachStep else { return nil }
        return step.rawValue
    }

    /// Where the coach's hand points on the board, if anywhere: the spot to tap, or the ghost to turn.
    var coachHandHex: Hex? {
        guard let coachSpot else { return nil }
        switch coachStep {
        case .tile(.place): return selectedSlot == nil ? coachSpot : nil
        case .tile(.turn): return selectedSlot == nil || !isCoachedTileReady ? coachSpot : nil
        default: return nil
        }
    }

    /// The coached tile sits on its spot, turned the way the lesson wants it.
    private var isCoachedTileReady: Bool {
        selectedSlot == coachSpot && game.current == coachTile && canPlace
    }

    /// Place wears the coach's ring once the coached tile is ready.
    var coachMarksPlace: Bool {
        isCoachingATile && isCoachedTileReady
    }

    /// A big coin payout is on its way to the chip; the coach's bubble steps aside.
    var isBigPayoutInFlight: Bool {
        coinFlights.contains { $0.count >= 5 }
    }

    /// The hand points at Place on the first two coached tiles.
    var coachHandOnPlace: Bool {
        coachMarksPlace && (coachStep == .tile(.place) || coachStep == .tile(.turn))
    }

    /// Starts a new player's first run once the board is on screen.
    func beginFirstRunIfNeeded() {
        guard needsFirstRun else { return }
        needsFirstRun = false
        startGlimpse(animated: false)
    }

    /// How to Play is on offer: a Coin valley in play, nothing else on screen or in hand.
    var canReplayCoach: Bool {
        mode == .coins && coachStep == nil && overlay == nil && !isAimingDynamite && game.current != nil
    }

    /// "How to Play": the coach walks through the next tiles of the current valley, with the whole HUD.
    func replayCoach() {
        guard canReplayCoach else { return }
        isReplayingCoach = true
        dismissTip()
        resetSelection()
        enterCoachStep(.tile(.place))
        scene.sync()
    }

    /// Skip: the first run ends and the whole game is there.
    func skipCoach() {
        if coachStep == .glimpse { scene.recenter() }
        finishCoach()
    }

    /// The first run is over (or a replay is): the whole HUD, and it won't start again.
    func finishCoach() {
        guard coachStep != nil else { return }
        if !isReplayingCoach { defaults.set(true, forKey: Key.tutorialDone) }
        endCoach()
        scene.sync()
    }

    private func endCoach() {
        glimpseToken += 1
        coachStep = nil
        coachSpot = nil
        coachTile = nil
        isReplayingCoach = false
        glimpsePhase = nil
        glimpseFrame = nil
        glimpseBoard = nil
    }

    /// The glimpse: the finished valley under fog, the fog lifting, a photo frame, then it folds away.
    /// On a first launch it opens already framed; after Reset Player the camera glides to it.
    private func startGlimpse(animated: Bool) {
        glimpseToken += 1
        let token = glimpseToken
        coachStep = .glimpse
        glimpseBoard = Tutorial.glimpse()
        glimpsePhase = .fogged
        resetSelection()
        // The HUD is hidden, so the valley is framed on the whole screen.
        scene.hudTop = 0
        scene.hudBottom = 0
        scene.sync()
        scene.fitValley(animated: animated)
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard glimpseToken == token else { return }
            glimpsePhase = .lit
            scene.sync()
            scene.fitValley()
            try? await Task.sleep(for: .seconds(1.4))
            guard glimpseToken == token else { return }
            glimpseFrame = scene.screenRect(of: displayBoard.tiles.keys)
            glimpsePhase = .framed
            try? await Task.sleep(for: .seconds(1.6))
            guard glimpseToken == token else { return }
            foldGlimpse()
        }
    }

    /// The glimpse's valley folds away, outer ring first, down to the one tile the player starts from.
    private func foldGlimpse() {
        guard coachStep == .glimpse else { return }
        glimpseToken += 1
        let token = glimpseToken
        glimpsePhase = .folding
        glimpseFrame = nil
        scene.sync()
        scene.recenter()
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            guard glimpseToken == token else { return }
            glimpsePhase = nil
            glimpseBoard = nil
            enterCoachStep(.tile(.place))
            scene.sync()
        }
    }

    /// Moves to the coach step after a placement, and ends the coach if the valley is over.
    private func advanceCoach() {
        guard let coachStep else { return }
        if game.isOver {
            // The caller draws the placement next, so no redraw here.
            if !isReplayingCoach { defaults.set(true, forKey: Key.tutorialDone) }
            endCoach()
            return
        }
        switch coachStep {
        case .tile(.place): enterCoachStep(.tile(.turn))
        case .tile(.turn): enterCoachStep(.tile(isReplayingCoach ? .choice : .quest))
        case .tile(.quest): enterCoachStep(.tile(.choice))
        case .tile(.choice): enterCoachStep(.handOff)
        case .glimpse, .handOff: break
        }
    }

    /// Enters `step`, fixing the spot to coach. A coached tile with nothing to show (on a replay,
    /// a valley may have no spot that teaches turning) moves on to the next step.
    private func enterCoachStep(_ step: CoachStep) {
        var step = step
        coachSpot = nil
        coachTile = nil
        while case .tile(let tileStep) = step, tileStep != .choice {
            if let spot = Tutorial.spot(for: tileStep, in: game), let tile = game.current {
                coachSpot = spot
                let turns = tileStep == .turn
                    ? Tutorial.firstFittingTurn(for: tile, at: spot, on: game.board)
                    : game.board.bestRotation(for: tile, at: spot)
                coachTile = tile.rotatedClockwise(turns ?? 0)
                break
            }
            step = switch tileStep {
            case .place: .tile(.turn)
            case .turn: .tile(isReplayingCoach ? .choice : .quest)
            case .quest, .choice: .tile(.choice)
            }
        }
        coachStep = step
    }

    /// Turns the tile in hand to the coached rotation. False when it's already there.
    private func turnToCoachedRotation() -> Bool {
        guard let coachTile, let current = game.current, current != coachTile,
              let steps = (1...5).first(where: { current.rotatedClockwise($0) == coachTile }) else { return false }
        turn(steps)
        return true
    }

    /// A power-up changed the run mid-coach (How to Play): coach the new tile afresh, or stop if the valley can't go on.
    private func recoachAfterPowerUp() {
        guard let coachStep else { return }
        if game.isOver || game.isStuck {
            endCoach()
        } else if case .tile(let step) = coachStep {
            enterCoachStep(.tile(step))
        }
    }

    /// A tap somewhere other than where the coach points: the spot pops and the bubble shakes.
    private func nudge() {
        coachNudges += 1
        haptics.select()
        scene.nudgeSpotlight()
    }

    // MARK: - Tips

    /// After a placement, a one-time tip if the moment calls for one.
    private func offerTipAfterPlacing() {
        guard coachStep == nil else { return }
        switch game.outcome {
        case .outOfTiles:
            showTip(.viewValley)
        case .outOfRoom:
            showTip(.noRoom)
        case .playing:
            guard let current = game.current, canUse(.swap) else { return }
            let fits = game.board.openSlots.filter { game.board.bestRotation(for: current, at: $0) != nil }.count
            if fits <= 2 { showTip(.swap) }
        case .won:
            break
        }
    }

    /// Shows `tip` the first time only.
    private func showTip(_ newTip: Tip) {
        guard coachStep == nil, !tipsSeen.contains(newTip.rawValue) else { return }
        tipsSeen.insert(newTip.rawValue)
        defaults.set(Array(tipsSeen).sorted(), forKey: Key.tipsSeen)
        tip = newTip
    }

    private func dismissTip() {
        tip = nil
    }

    // MARK: - Modes and levels

    func switchMode(to newMode: GameMode) {
        guard newMode != mode else { return }
        if coachStep != nil { finishCoach() }
        dismissTip()
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Key.mode)
        isAimingDynamite = false
        isViewingValley = false
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

    func debugAddCoins(_ amount: Int) {
        addCoins(amount)
        syncWalletShown()
        showCoinChange(amount)
    }

    func debugJumpValley(to number: Int) {
        startValley(max(1, number), canRewindProgress: true)
    }

    func debugJump(to number: Int) {
        startLevel(min(max(1, number), LevelDesigner.levelCount), canRewindProgress: true)
    }

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

    private func resetValleyViewing() {
        isViewingValley = false
        hasRevealedValley = false
        savedEntryID = nil
        isSavingValley = false
        saveToken = UUID()
    }

    private static func makeZenGame() -> ValleyGame {
        var rules = Rules.zen
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
        coinChange = nil
        stopAllFlights()
        endedQuestIDs = []
        tip = nil
    }

    /// Keeps the chips of quests that just ended on screen, marked done or closed off, then lets them go.
    private func showQuestEndings(_ quests: [Quest]) {
        let ids = Set(quests.map(\.id))
        guard !ids.isEmpty else { return }
        endedQuestIDs.formUnion(ids)
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            endedQuestIDs.subtract(ids)
        }
    }

    private func turn(_ steps: Int) {
        // A wildcard looks and plays the same every way round, so it doesn't turn.
        guard game.current?.isWild == false else { return }
        game.rotateCurrent(clockwiseSteps: steps)
        rotationTurns += steps
    }

    private func announce(_ result: PlacementResult, fogReturned: Bool) {
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
                : "+\(game.rules.questCoins(for: quest.growth)) coins"
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
        } else if let quest = result.startedQuests.first, coachStep == nil || isReplayingCoach {
            show("New quest: \(quest.terrain.displayName) to \(quest.target)", symbol: quest.terrain.symbolName)
        } else if fogReturned {
            show("The fog rolls back in", symbol: "cloud.fog.fill")
        }
    }

    private func show(_ message: String, symbol: String, seconds: Double = 2) {
        feedbackCount += 1
        let toast = Toast(id: feedbackCount, message: message, symbolName: symbol)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(seconds))
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

    private func showCoinChange(_ amount: Int) {
        feedbackCount += 1
        let change = Gain(id: feedbackCount, amount: amount)
        coinChange = change
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if self.coinChange?.id == change.id { self.coinChange = nil }
        }
    }
}

struct Haptics {
    func select() { UISelectionFeedbackGenerator().selectionChanged() }
    func place() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    func warn() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
