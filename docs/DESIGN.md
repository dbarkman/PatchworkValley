# Patchwork Valley: Design

## Modes

The menu (top left) switches between three modes; each keeps its own run, so switching back and forth loses nothing.

- **Coins** (the main mode for new players): numbered valleys that pay coins, spent on power-ups.
- **Levels:** five designed levels with goals to meet.
- **Zen:** one valley for a high score, where quests earn more tiles.

## Placing tiles (all modes)

- **Placing:** a tile goes in any open hex touching the valley and can be rotated first. Tapping a spot drops a ghost there in its best rotation, with stitches sewn across each matching seam. Tapping the ghost cycles through the rotations that fit, and **Place** confirms. The player always sees the current tile and the next one.
- **Terrain:** meadow, forest, field, village and river. Rivers must connect to rivers. The other terrains may touch anything. In Coin mode and Zen, some water tiles are **lakes**: a pond with a single river flowing in, so rivers can end. Levels deal rivers only.
- **Scoring:** 10 points per matching edge. A perfect fit (six neighbors, all matching) adds 50 points.
- **Stuck tiles:** a tile that fits nowhere can be discarded, which costs one tile.

The menu also restarts the current run. All tuning numbers live in `Rules` (`ValleyCore/Sources/ValleyCore/ValleyGame.swift`) and, for coins and power-ups, `CoinEconomy.swift`.

## Coin mode

- Each valley is a fresh board with 36 tiles (6 × 6) and random quests, as in Zen. The stack only counts down: quests and perfect fits pay coins, never tiles. There is no score.
- **The crater:** the valley floor is a hexagon of radius 4 (61 hexes) ringed by a mountain rim. Peaks and ridges stand on the floor: 6 in valley 1, one more every two valleys, up to 14. The generator always leaves room for all 36 tiles.
- **Fog:** only hexes next to your tiles are visible. Placing a tile can uncover open ground, a mountain rising out of the fog, or a lake. The rim appears as you reach the edge.
- **Hidden lakes** help rather than hinder: 2 per valley, 3 from valley 6, never next to each other. Tiles can't go on a lake, but a river edge touching one counts as a match (and a coin), and land can border it like a shore. A lake joins every river flowing into it into one region, and counts toward river quests. The preview ignores lakes still in fog; if a river turns out to flow into one, the match is paid when it's placed.
- **Match rule:** every tile must match at least one neighboring edge (rivers still meet rivers). Mountains count as neither match nor clash, and a spot boxed in by tiles and mountains still counts toward a perfect fit.
- **Win or lose:** placing the whole stack finishes the valley. If the tile in hand fits nowhere, the valley is **out of room**. The card offers a rescue (Undo, Swap, Wildcard or Dynamite) or a retry. There are no free discards in Coin mode.
- **Coins:** every matched side pays 1. A quest pays 5 + 2 per tile of its target (a forest of 8 pays 21). A perfect fit pays 5. Finishing a valley's stack pays 20, banked right away. Coins stay in a wallet across valleys; new players start with 300. Coin mode shows coins, never points.
- **Valleys are numbered** and quests grow by one every three valleys, up to six bigger than valley 1's. Progress saves the moment a valley's stack is finished.
- **Quests always fit the stack:** the whole stack is dealt when the valley starts, and a quest never asks for more than its own tile plus 70% of the matching tiles still to come (60% for rivers, which are harder to join). A river quest of 4 can't appear when only two river tiles remain.
- **Power-ups** are introduced one per valley on the valley's opening card, and bought with coins from the bar under the tile tray:

| Power-up | Introduced | Price | Effect |
|---|---|---|---|
| Undo | Valley 1 | 60 | Take back the last placement and the coins it earned |
| Swap | Valley 2 | 80 | Trade the tile in hand for a freshly dealt one |
| Wildcard | Valley 3 | 160 | The tile in hand becomes a patchwork that matches, and joins, any terrain |
| Dynamite | Valley 4 | 120 | Blast a revealed mountain on the valley floor (not the rim), opening the ground |
| Lantern | Valley 5 | 100 | Lift the fog off every mountain and lake in the valley |

- **End of a valley:** when the stack runs out, the card shows the coins earned. If a quest is within three tiles, it offers **+3 tiles for 200 coins** as well as the next valley. Bought tiles are a bonus: if one fits nowhere, the valley still counts as finished.
- **Economy and difficulty:** the disabled `coinEconomyReport` test plays 300 valleys with a bot that chases quests while keeping room open (a stand-in for a planning player):

| Valley | Coins per valley (+20 bonus) | Quests | Out of room |
|---|---|---|---|
| 1 | 109 | 2.9 | 13% |
| 5 | 103 | 2.5 | 17% |
| 10 | 91 | 1.8 | 26% |

  A purely greedy bot gets stuck about twice as often, so planning ahead pays.
- Planned power-ups: Lift (move a placed tile), Pocket (set a tile aside to play later) and Peek (see the next three tiles).

## Levels (main mode)

- Each level is a fresh valley with a fixed stack of tiles and one or more goals, such as "grow a forest of 9". A goal counts the largest connected region of its terrain.
- The stack only counts down: no tile quests and no bonus tiles. When the counter reads 3, the level really is almost done.
- **Winning:** the level ends as soon as every goal is met. Each unused tile is worth 25 points. The player's level number is saved.
- **Losing:** the level ends when tiles run out with a goal unmet. The card shows each goal's progress and the closest miss ("So close! Your field was 2 tiles short of 6"), and offers **+3 tiles** or a retry. That offer is the main moment the game sells.
- **Difficulty is tightness:** how many tiles you get for the size of the goals. Every level's goals add up to half its stack.

| Level | Tiles | Goals | Bot's spare tiles |
|---|---|---|---|
| 1 | 12 | Field 6 | 4 |
| 2 | 18 | Forest 9 | 4 |
| 3 | 24 | Forest 6, field 6 | 1 |
| 4 | 30 | Forest 5, field 5, village 5 | 1 |
| 5 | 36 | Forest 6, field 5, village 4, river 3 | 1 |

- **Tile order is designed too.** Each level has a fixed seed, so it deals the same tiles every time. Seeds are picked with `LevelDesigner.searchSeed`, which finds a tile order the greedy bot (`GreedyBot`) wins with a chosen number of tiles to spare: comfortable early on, and only just by level 3. To design or change a level, enable the `findLevelSeeds` test, run it, and copy the seeds it prints.
- After level 5, a card congratulates the player and offers to play again from level 1 or to try Zen.
- Unlimited levels are the long-term goal. New ingredients (power-ups, new terrains, obstacles) will keep them fresh.

## Zen mode

One valley for a high score, starting with 30 tiles. Some tiles carry a quest, for example "grow this forest to 8", which tracks the region connected to that tile. Completing a quest earns `3 + target / 3` tiles and `target × 10` points. A quest fails if its region closes off first. Perfect fits earn one extra tile. The run ends when tiles run out, and the card offers **+5 tiles** and shows the best score.

## Monetization

- There are no forced ads. That is a selling point on the App Store listing, since competitors' reviews complain heavily about ads.
- Revenue comes from power-ups and the offer when a level runs out. Candidate power-ups: +3 tiles, undo, swap the current tile, see the next three tiles, and turn one tile into a wildcard.
- An optional VIP subscription (daily power-up allowance plus cosmetics) comes on top of that, never instead of it.
- Rewarded ads, where the player chooses to watch one for a free power-up, are undecided.

### Coin packs (planned)

Coin mode builds the habit: players earn coins that get them a little further each valley, and grow used to power-ups. When their coins run out, coin packs for real money let them keep powering up. The starting wallet should let a new player try each early power-up a couple of times and get hooked, and a few free power-ups at the start (as the bus game does) are worth trying.

## Visual direction

The look is patchwork quilt: tiles resemble fabric patches with stitched seams, and a finished region gets "sewn" together. This gives the game an identity distinct from Dorfromantik. A planned meta layer builds on it: each completed level becomes a patch sewn into the player's growing quilt. The prototype uses flat placeholder art drawn in code.

## Prototype scope

The prototype covers Coin mode (crater, fog, mountains, five power-ups), five designed levels, Zen mode, the near-miss cards and free continues. It does not yet include real-money purchases, the quilt, sound, final art or a tutorial.
