# Patchwork Valley: Design

## Core loop

Each run starts with one tile on the board and a stack of 30 tiles. The player sees the current tile and the next one.

- **Placing:** a tile goes in any open hex touching the valley and can be rotated first. Tapping a spot drops a ghost there in its best rotation, with stitches sewn across each matching seam. Tapping the ghost cycles through the rotations that fit, and **Place** confirms.
- **Terrain:** meadow, forest, field, village and river. Rivers must connect to rivers. The other terrains may touch anything.
- **Scoring:** 10 points per matching edge. A perfect fit (six neighbors, all matching) adds 50 points and one tile.
- **Quests:** some tiles carry a quest, for example "grow this forest to 8". The quest tracks the region connected to that tile. Completing it earns `3 + target / 3` tiles and `target × 10` points. If the region closes off before reaching the target, the quest fails. Up to three quests can be active at once, and targets grow as the valley grows.
- **Stuck tiles:** a tile that fits nowhere can be discarded, which costs one tile.
- **End of a run:** the run ends when the tiles run out. The game-over card reports the closest unfinished quest ("So close! Your forest was 1 tile from 10") and offers **+5 tiles** to keep going. That offer is the main moment the game sells.

All tuning numbers live in `Rules` (`ValleyCore/Sources/ValleyCore/ValleyGame.swift`).

## Monetization

- There are no forced ads. That is a selling point on the App Store listing, since competitors' reviews complain heavily about ads.
- Revenue comes from power-ups and the offer at the end of a run. Candidate power-ups: +5 tiles, undo, swap the current tile, see the next three tiles, and turn one tile into a wildcard.
- An optional VIP subscription (daily power-up allowance plus cosmetics) comes on top of that, never instead of it.
- Rewarded ads, where the player chooses to watch one for a free power-up, are undecided.

### Coin economy (planned)

Players earn coins from every run, scaled by score and quests completed, and spend them on power-ups. That builds a habit: players feel they are earning something that gets them a little further each time. When their coins run out, coin packs for real money let them keep powering up. Starter coins should cover the first several continues so the habit forms before the first purchase.

## Visual direction

The look is patchwork quilt: tiles resemble fabric patches with stitched seams, and a finished region gets "sewn" together. This gives the game an identity distinct from Dorfromantik. The prototype uses flat placeholder art drawn in code.

## Prototype scope

The prototype covers the core loop, quests, the near-miss game-over card and a free +5 continue. It does not yet include purchases, coins, a gallery of finished valleys, sound, final art or a tutorial.
