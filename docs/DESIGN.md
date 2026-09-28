# Patchwork Valley: Design

## Modes

The menu (top left) switches between three modes; each keeps its own run, so switching back and forth loses nothing.

- **Coins** (the main mode for new players): numbered valleys that pay coins, spent on power-ups.
- **Levels:** five designed levels with goals to meet.
- **Zen:** one valley for a high score, where quests earn more tiles.

## Placing tiles (all modes)

- **Placing:** a tile goes in any open hex touching the valley and can be rotated first. Tapping a spot drops a ghost there in its best rotation, with stitches sewn across each matching seam. Tapping the ghost cycles through the rotations that fit, and **Place** confirms. The player always sees the current tile and the next one.
- **Terrain:** meadow, forest, field, village and river. Rivers must connect to rivers. The other terrains may touch anything. In Coin mode and Zen, some water tiles are **lakes**: a pond with a single river flowing in, so rivers can end. Levels deal rivers only.
- **Scoring (Levels and Zen):** 10 points per matching edge. A **perfect fit** leaves the tile no open side (every side touches a tile, a mountain or a found lake), clashes with no neighbor, and matches at least two sides (a river into a lake counts); it's judged once the tile is down, so what it uncovers counts. It adds 50 points (Zen also gives a tile). Coin mode pays coins instead.
- **Stuck tiles (Levels and Zen):** a tile that fits nowhere can be discarded, which costs one tile. Coin mode has no discards; see *Win or lose* below.

Drag to pan and pinch to zoom (around the fingers); the **fit** button beside the quest chips frames the whole valley, including the mountains and lakes found so far, between the HUD and the tray. The menu also restarts the current run, and **Reset Player** (after a confirmation) starts over as a brand-new player: Coin mode, valley 1, the starting wallet, level 1, no Zen best, and the first run and tips again (the gallery stays). The menu's **Debug** section (add coins, jump between valleys or levels) is in every build while the game is in testing. All tuning numbers live in `Rules` (`ValleyCore/Sources/ValleyCore/ValleyGame.swift`) and, for coins and power-ups, `CoinEconomy.swift`.

## Coin mode

- Each valley is a fresh board with random quests, as in Zen. The first valleys are shorter: 24 tiles in valley 1, 30 in valley 2, and 36 from valley 3 on. The stack only counts down: quests and perfect fits pay coins, never tiles. There is no score.
- **The crater:** the valley floor is about 4 steps from its center to its wall, holds about 50–80 hexes, and is ringed by a mountain rim. Its edge wanders in and out (bays, points, bulges): nearly round in valley 1, getting more ragged each valley, fully ragged by valley 10. The crater's center sits up to one step from the start in valleys 1–2 and up to two from valley 3, so play often begins near a wall. The start and its six neighbors are always open floor. Peaks and ridges stand on the floor: 6 in valley 1, one more every two valleys, up to 14. The generator always leaves room for the whole stack.
- **Fog:** only hexes next to your tiles are visible. Placing a tile can uncover open ground, a mountain rising out of the fog, or a lake. The rim appears as you reach the edge. A Lantern lights the whole crater for one turn: when the next tile goes down, everything not touching a tile sinks back into the fog.
- **Hidden lakes** help rather than hinder: 2 per valley, 3 from valley 6, never next to each other. Tiles can't go on a lake, but a river edge touching one counts as a match (and a coin), and land can border it like a shore. A lake joins every river flowing into it into one region, and counts toward river quests. The preview ignores lakes still in fog; if a river turns out to flow into one, the match is paid when it's placed.
- **Match rule:** every tile must match at least one neighboring edge (rivers still meet rivers). Mountains count as neither match nor clash, and a spot boxed in by tiles and mountains still counts toward a perfect fit.
- **Win or lose:** placing the whole stack finishes the valley. If the tile in hand fits nowhere, the valley is **out of room**. The card offers a rescue (Swap, Undo, Wildcard or Dynamite) or a retry. There are no free discards in Coin mode.
- **Coins:** every matched side pays 1. A quest pays 5 + 2 per tile it asked for (a tile's forest-of-8 quest pays 21). A perfect fit pays 5. Finishing a valley's stack pays 20, banked right away. Coins stay in a wallet across valleys; new players start with 500. Coin mode shows coins, never points. Earned coins fly from the placed tile to the coin chip, one coin per coin (the finishing bonus too), and the total counts up as they land while a gold "+N" rises into it; spending drops a red "−N" out of the chip.
- **Valleys are numbered** and quests grow by one every three valleys, up to six bigger than valley 1's. Progress saves the moment a valley's stack is finished.
- **Always a quest going:** 30% of tiles carry a quest (up to 3 at once). Whenever none is active and none is on a tile in view, the game sets one. Half the time it grows a region already on the board, favoring the biggest, such as "grow this village from 14 to 18" (3–5 more tiles, 2–3 for rivers), so building big regions pays off. The other half, it puts a fresh quest on the next tile. If one kind isn't possible, the other is used.
- **Quest tiles ask for growth, wherever they land:** a quest tile asks its region to grow by its number minus one. Placed on its own, a village-8 tile means "grow to 8"; placed into a 14-village, it becomes "grow to 22" (a toast announces it), so joining a big region never wins a quest outright. This holds in Zen too. Quest rewards follow the growth asked for, counting the quest's first tile, not the region's full size.
- **Quests always fit the stack:** the whole stack is dealt when the valley starts, and a quest never asks for more than its own tile plus 70% of the matching tiles still to come (60% for rivers, which are harder to join). A river quest of 4 can't appear when only two river tiles remain. A terrain showing on just one side of the quest tile asks for 2 less, since it can only grow one way, and quests favor terrains that cover more of the tile.
- **Power-ups** are introduced one per valley on the valley's opening card, and bought with coins from the bar under the tile tray:

| Power-up | Introduced | Price | Effect |
|---|---|---|---|
| Swap | Valley 1 | 25 | Trade the tile in hand for a freshly dealt one |
| Undo | Valley 2 | 50 | Take back the last placement and the coins it earned |
| Wildcard | Valley 3 | 100 | The tile in hand becomes a patchwork that matches, and joins, any terrain |
| Dynamite | Valley 4 | 200 | Blast a revealed mountain on the valley floor (not the rim), opening the ground |
| Lantern | Valley 5 | 300 | Light every mountain and lake in the valley until the next tile is placed; the preview counts lit lakes, and Dynamite can reach any lit floor mountain |

- **Quest endings:** when a quest completes, its chip and its badge on the board turn green with a check before leaving; when its region is closed off, they turn red with a cross.
- **End of a valley:** when the stack runs out, the card shows the coins earned and lists the quests the valley ends without: those still going and any the last tile closed off, with how far each got ("Forest 6 of 10 · 4 short", "Village closed off at 5 of 6"). If a quest is within three tiles, it offers **+3 tiles for 250 coins** as well as the next valley. Bought tiles are a bonus: if one fits nowhere, the out-of-room card offers the rescues and **Finish valley**, which ends the valley as done, so buying tiles never turns a finished valley into a loss.
- **View valley:** the end card's **View valley** puts the card away and lifts the fog off the whole crater: every mountain and lake rises into view, found or not, and the camera frames it all. The finished valley can be panned and zoomed but not played. **Save to Gallery** keeps it (see *Gallery*), and **Done** brings the card back with the valley still in full view. Looking never changes the run, so buying +3 tiles afterwards puts the fog back.
- **Dynamite with nothing to blast:** when every mountain found so far is on the valley's edge, the Dynamite button looks off but still answers a tap, with a message that only mountains inside the valley can be blasted.
- **Economy and difficulty:** the disabled `coinEconomyReport` test plays 300 valleys with a bot that chases quests while keeping room open (a stand-in for a planning player):

| Valley | Coins per valley (+20 bonus) | Quests | Out of room |
|---|---|---|---|
| 1 | 75 | 2.5 | 8% |
| 5 | 93 | 2.1 | 23% |
| 10 | 82 | 1.4 | 27% |

  Valley 1's shorter stack earns fewer coins and rarely runs out of room. With a quest always going, the bot chases quests harder and gets stuck a little more often; a purely greedy bot gets stuck about twice as often, so planning ahead pays.
- Planned power-ups: Lift (move a placed tile), Pocket (set a tile aside to play later) and Peek (see the next three tiles).

## Levels

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

One valley for a high score on the open plane (no crater, no match rule), starting with 30 tiles. Peaks and lakes hide in the fog, as in Coin mode: about 6% of hexes within 20 steps of the start hold a peak (single peaks and short ridges) and about 2% a lake, set apart from each other. The start and its neighbors are always clear, and the start is never walled in. A tile touching one brings it into view; tiles can't go on either, and a river flowing into a lake counts as a match. Zen has no power-ups. Some tiles carry a quest, for example "grow this forest to 8", which asks the region the tile joins to grow by that many tiles (see *Quest tiles ask for growth* above). Completing a quest earns `3 + growth / 3` tiles and `target × 10` points. A quest fails if its region closes off first. Perfect fits earn one extra tile. The run ends when tiles run out, and the card offers **+5 tiles** and shows the best score.

## Gallery

Finished Coin valleys can be saved from the *View valley* screen. The menu's **Gallery** shows them newest first, with the valley number and date; tap one to see it full screen (pinch or double-tap to zoom), and press and hold, or use the trash button, to delete one after a confirmation. Each saved valley keeps its picture and its layout (every tile, mountain and lake), so it can be drawn again at any size, for sharing later. Reset Player leaves the gallery alone.

## Monetization

- There are no forced ads. That is a selling point on the App Store listing, since competitors' reviews complain heavily about ads.
- Revenue comes from power-ups and the offer when a level runs out. Candidate power-ups: +3 tiles, undo, swap the current tile, see the next three tiles, and turn one tile into a wildcard.
- An optional VIP subscription (daily power-up allowance plus cosmetics) comes on top of that, never instead of it.
- Rewarded ads, where the player chooses to watch one for a free power-up, are undecided.

### Coin packs (planned)

Coin mode builds the habit: players earn coins that get them a little further each valley, and grow used to power-ups. When their coins run out, coin packs for real money let them keep powering up. The starting wallet should let a new player try each early power-up a couple of times and get hooked, and a few free power-ups at the start (as the bus game does) are worth trying.

## First run

A new player on valley 1 is coached through the first tiles instead of reading rules; players past valley 1 never see it. It takes about 45 seconds, and **Skip** is always there.

- **Glimpse (about 10 seconds, at least 2 per beat):** no HUD. The tutorial valley, finished by the bot, sits on the board under fog (2.5 s); the fog lifts (2.5 s, "Build a valley like this, one tile at a time."), a white photo frame drops around it (3 s, "Finish it, and keep the picture."), then it folds away a ring at a time to the single starting tile (2 s). Taps on the board don't cut it short; Skip does.
- **Four coached tiles** on a fixed tutorial deal (`Tutorial`, valley-1 seed 120854), with dots showing the four steps. The HUD comes in piece by piece: first only the coin chip and the tile with Place.
  1. *Place:* one spot glows, a hand points at it, the ghost lands matching with its stitches, and Place wears a ring and the hand. One coin flies in.
  2. *Turn:* Rotate appears. The ghost lands as dealt, red, and shakes; "The sides don't match. Tap the tile to turn it." One turn matches two sides for two coins.
  3. *Quest:* the quest chip and badge appear ("Quest: add 1 more field tile here for bonus coins."); one spot glows with no hand, and it finishes the quest.
  4. *Choice:* Next appears; every fitting spot glows ("Your turn. Put it anywhere that glows.").
- **Hand-off:** the menu, tiles left, fit and the power-ups slide in: "20 tiles to go. Can you find 2 hidden lakes?" with **Let's go** (or tap any spot).
- A tap anywhere but the coached spot shakes the line and pops the spot. "New quest" toasts stay quiet until the hand-off.
- **One-time tips** afterwards, each gone with the next action: a tile that fits 2 spots or fewer rings Swap ("Tricky tile? Your coins can Swap it for another."); the first out-of-room card adds "It happens! A power-up can rescue this tile."; the first finished valley rings View valley ("Lift the fog and see what you built."); the first look over it rings Save.
- **How to Play** in the menu (Coin mode) coaches the next tiles of the current valley with the whole HUD in view: place, turn when a spot can teach it, choice, then a closing line.

## Visual direction

The look is patchwork quilt: tiles resemble fabric patches with stitched seams, and a finished region gets "sewn" together. This gives the game an identity distinct from Dorfromantik. A planned meta layer builds on it: each completed level becomes a patch sewn into the player's growing quilt. The prototype uses flat placeholder art drawn in code. The app icon, Stitched Hills (a hexagon window onto fabric hills sewn with cream stitches), is one opaque 1024×1024 PNG in `PatchworkValley/Assets.xcassets/AppIcon.appiconset`, drawn from `docs/AppIcon.svg`.

## Prototype scope

The prototype covers Coin mode (irregular craters, fog, mountains, lakes, a quest always going, five power-ups, coin flights), five designed levels, Zen mode, the near-miss cards, the first run and tips, View valley and the gallery, Reset Player and camera fit. It does not yet include real-money purchases, free starter power-ups, the quilt, sound, final art or sharing.
