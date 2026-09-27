# Patchwork Valley

A calm iOS puzzle game. Players place hex landscape tiles and match edges. **Levels** (the main mode) give a fixed stack of tiles and region goals to meet. **Zen** is one endless-feeling valley where quests earn more tiles. Game design lives in [docs/DESIGN.md](docs/DESIGN.md), and other game concepts live in [docs/CONCEPTS.md](docs/CONCEPTS.md).

## Layout

- `ValleyCore/` is a Swift package that holds every game rule: the hex grid, tiles, the seeded tile generator, the board, scoring, quests, goals and run state (`ValleyGame`), plus level generation (`LevelDesigner`) and the bot that makes levels fair (`GreedyBot`). It is pure Swift with no SpriteKit, SwiftUI or UIKit imports, and it builds for iOS and macOS.
- Level generation must stay deterministic: the same level number always builds the same level. The tile stream never depends on player actions, and the bot sorts slots before choosing, because `Set` order changes every launch.
- `PatchworkValley/` is the app: a SwiftUI HUD over a SpriteKit board.
  - `GameModel` is the `@Observable` owner of both modes' runs, the saved level number and Zen best, and the player's in-progress choice (selected slot, rotation). It calls `scene.sync` after every change.
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

In Debug builds, the launch argument `-startingTiles N` starts Zen runs with N tiles, and the menu has a Debug section for jumping between levels.

## Rules for changes

- Game rules belong in `ValleyCore` and come with tests. The app never computes rules itself.
- Every visible state change animates, whether through a SwiftUI transition or `.animation` or an `SKAction`. Nothing snaps.
- UI sizes use `@ScaledMetric` or semantic fonts, never hard-coded values. Board world units are exempt because the camera zooms.
- The project uses Swift 6 and iOS 26. The app target's default actor isolation is `MainActor`.
- SpriteKit has had no new API since iOS 15. Keep it replaceable: it renders and handles gestures, nothing more. Avoid GameplayKit, which breaks under Swift 6 strict concurrency.
- The board view ignores sibling order for speed, so every SpriteKit node that must draw above a sibling needs an explicit `zPosition`. That includes shapes rendered into tile textures.
