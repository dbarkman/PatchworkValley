import Testing
@testable import ValleyCore

/// A design tool, not a check: enable it to find tile orders (seeds) for new or
/// changed levels, then copy the printed seeds into `LevelDesigner.levels`.
/// Each range is how many tiles the bot should have left when it wins.
@Test(.disabled("Run by hand when designing levels"))
func findLevelSeeds() {
    let plans: [(tiles: Int, goals: [Goal], spare: ClosedRange<Int>)] = [
        (12, [Goal(terrain: .field, target: 6)], 3...5),
        (18, [Goal(terrain: .forest, target: 9)], 2...4),
        (24, [Goal(terrain: .forest, target: 6), Goal(terrain: .field, target: 6)], 1...3),
        (30, [Goal(terrain: .forest, target: 5), Goal(terrain: .field, target: 5), Goal(terrain: .village, target: 5)], 0...2),
        (36, [Goal(terrain: .forest, target: 6), Goal(terrain: .field, target: 5), Goal(terrain: .village, target: 4), Goal(terrain: .water, target: 3)], 0...1),
    ]
    for (index, plan) in plans.enumerated() {
        let seed = LevelDesigner.searchSeed(tiles: plan.tiles, goals: plan.goals, spare: plan.spare)
        print("Level \(index + 1): seed \(seed.map(String.init) ?? "none found")")
    }
}

/// A design tool, not a check: enable it to find the tutorial valley's seed, the first whose
/// opening meets every `Tutorial.Requirement`, then copy the printed seed into `Tutorial.seed`
/// and the printed spots into `TutorialTests`. Few seeds qualify (the first is past 120,000),
/// so it takes a few minutes.
@Test(.disabled("Design tool: run by hand to pick the tutorial's seed"))
func findTutorialSeed() {
    let attempts: UInt64 = 500_000
    var nearest: (seed: UInt64, met: Int)?
    for seed in 1...attempts {
        let audit = Tutorial.audit(seed: seed, stopAtFirst: true)
        if audit.passes {
            let spots = Tutorial.Step.allCases.compactMap { step in audit.spots[step].map { "\(step) \($0)" } }
            print("Tutorial: seed \(seed) (searched 1...\(seed)); spots \(spots.joined(separator: ", "))")
            return
        }
        if audit.met.count > (nearest?.met ?? -1) { nearest = (seed, audit.met.count) }
    }
    print("Tutorial: no seed in 1...\(attempts) meets every requirement; closest is \(nearest.map { "seed \($0.seed), \($0.met) met" } ?? "none")")
}
