# Patchwork Valley

A calm iOS puzzle game. Players place hex landscape tiles and match edges. **Coins** (the main mode) deals numbered 36-tile valleys whose quests pay coins, spent on power-ups. **Levels** give a fixed stack of tiles and region goals to meet. **Zen** is one endless-feeling valley where quests earn more tiles. Game design lives in [docs/DESIGN.md](docs/DESIGN.md), and other game concepts live in [docs/CONCEPTS.md](docs/CONCEPTS.md).

## Layout

- `ValleyCore/` is a Swift package that holds every game rule: the hex grid, tiles, the seeded tile generator, the board, scoring, quests, goals and run state (`ValleyGame`), plus the designed levels (`LevelDesigner`), the bot that proves each level beatable (`GreedyBot`), Coin mode's crater generator (`Crater`), and its power-ups and prices (`CoinEconomy.swift`). The open plane (Levels, Zen) is `Board(starter:)`; a crater board adds mountains, lakes, fog (`revealedMountains`, `revealedLakes`) and the match rule. Power-ups that change the run (Swap, Wildcard) are `ValleyGame` methods; Undo is the app restoring a copy of the run, since `ValleyGame` is a value type. It is pure Swift with no SpriteKit, SwiftUI or UIKit imports, and it builds for iOS and macOS.
- Levels must stay deterministic: a level's seed always deals the same tiles. The tile stream never depends on player actions (every run deals its whole stack up front, and quests are added as tiles are shown), and the bot sorts slots before choosing, because `Set` order changes every launch. Tests fail if a rule change makes any level unbeatable for the bot; if that happens, re-pick seeds with the disabled `findLevelSeeds` test.
- `PatchworkValley/` is the app: a SwiftUI HUD over a SpriteKit board.
  - `GameModel` is the `@Observable` owner of all three modes' runs, the saved valley, wallet, level number and Zen best, and the player's in-progress choice (selected slot, rotation). It calls `scene.sync` after every change.
  - `ValleyScene` only renders. `sync(placement:)` reconciles its nodes with the model, and its gestures call into the model.
  - `TileDrawing` draws a tile as a list of paths. SpriteKit (board textures) and SwiftUI `Canvas` (tray previews) both use it, so tiles look the same everywhere.
  - `HexGeometry` converts pointy-top axial coordinates to points and back, in y-up space. Direction `i` points `60° × i` counter-clockwise from east.
- `PatchworkValley.xcodeproj` uses synchronized folders, so new files in `PatchworkValley/` join the target automatically.

## Build and test

```bash
cd ValleyCore && swift test
```

```bash
xcodebuild -project PatchworkValley.xcodeproj -scheme PatchworkValley -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

In Debug builds, the launch argument `-startingTiles N` starts Zen runs with N tiles, and the menu has a Debug section for jumping between valleys or levels and adding coins.

## Rules for changes

- Game rules belong in `ValleyCore` and come with tests. The app never computes rules itself.
- Every visible state change animates, whether through a SwiftUI transition or `.animation` or an `SKAction`. Nothing snaps.
- UI sizes use `@ScaledMetric` or semantic fonts, never hard-coded values. Board world units are exempt because the camera zooms.
- The project uses Swift 6 and iOS 26. The app target's default actor isolation is `MainActor`.
- SpriteKit has had no new API since iOS 15. Keep it replaceable: it renders and handles gestures, nothing more. Avoid GameplayKit, which breaks under Swift 6 strict concurrency.
- The board view ignores sibling order for speed, so every SpriteKit node that must draw above a sibling needs an explicit `zPosition`. That includes shapes rendered into tile textures.
