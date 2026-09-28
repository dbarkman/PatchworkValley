# Patchwork Valley: Design

## Modes

The menu (top left) switches between three modes; each keeps its own run, so switching back and forth loses nothing.

- **Coins** (the main mode for new players): numbered valleys that pay coins, spent on power-ups.
- **Levels:** five designed levels with goals to meet.
- **Zen:** one valley for a high score, where quests earn more tiles.

## Placing tiles (all modes)

- **Placing:** a tile goes in any open hex touching the valley and can be rotated first. In Coin mode, the spots where the tile in hand fits glow softly, all rising and falling together (still with Reduce Motion). Tapping a spot drops a ghost there in its best rotation, with stitches sewn across each matching seam. Tapping the ghost cycles through the rotations that fit, and **Place** confirms. The player always sees the current tile and the next one.
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
- **Coins:** every matched side pays 1. A quest pays 5 + 2 per tile it asked for (a tile's forest-of-8 quest pays 21). A perfect fit pays 5. Finishing a valley's stack pays 20, banked right away. Coins stay in a wallet across valleys; new players start with 500. On screen, coins in general are "rewards" ("each match earns a reward"), and "coins" goes with an amount ("50 coins"). Coin mode shows coins, never points. Earned coins fly from the placed tile to the coin chip, one coin per coin (the finishing bonus too), and the total counts up as they land while a gold "+N" rises into it; spending drops a red "−N" out of the chip.
- **Valleys are numbered** and quests grow by one every three valleys, up to six bigger than valley 1's. Progress saves the moment a valley's stack is finished.
- **Always a quest going:** 30% of tiles carry a quest (up to 3 at once). Whenever none is active and none is on a tile in view, the game sets one. Half the time it grows a region already on the board, favoring the biggest, such as "grow this village from 14 to 18" (3–5 more tiles, 2–3 for rivers), so building big regions pays off. The other half, it puts a fresh quest on the next tile. If one kind isn't possible, the other is used.
- **Quest tiles ask for growth, wherever they land:** a quest tile asks its region to grow by its number minus one. Placed on its own, a village-8 tile means "grow to 8"; placed into a 14-village, it becomes "grow to 22" (a toast announces it), so joining a big region never wins a quest outright. This holds in Zen too. Quest rewards follow the growth asked for, counting the quest's first tile, not the region's full size.
- **Quests always fit the stack:** the whole stack is dealt when the valley starts, and a quest never asks for more than its own tile plus 70% of the matching tiles still to come (60% for rivers, which are harder to join). A river quest of 4 can't appear when only two river tiles remain. A terrain showing on just one side of the quest tile asks for 2 less, since it can only grow one way, and quests favor terrains that cover more of the tile.
- **Power-ups** are introduced one per valley on the valley's opening card (with a free try: Swap in the first run, the others in their demos), and bought with coins from the bar under the tile tray:

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

A new player on valley 1 sees a short intro, then is coached through the first tiles instead of reading rules; players past valley 1 never see it. **Skip** is always there.

- **Intro (five pages, each waiting for Next, with Skip):** just the board, the bubble with dots for the five pages, and from page 2 the coin chip. It tells the game's hook, build a valley, finish quests, earn rewards, keep what you build, on the tutorial valley itself:
  1. "A valley, lost in fog. Can you bring it back?" The tutorial valley, finished by the bot, barely shows through drifting fog.
  2. "Stitch it back together, one patch at a time. Every matching side earns a reward." The fog clears, the valley folds away a ring at a time to its first tile, and a tile shows its stitches and goes down; its coin flies to the chip.
  3. "Quests help grow your valley and earn a pile of rewards when finished." Three more tiles go down by themselves: the quest chip and badge count down, the chip turns green, and twelve coins stream to the chip.
  4. "Spend your rewards on helpful power-ups." A card headed "Power-ups" lists all five, arriving one after another, each with a few words.
  5. "Finish a valley, then save and share." The finished valley comes back, lit, and a photo frame drops around it; the button says **Let's go!**.

  The intro's tiles go down by themselves, and their coins fly to the chip and stay in the wallet (17, a small welcome gift); Next finishes a page's tiles at once. Let's go! (or Skip on any page) folds the board down to the valley's first tile and starts the coached tiles, which have their own Skip.
- **Five coached tiles** on a fixed tutorial deal (`Tutorial`, valley-1 seed 1106390), with dots showing the five steps. The HUD comes in piece by piece: first only the coin chip and the tile with Place. The valley opens with no quest going; the second tile carries one.
  1. *Place:* one spot glows, a hand points at it, the ghost lands matching with its stitches ("Stitches mean the sides match, and each match earns a reward."), and Place wears a ring and the hand. One coin flies in.
  2. *Quest tile:* the tag on the tile in the tray wears a ring: "This tile has a quest. This tag means: grow a forest of 3 tiles." Its spot keeps its forest apart from any other forest, so the quest asks for the 3 on its tag. Once it's down ("Tap Place to start the quest."), the quest chip appears up top and a badge on the board. It matches two sides for two coins.
  3. *Turn:* the badge pulses ("The badge counts the forest tiles still needed.") and Rotate appears. The ghost lands as dealt, red, and shakes; "The sides don't match. Tap the tile to turn it." One turn matches two sides for two coins and grows the forest to 2 of 3.
  4. *Finish the quest:* the quest chip wears a ring ("The chip up top tracks the quest too. One more forest tile finishes it for bonus rewards."); an all-forest tile finishes it: 1 coin for its match and 11 for the quest.
  5. *Choice:* Next appears; every fitting spot glows ("Your turn, tap any glowing spot."). The fifth tile fits in 6 spots, and wherever it goes, the valley can be finished with or without swapping the sixth tile.
- **Try Swap:** everything slides in, and the coin chip and Swap wear rings: "Matches and quests earn rewards, and rewards buy power-ups. Don't like your tile? Swap trades it for a new one. Try it free." The swap is free; Skip here goes on to the hand-off.
- **Hand-off:** the tiles-left chip wears a ring: "19 tiles left to place. Can you find 2 hidden lakes?" Only **Let's go!** closes it.
- While coaching, a tap anywhere but where the coach points shakes the line and pops the spot, and only the power-up being taught can be tapped. "New quest" toasts stay quiet until the hand-off.
- **One-time tips** afterwards, each gone with the next action: a tile that fits 2 spots or fewer rings Swap ("Tricky tile? Spend rewards to Swap it for another."); the first out-of-room card adds "It happens! A power-up can rescue this tile."; the first finished valley rings View valley ("Lift the fog and see what you built."); the first look over it rings Save.
- **How to Play** in the menu (Coin mode) coaches the next tiles of the current valley with the whole HUD in view: place, turn when a spot can teach it, choice, then a closing line.

## Power-up demos

Valleys 2–5 each bring a power-up, and the first time a player reaches one, its opening card says **Try it** instead of Play. The demo runs on its own little valley (`PowerUpDemo`: a fixed crater and tiles that pay no coins and set no quests; the tray says "Practice tile"), with only that power-up on the bar, and the try is free. Undo and Wildcard go straight on to the real valley a moment after the try; Dynamite and Lantern end with a line and **Continue**. Either way, or with Skip, a fresh real valley is dealt, so nothing seen or done in the demo carries over ("A fresh valley. Good luck!").

| Valley | Demo |
|---|---|
| 2 Undo | Place the coached tile, then tap Undo to take it back. |
| 3 Wildcard | The tile in hand fits one spot; tap Wildcard and place the wild tile anywhere. |
| 4 Dynamite | "Watch: a tile goes down, and a mountain comes out of the fog." waits for **Next**; the coach places the tile and a mountain rises. Tap Dynamite, then the glowing mountain; "Boom! Mountains on the valley's edge can't be blasted." |
| 5 Lantern | "The Lantern shows them all for one turn." Tap Lantern; every hidden mountain and lake lights up, the camera frames the whole crater: "There's everything the fog was hiding." |

Reset Player brings the demos back; players already past a valley don't get its demo.

## Visual direction

The look is patchwork quilt: tiles resemble fabric patches with stitched seams, and a finished region gets "sewn" together. This gives the game an identity distinct from Dorfromantik. A planned meta layer builds on it: each completed level becomes a patch sewn into the player's growing quilt. The prototype uses flat placeholder art drawn in code. The app icon, Stitched Hills (a hexagon window onto fabric hills sewn with cream stitches), is one opaque 1024×1024 PNG in `PatchworkValley/Assets.xcassets/AppIcon.appiconset`, drawn from `docs/AppIcon.svg`.

## Prototype scope

The prototype covers Coin mode (irregular craters, fog, mountains, lakes, a quest always going, five power-ups, coin flights), five designed levels, Zen mode, the near-miss cards, the first run and tips, View valley and the gallery, Reset Player and camera fit. It does not yet include real-money purchases, free starter power-ups, the quilt, sound, final art or sharing.
