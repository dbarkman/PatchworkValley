import SwiftUI
import ValleyCore

/// Where the coach is. The first run opens with a five-page intro, coaches the first tiles of
/// valley 1 (`Tutorial.Step`), has the player try Swap, then hands the game over.
/// Valleys 2–5 each open with a demo of the power-up they bring.
enum CoachStep: Equatable {
    /// The intro, one page at a time (0 to `introPages - 1`), each waiting for Next: a valley in
    /// fog, tiles stitching together, a quest paying out, the power-ups, and the finished valley to keep.
    case intro(Int)
    /// A coached tile: place, a quest tile, turn, finish the quest, then the player's own choice.
    case tile(Tutorial.Step)
    /// Coins buy power-ups: the player tries Swap, free this once.
    case trySwap
    /// Everything slides in, with one last line and "Let's go".
    case handOff
    /// A power-up's first-time demo, on its own little valley.
    case demo(PowerUp, DemoBeat)
}

/// The beats of a power-up demo.
enum DemoBeat: Equatable {
    /// Undo: place a tile first, to have something to take back.
    case place
    /// Dynamite: the coach places a tile for the player, and a mountain comes out of the fog.
    case autoPlace
    /// Tap the power-up, free this once.
    case use
    /// Dynamite: tap the glowing mountain.
    case aim
    /// Wildcard: put the wild tile anywhere.
    case placeWild
    /// The price from now on, then Continue to a fresh valley.
    case done
}

/// How the intro shows its finished valley: under fog, lit, framed as a picture, or folding away.
enum GlimpsePhase: Equatable {
    case fogged, lit, framed, folding
}

/// The intro's pages.
let introPages = 5

/// Which parts of the HUD are on screen. The first run brings them in one at a time.
struct HUDParts: Equatable {
    var topBar = true
    var menu = true
    var tilesLeft = true
    var fit = true
    var quests = true
    var tray = true
    var rotate = true
    var next = true
    var powerUps = true

    static let all = HUDParts()
}

/// One-time tips after the coached tiles, each shown once and gone with the player's next action.
enum Tip: String, CaseIterable {
    /// A tile that fits in two spots or fewer.
    case swap
    /// The first time a tile fits nowhere.
    case noRoom
    /// The first finished valley.
    case viewValley
    /// The first look over a finished valley.
    case save

    var line: String {
        switch self {
        case .swap: "Tricky tile? Spend rewards to Swap it for another."
        case .noRoom: "It happens! A power-up can rescue this tile."
        case .viewValley: "Lift the fog and see what you built."
        case .save: "Save it to keep the picture."
        }
    }
}

/// The coach's line above the tile tray, with step dots and Skip, or "Let's go" at the end.
/// It gives a little shake when the player taps somewhere else.
struct CoachBubble: View {
    let line: String
    /// Which page or coached tile this is (0-based), or nil when there are no dots to show.
    var stepIndex: Int?
    var dotCount = Tutorial.Step.allCases.count
    var nudges = 0
    var onSkip: (() -> Void)?
    var onGo: (() -> Void)?
    var goTitle = "Let's go"
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric private var dotSize: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // At the largest text sizes the line scrolls, so the tray below never leaves the screen.
            ViewThatFits(in: .vertical) {
                lineText
                ScrollView { lineText }
            }
            if stepIndex != nil || onSkip != nil || onGo != nil {
                HStack(spacing: 6) {
                    // At accessibility text sizes the dots make way for the buttons.
                    if let stepIndex, !dynamicTypeSize.isAccessibilitySize {
                        ForEach(0..<dotCount, id: \.self) { index in
                            Circle()
                                .fill(index <= stepIndex ? Color.accentColor : Color.secondary.opacity(0.35))
                                .frame(width: dotSize, height: dotSize)
                        }
                        .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                    if let onSkip {
                        Button("Skip", action: onSkip)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    if let onGo {
                        Button(goTitle, action: onGo)
                            .buttonStyle(.borderedProminent)
                    }
                }
                // The buttons stop growing at the first accessibility size, so "Next" never breaks mid-word.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .keyframeAnimator(initialValue: 0.0, trigger: nudges) { content, shift in
            content.offset(x: shift)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-8, duration: 0.06)
                CubicKeyframe(8, duration: 0.08)
                CubicKeyframe(-4, duration: 0.07)
                CubicKeyframe(0, duration: 0.07)
            }
        }
        .animation(.snappy, value: line)
        .onChange(of: line, initial: true) { _, newLine in
            AccessibilityNotification.Announcement(newLine).post()
        }
    }

    private var lineText: some View {
        Text(line)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
    }
}

extension View {
    /// Draws the coach's pulsing ring around a button, with a pointing hand when `hand` is set.
    func coachMark(_ isActive: Bool, hand: Bool = false) -> some View {
        modifier(CoachMark(isActive: isActive, showsHand: hand))
    }
}

private struct CoachMark: ViewModifier {
    let isActive: Bool
    let showsHand: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    Capsule()
                        .strokeBorder(Color.yellow, lineWidth: 3)
                        .padding(-5)
                        .phaseAnimator([false, true]) { ring, isOut in
                            ring
                                .scaleEffect(isOut && !reduceMotion ? 1.08 : 1)
                                .opacity(isOut && !reduceMotion ? 0.45 : 1)
                        } animation: { _ in .easeInOut(duration: 0.7) }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isActive && showsHand {
                    CoachHandView()
                        .offset(x: 14, y: 22)
                        .allowsHitTesting(false)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy, value: isActive)
    }
}

/// A pointing hand that bobs toward whatever it points at.
struct CoachHandView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 34

    var body: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: size))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
            .phaseAnimator([false, true]) { hand, isIn in
                hand.offset(x: isIn && !reduceMotion ? -5 : 0, y: isIn && !reduceMotion ? -6 : 0)
            } animation: { _ in .easeInOut(duration: 0.5) }
            .accessibilityHidden(true)
    }
}

/// The intro's photo frame: a white border dropped around the finished valley, tilted a little,
/// with a "keep the picture" badge in its corner.
struct GlimpseFrameLayer: View {
    let frame: CGRect?
    @ScaledMetric(relativeTo: .title) private var badgeSize: CGFloat = 30

    var body: some View {
        GeometryReader { screen in
            if let frame {
                // A little room around the valley, but never wider or taller than the screen.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white, lineWidth: 8)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    .frame(width: min(frame.width + 32, screen.size.width - 40),
                           height: min(frame.height + 32, screen.size.height - 120))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: badgeSize))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.accentColor, in: Circle())
                            .offset(x: 16, y: -16)
                    }
                    .rotationEffect(.degrees(-3))
                    .position(x: frame.midX, y: frame.midY)
                    .transition(.scale(scale: 1.15).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.snappy(duration: 0.45), value: frame)
    }
}

/// The intro's first page: soft fog drifting over a valley the player can only just make out.
struct IntroFog: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where each cloud sits, as fractions of the screen.
    private let clouds: [(x: CGFloat, y: CGFloat)] = [(0.2, 0.18), (0.8, 0.3), (0.35, 0.45), (0.75, 0.58), (0.25, 0.72), (0.65, 0.85)]

    var body: some View {
        GeometryReader { screen in
            ZStack {
                Color.white.opacity(0.28)
                ForEach(clouds.indices, id: \.self) { index in
                    Ellipse()
                        .fill(.white.opacity(0.6))
                        .frame(width: screen.size.width * 0.95, height: screen.size.height * 0.26)
                        .blur(radius: 36)
                        .position(x: screen.size.width * clouds[index].x, y: screen.size.height * clouds[index].y)
                        .phaseAnimator([false, true]) { cloud, isAcross in
                            cloud.offset(x: reduceMotion ? 0 : (isAcross ? 36 : -36) * (index.isMultiple(of: 2) ? 1 : -1))
                        } animation: { _ in .easeInOut(duration: 5 + Double(index)) }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The intro's power-ups page: each power-up and what it does, arriving one after another.
struct PowerUpShowcase: View {
    @State private var shown = 0
    @ScaledMetric(relativeTo: .title2) private var iconWidth: CGFloat = 34

    var body: some View {
        // At the largest text sizes the list scrolls rather than slipping under the bubble.
        ViewThatFits(in: .vertical) {
            card
            ScrollView { card }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(.horizontal, 8)
        .task {
            for count in 1...PowerUp.allCases.count {
                withAnimation(.snappy) { shown = count }
                try? await Task.sleep(for: .seconds(0.35))
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let powerUp = PowerUp.allCases[index]
        return HStack(spacing: 14) {
            Image(systemName: powerUp.symbolName)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: iconWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(powerUp.title)
                    .font(.headline)
                Text(powerUp.pitch)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(index < shown ? 1 : 0)
        .offset(x: index < shown ? 0 : -24)
        .accessibilityElement(children: .combine)
    }

    /// The rows are laid out one by one, with no ForEach: ViewThatFits can size its candidates off the
    /// main thread, where a main-actor ForEach closure would trap.
    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Power-ups")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            row(0)
            row(1)
            row(2)
            row(3)
            row(4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
