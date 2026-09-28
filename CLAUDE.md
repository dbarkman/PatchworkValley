# Patchwork Valley

A calm iOS puzzle game. Players place hex landscape tiles and match edges. **Coins** (the main mode) deals numbered 36-tile valleys whose quests pay coins, spent on power-ups. **Levels** give a fixed stack of tiles and region goals to meet. **Zen** is one endless-feeling valley where quests earn more tiles. Game design lives in [docs/DESIGN.md](docs/DESIGN.md), and other game concepts live in [docs/CONCEPTS.md](docs/CONCEPTS.md).

## Layout

- `ValleyCore/` is a Swift package that holds every game rule: the hex grid, tiles, the seeded tile generator, the board, scoring, quests, goals and run state (`ValleyGame`), plus the designed levels (`LevelDesigner`), the bot that proves each level beatable (`GreedyBot`), Coin mode's crater generator (`Crater`) and its power-ups and prices (`CoinEconomy.swift`), Zen's hidden peaks and lakes (`Scatter`), and `ValleyPicture`, a finished valley as plain `Codable` data for the gallery. The open plane is `Board(starter:)` (Levels) or `Board(starter:scatter:)` (Zen, with peaks and lakes in fog); a crater board adds a rim, the floor and the match rule. Fog is `revealedMountains` and `revealedLakes`; `Board.lit()` is a copy with everything in view. Power-ups that change the run (Swap, Wildcard) are `ValleyGame` methods; Undo is the app restoring a copy of the run, since `ValleyGame` is a value type. It is pure Swift with no SpriteKit, SwiftUI or UIKit imports, and it builds for iOS and macOS.
- Levels must stay deterministic: a level's seed always deals the same tiles. The tile stream never depends on player actions (every run deals its whole stack up front, and quests are added as tiles are shown), and the bot sorts slots before choosing, because `Set` order changes every launch. Tests fail if a rule change makes any level unbeatable for the bot; if that happens, re-pick seeds with the disabled `findLevelSeeds` test.
- `PatchworkValley/` is the app: a SwiftUI HUD over a SpriteKit board.
  - `GameModel` is the `@Observable` owner of all three modes' runs, the saved valley, wallet, level number and Zen best (UserDefaults keys `mode`, `valley`, `wallet`, `level`, `zenBest`), the player's in-progress choice (selected slot, rotation), power-up use (Undo via `UndoPoint`, Dynamite aiming), viewing and saving a finished valley (`displayBoard` is what the scene draws), coin flights (the chip shows `walletShown`: the wallet less the coins still in the air), and Reset Player. It calls `scene.sync` after every change.
  - `Gallery` keeps saved valleys in Application Support/Gallery: `gallery.json` plus a full picture and a thumbnail PNG per valley. `GalleryView` shows them. `ValleyArt` draws a `ValleyPicture` with Core Graphics from the same `TileDrawing` layers as the board; it and the types it uses (`Palette`, `TileDrawing`, `HexGeometry`) are `nonisolated`, so saving draws off the main thread.
  - `ValleyScene` only renders. `sync(placement:blasted:)` reconciles its nodes (tiles, open slots, mountains, lakes, quest badges, ghost) with the model, and its gestures (tap, pan, pinch around the fingers) call into the model. `fitValley()` frames the valley between the HUD and the tray, using `hudTop`/`hudBottom` that `GameView` measures.
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

Build a signed device build (automatic signing, team `XWQQQ8GD2Z`, bundle ID `com.redmesastudios.PatchworkValley`), then install it with `xcrun devicectl device install app --device <id> <path to .app>`:

```bash
xcodebuild -project PatchworkValley.xcodeproj -scheme PatchworkValley -destination 'generic/platform=iOS' -configuration Debug -allowProvisioningUpdates build
```

In Debug builds, the menu has a Debug section for jumping between valleys or levels and adding coins, and the launch argument `-startingTiles N` starts Zen runs and Coin valleys with N tiles. Any saved key can be overridden at launch, for example `-mode coins -valley 5 -wallet 800`.

## Design tools

Two tests are disabled by default because they are tools, not checks. Enable one by removing its `.disabled(...)` trait, run it, and disable it again:

- `findLevelSeeds` searches for the tile order (seed) of each designed level, so the bot wins with a chosen number of tiles to spare. Copy the seeds it prints into `LevelDesigner.levels`.
- `coinEconomyReport` plays 300 Coin valleys at valleys 1, 5 and 10 with a quest-chasing, room-keeping bot and prints coins, quests, near misses and out-of-room rates. `docs/DESIGN.md` records its latest numbers.

## Rules for changes

- Game rules belong in `ValleyCore` and come with tests. The app never computes rules itself.
- Every visible state change animates, whether through a SwiftUI transition or `.animation` or an `SKAction`. Nothing snaps.
- UI sizes use `@ScaledMetric` or semantic fonts, never hard-coded values. Board world units are exempt because the camera zooms.
- The project uses Swift 6 and iOS 26. The app target's default actor isolation is `MainActor`.
- SpriteKit has had no new API since iOS 15. Keep it replaceable: it renders and handles gestures, nothing more. Avoid GameplayKit, which breaks under Swift 6 strict concurrency.
- The board view ignores sibling order for speed, so every SpriteKit node that must draw above a sibling needs an explicit `zPosition`. That includes shapes rendered into tile textures. Scene layers sit 10 apart so the small depths inside a layer never reach the next one.
- Swift Testing's `#expect` and `#require` can't wrap a `mutating` call; assign the result to a `let` first.
- Commit messages go in a temp file and use `git commit -F`; use `git -C <path>` rather than `cd` and git together.
