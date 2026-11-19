# Patchwork Valley

A calm puzzle game for iPhone. Place hex landscape patches, match their edges, and grow a
valley out of the fog.

## How it plays

Every patch has six sides of meadow, forest, field, village or river. A patch goes in any
open spot touching the valley and can be rotated first. Rivers must connect to rivers, and
matching sides score.

- **Coins** is the main mode: numbered valleys with quests that pay coins, which buy
  power-ups. Each valley is a crater hidden in fog, with mountains and lakes to find.
- **Levels** are five designed puzzles with region goals to meet from a fixed stack of
  patches.
- **Zen** is one long valley played for a high score, where quests earn more patches.

Finished valleys are saved to a gallery as pictures.

## How it's built

- **`ValleyCore/`** is a Swift package that holds every game rule: the hex grid, the
  seeded tile generator, the board, scoring, quests, goals and the designed levels. It has
  no UI and comes with tests. A level's seed always deals the same patches, and a bot
  proves every designed level can be won.
- **`PatchworkValley/`** is the app: a SwiftUI HUD over a SpriteKit board. SpriteKit only
  renders and handles gestures, so it stays replaceable.
- One drawing routine draws patches for both the SpriteKit board and the SwiftUI tray, so
  they look the same everywhere.
- Sound runs through a single `AVAudioEngine` that follows the silent switch and mixes
  with the player's own music.
- Every visible state change animates, and text follows the player's text size.

The project uses Swift 6 and iOS 26.

## Build and test

```bash
cd ValleyCore && swift test
```

```bash
xcodebuild -project PatchworkValley.xcodeproj -scheme PatchworkValley -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

To run on your own device, set your development team under Signing & Capabilities.

## More

- [docs/DESIGN.md](docs/DESIGN.md) covers the game design in full.
- [docs/CONCEPTS.md](docs/CONCEPTS.md) holds other game concepts.
