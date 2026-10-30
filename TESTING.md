# Testing Patchwork Valley

Build 2026103001 (version 1) is the one on TestFlight. Testers get it from TestFlight; a build from Xcode (scheme PatchworkValley) has the same menu.

## The Testing section

The menu at the top left ends with a **Testing** section, in every build, TestFlight included:

- **+500 Coins** (Coin mode) adds 500 to the wallet. Each tap gives a success haptic, and as the menu closes the coin chip pops and counts up with a gold "+500"; the item's subtitle shows the balance ("You have 800 coins").
- **Next Valley** and **Previous Valley** (Coin mode), **Next Level** and **Previous Level** (Levels) jump around.
- **Reset Everything** (every mode) asks "Reset everything? All progress, rewards and saved valleys go back to a fresh install." with Reset and Cancel. Reset wipes every saved key (mode, valley, wallet, level, Zen best, first run done, tips and demos seen) and the whole gallery, then glides into the first run's intro on valley 1 with 300 coins, no relaunch needed.

Reset Player, above it, stays the player-facing start-over and keeps the gallery.

Try it: save a valley to the gallery, play into Levels and set a Zen best, then Reset Everything. The intro should start at once; Skip through, and check the gallery is empty, Levels opens on level 1, Zen shows no best, valley 2 offers its Undo demo again, and the wallet reads 300 (plus the intro's 17). Then tap +500 Coins and buy a power-up with it.
