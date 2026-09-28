import SwiftUI
import ValleyCore

/// Where the first-run coach is. It opens with a glimpse of a finished valley, coaches the
/// first tiles of valley 1 (`Tutorial.Step`), then hands the whole game over.
enum CoachStep: Equatable {
    /// A finished valley lifts out of the fog, is framed like a photo, then folds away to one tile.
    case glimpse
    /// A coached tile: place, turn, quest, then the player's own choice.
    case tile(Tutorial.Step)
    /// Everything slides in, with one last line and "Let's go".
    case handOff
}

/// The glimpse's beats: the finished valley under fog, lit, framed as a picture, then folding away.
enum GlimpsePhase: Equatable {
    case fogged, lit, framed, folding
}

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
        case .swap: "Tricky tile? Your coins can Swap it for another."
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
    /// Which of the four coached tiles this is (0-based), or nil when there are no dots to show.
    var stepIndex: Int?
    var nudges = 0
    var onSkip: (() -> Void)?
    var onGo: (() -> Void)?
    @ScaledMetric private var dotSize: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(line)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            if stepIndex != nil || onSkip != nil || onGo != nil {
                HStack(spacing: 6) {
                    if let stepIndex {
                        ForEach(0..<Tutorial.Step.allCases.count, id: \.self) { index in
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
                        Button("Let's go", action: onGo)
                            .buttonStyle(.borderedProminent)
                    }
                }
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

/// The glimpse's photo frame: a white border dropped around the finished valley, tilted a little,
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
