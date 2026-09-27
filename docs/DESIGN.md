# Patchwork Valley: Design

## Placing tiles (both modes)

- **Placing:** a tile goes in any open hex touching the valley and can be rotated first. Tapping a spot drops a ghost there in its best rotation, with stitches sewn across each matching seam. Tapping the ghost cycles through the rotations that fit, and **Place** confirms. The player always sees the current tile and the next one.
- **Terrain:** meadow, forest, field, village and river. Rivers must connect to rivers. The other terrains may touch anything.
- **Scoring:** 10 points per matching edge. A perfect fit (six neighbors, all matching) adds 50 points.
- **Stuck tiles:** a tile that fits nowhere can be discarded, which costs one tile.

The menu (top left) switches between Levels and Zen and restarts the current run. Each mode keeps its own run, so switching back and forth loses nothing. All tuning numbers live in `Rules` (`ValleyCore/Sources/ValleyCore/ValleyGame.swift`).

## Levels (main mode)

- Each level is a fresh valley with a fixed stack of tiles and one to three goals, such as "grow a forest of 12". A goal counts the largest connected region of its terrain.
- The stack only counts down: no tile quests and no bonus tiles. When the counter reads 3, the level really is almost done.
- **Winning:** the level ends as soon as every goal is met. Each unused tile is worth 25 points. The player's level number is saved.
- **Losing:** the level ends when tiles run out with a goal unmet. The card shows each goal's progress and the closest miss ("So close! Your field was 2 tiles short of 5"), and offers **+3 tiles** or a retry. That offer is the main moment the game sells.
- **Stack sizes** run 12, 18, 24, 30, 36 and then repeat. Every stack is a multiple of six, one per side of a hex, a quiet nod players may or may not notice. The short levels after each 36 act as breathers.
- **Generated levels:** `LevelDesigner` builds each level from its number, with no hand design. A greedy bot (`GreedyBot`) plays the level's exact tile stream, and goals are set to a share of the regions it reached: 75% at first, rising 5% every five levels, plus 10% on each 36-tile finale, capped at 100%. The bot is a modest player, so every level is provably beatable and a thoughtful player has room to spare. River goals start at level 8.

## Zen mode

One valley for a high score, starting with 30 tiles. Some tiles carry a quest, for example "grow this forest to 8", which tracks the region connected to that tile. Completing a quest earns `3 + target / 3` tiles and `target × 10` points. A quest fails if its region closes off first. Perfect fits earn one extra tile. The run ends when tiles run out, and the card offers **+5 tiles** and shows the best score.

## Monetization

- There are no forced ads. That is a selling point on the App Store listing, since competitors' reviews complain heavily about ads.
- Revenue comes from power-ups and the offer when a level runs out. Candidate power-ups: +3 tiles, undo, swap the current tile, see the next three tiles, and turn one tile into a wildcard.
- An optional VIP subscription (daily power-up allowance plus cosmetics) comes on top of that, never instead of it.
- Rewarded ads, where the player chooses to watch one for a free power-up, are undecided.

### Coin economy (planned)

Players earn coins for every level they complete, and more for tiles to spare. Coins buy power-ups. That builds a habit: players feel they are earning something that gets them a little further each time. When their coins run out, coin packs for real money let them keep powering up. Starter coins should cover the first several continues so the habit forms before the first purchase.

## Visual direction

The look is patchwork quilt: tiles resemble fabric patches with stitched seams, and a finished region gets "sewn" together. This gives the game an identity distinct from Dorfromantik. A planned meta layer builds on it: each completed level becomes a patch sewn into the player's growing quilt. The prototype uses flat placeholder art drawn in code.

## Prototype scope

The prototype covers generated levels with goals, Zen mode, the near-miss cards and free continues. It does not yet include purchases, coins, the quilt, sound, final art or a tutorial.
