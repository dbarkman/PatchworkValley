import Dispatch
import Synchronization
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
/// and the printed spots and coins into `TutorialTests`. Very few seeds qualify (the first is past
/// 1,100,000), so it searches millions, a block at a time across every core, and prints its progress
/// after each block. A release build is quickest, about a minute:
/// `swift test -c release -Xswiftc -enable-testing --filter findTutorialSeed`.
@Test(.disabled("Design tool: run by hand to pick the tutorial's seed"))
func findTutorialSeed() {
    let attempts: UInt64 = 50_000_000
    let block: UInt64 = 100_000
    var nearest: (seed: UInt64, met: Int)?
    var start: UInt64 = 1
    while start <= attempts {
        let first = start
        let count = min(block, attempts - first + 1)
        // A block is searched in parallel; the lowest passing seed of the first block with one wins.
        let results = Mutex<[(seed: UInt64, audit: Tutorial.Audit)]>([])
        DispatchQueue.concurrentPerform(iterations: Int(count)) { index in
            let seed = first + UInt64(index)
            let audit = Tutorial.audit(seed: seed, stopAtFirst: true)
            if audit.met.count > 1 { results.withLock { $0.append((seed, audit)) } }
        }
        let found = results.withLock { $0 }.sorted { $0.seed < $1.seed }
        if let pass = found.first(where: { $0.audit.passes }) {
            let spots = Tutorial.Step.allCases.compactMap { step in
                pass.audit.spots[step].map { "\(step) \($0) (\(pass.audit.coins[step] ?? 0) coins)" }
            }
            print("Tutorial: seed \(pass.seed) (searched 1...\(pass.seed)); spots \(spots.joined(separator: ", "))")
            return
        }
        for candidate in found where candidate.audit.met.count > (nearest?.met ?? -1) {
            nearest = (candidate.seed, candidate.audit.met.count)
        }
        start += count
        print("Tutorial: searched 1...\(start - 1); closest so far \(nearest.map { "seed \($0.seed), \($0.met) met" } ?? "none")")
    }
    print("Tutorial: no seed in 1...\(attempts) meets every requirement; closest is \(nearest.map { "seed \($0.seed), \($0.met) met" } ?? "none")")
}
