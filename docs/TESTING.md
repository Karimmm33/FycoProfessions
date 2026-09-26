# FycoProfessions in-game testing sheet

> **Status (0.10.0): every phase is built and passes the automated suite. In
> game, only the settings width fix (C0) is confirmed so far; everything else,
> including the new map pins (section O), still needs testing.** This sheet
> covers all of it, in the order it was built.

Work through the sections in order. For each test, do exactly what the **How**
column says, compare with **Expected**, and report back by ID, for example:

> A1 ok, A2 ok, F3 FAIL - the path says "Make 10 x Rough Stone Statue" but the recipe is grey in my window, screenshot attached

Anything marked **auto** has already been checked by the automated test suite
(`py -3.11 tests/run_tests.py`, see the bottom of this file), so for those you
only need to confirm that the game agrees with the mock. If you see red error
text anywhere, copy it into your report exactly.

Tests marked **realm** compare what the addon was built from (this realm's
client files plus the stock AzerothCore database) with what Frostmourne
Rebuffed really does. A difference there is a finding, not necessarily a bug:
tell me what the game shows and I will correct the data.

---

## Setup (once)

1. Close the game.
2. In PowerShell:
   ```powershell
   cd D:\Projects\FycoProfessions
   .\scripts\deploy.ps1
   ```
   It must end with a green **Deployed.** line. It creates
   `Interface\AddOns\FycoProfessions` and does not touch FycoPvE or FycoPvP.
3. Start the game. On the character select screen, click **AddOns** and make
   sure **FycoProfessions** is listed and ticked.
4. Log in on the character with Jewelcrafting and Skinning.
5. Run `/console scriptErrors 1` once and `/reload`, so any Lua error pops up
   in a window you can screenshot.

---

## Phase 0 - foundation

### A. Loading

| ID | How | Expected |
|---|---|---|
| A1 | Log in and look at chat. | One line: `FycoProfessions v0.10.0 - x2, target: your rank's cap, <your faction>. /fprof to open.` (auto) |
| A2 | Look at the edge of the minimap. | A round button with a note icon, separate from FycoPvE's book button. |
| A3 | Type `/fprof help`. | A list of twelve commands, with no red text. (auto) |
| A4 | Type `/reload`. | The same greeting again, and no errors. |

### B. Main window

| ID | How | Expected |
|---|---|---|
| B1 | Type `/fprof`. | A window titled **FycoProfessions v0.10.0**, grey line under it `Guide: x2, target: your rank's cap, <faction>`, a **Settings** button top-right. Tab buttons: one per profession you have (for example **Jewelcrafting**, **Skinning**, **Cooking**, **First Aid**, **Fishing**) and **All professions** last. No tab for a profession you do not have. (auto) |
| B2 | Drag the window by its title area, close it with X, then `/fprof` again. | It reopens where you left it. |
| B3 | With the window open, press **Escape**. | It closes. |
| B4 | Left-click the minimap button, then right-click it. | Left opens and closes the window. Right opens *Interface → AddOns → FycoProfessions*. |
| B5 | Drag the minimap button around the minimap, then `/reload`. | It stays where you left it. |
| B6 | Hover the minimap button. | A tooltip: `FycoProfessions`, the guide line, and click hints. |

### C. Settings

| ID | How | Expected |
|---|---|---|
| C0 | Open every FycoProfessions settings page (main, **Tracker**, **Auction House**). | Nothing is cut off on the right: every checkbox label, dropdown arrow, slider and button sits inside the grey area with room to spare, and everything on the right column can be clicked. (auto) |
| C1 | `/fprof options`. | *Interface → AddOns → FycoProfessions* opens. Left: **Leveling guide** with four dropdowns (Skill points per skill-up, Guides stop at, Faction, Materials), each with a grey note, and a **Use recipes that only drop** checkbox. Right: **Window**, **Features** (Tracker, Tooltips), **About the data**. Nothing runs past the bottom; the page scrolls if it is long. |
| C2 | Open **Skill points per skill-up**. | `x1 (stock)` and `x2`; `x2` ticked. |
| C3 | Pick `x1`, then open the Jewelcrafting tab. | The window's guide line says `x1`, and the path has about twice as many crafts. Set it back to `x2`: the counts halve again. (auto) |
| C4 | Open **Guides stop at**. | `Your rank's cap`, then `75 (Apprentice)` to `450 (Grand Master)`. Pick `450`: the path gets **Train ...** steps at each rank cap above your current one. (auto) |
| C5 | Open **Faction**. | `Auto (<your faction>)`, `Alliance`, `Horde`. Pick the other faction: trainers shown switch to that faction's. On another character it is back to Auto (saved per character). Set it back to Auto. (auto) |
| C6 | Open **Materials**. | `Buy or gather` and `Gathered only`. With `Gathered only` the window line ends in `gathered materials only`, path costs stop using Auction House prices, and recipes whose materials cannot be gathered or bought from a vendor drop out. Set it back. (auto) |
| C7 | Expand FycoProfessions in the options' left list. | Sub-pages **Tracker** and **Auction House**. |
| C8 | Change **Window scale** to 1.2. | The window grows at once. Set it back to 1. |
| C9 | Untick **Minimap button**, then tick it. | The button disappears and comes back. |
| C10 | `/reload`, then open the settings. | Every choice you left is still set. |

### D. Tracker

| ID | How | Expected |
|---|---|---|
| D1 | After login, look at the right side of the screen. | A small dark frame titled e.g. **Jewelcrafting 120/150 (x2)** with the current step (`Make 9 x ...`, `until ...`) and one `have/need` line per material, green when you have enough, red when not. |
| D2 | Drag it somewhere else, then `/reload`. | It stays where you put it. |
| D3 | *Settings → Tracker*: tick **Lock it in place**, try to drag it. | It does not move. Untick: it can be dragged again. |
| D4 | Move **Tracker scale** to 1.4. | The tracker grows at once. |
| D5 | Click **Reset position**. | It jumps back to the right side of the screen. |
| D6 | Untick **Show the tracker**, then tick it. | It disappears and comes back. |
| D7 | Right-click the tracker. | The main window opens on the tracked profession's tab. |
| D8 | *Settings → Tracker → Profession to track*: pick Skinning. | The tracker switches to Skinning: `Go to <zone>`, mob names in their colours, `move on at ...`. Opening the Jewelcrafting tab in the window switches it back. |
| D9 | Main settings page, **Features**: untick **Tracker**, then tick it. | It disappears and comes back. |

### E. Commands

| ID | How | Expected |
|---|---|---|
| E1 | `/fprof rate 1`, `/fprof rate 2`, `/fprof rate 3`. | `x1`, then `x2`. The third says the rate can be 1 or 2 and stays x2. (auto) |
| E2 | `/fprof target 300`, `/fprof target rank`, `/fprof target 999`. | `300`, then `your rank's cap`. The third shows the usage line and changes nothing. (auto) |
| E3 | `/fprof faction horde`, then `/fprof faction auto`. | `Horde (chosen)`, then `<yours> (yours)`. (auto) |
| E4 | `/fprof materials gathered`, then `/fprof materials ah`. | `Gathered only`, then `Buy or gather`. (auto) |
| E5 | `/fprof drops` twice. | `recipes from drops: used`, then `not used`. (auto) |
| E6 | `/fprof path`, then `/fprof path skin`. | Chat: your tracked profession's first steps (`1. Make ...`, `Train ...`), then Skinning's best zone lines. (auto) |
| E7 | `/fprof tracker hide`, `show`, `lock`, `unlock`, `reset`. | Each works and prints one status line. (auto) |
| E8 | With the settings page open, type `/fprof rate 1`. | The rate dropdown on the open page shows `x1` at once. Set it back. |

---

## Phase 1 - detecting your professions

| ID | How | Expected |
|---|---|---|
| F1 | Open the character sheet's **Skills** tab and collapse **Professions** and **Secondary Skills**. `/reload`, `/fprof`. | The profession tabs are still all there, and the Skills tab headers are still collapsed afterwards. (auto) |
| F2 | Open the Jewelcrafting tab. | Title `Jewelcrafting  <skill> / <max>  <rank>` with your real numbers. |
| F3 | Open your Jewelcrafting window (the game's own), close it, look at the tab's grey second summary line. | Before: it asks you to open your Jewelcrafting window. After: it no longer does. Recipes you know now count even if they come from drops. (auto) |
| F4 | Craft something that gives a skill-up. | Within a second the title, the path's first step and the tracker move up by 2. (auto) |
| F5 | **realm** Open your Jewelcrafting window and compare three recipes' colours with the path: the first step's recipe, and two from **Other recipes at ...** in its detail. | The colours match (orange, yellow, green, grey). A mismatch means this realm's thresholds differ from its own client files; tell me the recipe and your skill. |

---

## Phase 2 - Jewelcrafting end to end

### G. The path

| ID | How | Expected |
|---|---|---|
| G1 | Jewelcrafting tab, **Path**. | Left: steps like `Make 9 x Bronze Setting` in the recipe's colour, with `from - to` on the right; steps run back to back from your skill to the target. Summary: `To <target> at x2: about N crafts, <cost>`, and `(some prices estimated)` until you scan the Auction House. |
| G2 | Click the first step. | Right: the recipe name, its orange/yellow/green/grey skills, `Make N, skill a to b (x2 per skill-up)`, cost, **Materials for this step** (each with have / need, green or red), **How to learn it** (green "from a trainer" or similar, then the source), and **Other recipes at a** with cost per point. |
| G3 | Hover a material row. Shift-click it with chat open. | The item tooltip plus where it comes from (vendor, gathered, crafted, Auction House). Shift-click puts the item link in chat. |
| G4 | **realm** Pick a step that says `Trainer: ... at skill X`. Visit your Jewelcrafting trainer. | The trainer sells it, at about that skill and price. |
| G5 | Set **Guides stop at** to 450. | Blue **Train Journeyman/Expert/...** rows at 75, 150, 225, 300, 375 (from your current rank on). Clicking one shows the level it needs (red if you are below it), its cost, and the nearest trainers for your faction: `Name <title> - Zone (x, y)`, `in your zone` first. (auto) |
| G6 | **realm** Go to the first trainer listed in G5, using the coordinates. | A Jewelcrafting trainer is there and teaches that rank at that level. |
| G7 | If you know a recipe from a drop: open your Jewelcrafting window once, then look at the path. | That recipe can now appear in the path (it counts as known). |
| G8 | Tick **Use recipes that only drop** in the settings. | The path may change to use drop recipes; their **How to learn it** says `World drop ... try the Auction House` or names the dropping creature. Untick it again. (auto) |

### H. Shopping list, bank and tooltips

| ID | How | Expected |
|---|---|---|
| H1 | Jewelcrafting tab, **Shopping list**. | Every material of the whole path with `have / need`, red until you have enough. Summary: `N materials, M still to get, about <cost> more`, then `Counts your bags. Visit your bank once so its contents count too.` |
| H2 | Visit your bank, close it, open the shopping list again. | The counts include your bank now, and the note says `as of your last visit`. (auto) |
| H3 | Click a material. | Right: where it comes from, and **Used in these steps** with amounts. |
| H4 | Hover a material from the list in your bags (or on a vendor, or in the Auction House). | One extra line: `Needed for your Jewelcrafting path: N (you have M)`. It does not appear twice. (auto) |
| H5 | Hover an unrelated item (your hearthstone). | No extra line. (auto) |
| H6 | Main settings, **Features**: untick **Tooltips**. Hover the material again. | No extra line. Tick it again. |

### I. Auction House prices

| ID | How | Expected |
|---|---|---|
| I1 | Open the Auction House. | A **FycoProf: prices** button near the top-right of the Auction House window. It does not cover the close button. |
| I2 | Click it. | `full Auction House scan started...`, a short pause (the game may stutter for a second), then `Auction House scan done: N prices saved.` (auto) |
| I3 | Open the Jewelcrafting path. | Fewer `(price estimated)` marks; material details show `Auction House: <price> each (x min ago)`. The path may change to cheaper recipes. (auto) |
| I4 | Click the button again at once. | `a full scan is allowed once every 15 minutes, and not yet.`, then `scanning N materials...` and it scans just your path's materials. (auto) |
| I5 | *Settings → Auction House*. | The status line shows how many prices are saved and how old the newest is. **Forget saved prices** empties it. |
| I6 | Type `/fprof scan` away from the Auction House. | `open the Auction House first.` (auto) |

---

## Phase 3 - every crafting profession

| ID | How | Expected |
|---|---|---|
| J1 | **All professions** tab. | 14 professions on the left, a green `*` on the ones you have. Jewelcrafting selected; right side shows its guide from your skill. |
| J2 | Click each crafting profession you do not have (Alchemy, Blacksmithing, Enchanting, Engineering, Inscription, Leatherworking, Tailoring). | Each shows `(not learned: a preview from skill 1)` and a path from 1 to 75; **Path**, **Shopping list** (and **Extras** for Enchanting and Inscription) all show rows. No errors. (auto) |
| J3 | In the browser, set the target to 450 and click through the same professions. | Each path reaches 450 with a **Train** row at every cap. First Aid stops at 410: its last recipe (Heavy Frostweave Bandage) only drops, and the row says `No usable recipe from here`; its detail explains what to do. (auto) |
| J4 | **realm** On a character with another crafting profession, open its tab and repeat F5 (colours) and G4 (a trainer recipe). | Same as F5 and G4. |

---

## Phase 4 - gathering

### K. Skinning

| ID | How | Expected |
|---|---|---|
| K1 | Skinning tab, **Best zones**. | A ranked list of zones with `(mobs lo-hi)`, red when the mobs are well above your level, and a score. The other faction's home zones are marked `(Alliance land)` / `(Horde land)` and ranked low. Summary: `Best now: <zone>. Move on at <skill>.` |
| K2 | Click the top zone. | Right: its skinnable mobs in colour (orange, yellow, green, grey for your skill), their level, the skill they need and how many spawn; then `Move on at N to <next zone>`. |
| K3 | **Mob levels** button. | Mob level 5 to 80 with the skill each needs, coloured for your skill; right side explains the formula (1 up to level 10, (level-10) x 10 for 11-20, level x 5 above). (auto) |
| K4 | **realm** Skin a mob the list shows orange. Then one it shows grey. | The orange one gives a skill-up (+2). The grey one never does. |
| K5 | If your Skinning is at its cap (e.g. 75/75): look at the tab. | A blue `Train <rank> - you are at your cap` row first; clicking it lists the level and nearest trainers. The tracker says `Train ...` too. (auto) |

### L. Mining and Herbalism (on a character that has them, or in the browser)

| ID | How | Expected |
|---|---|---|
| L1 | Mining tab (or browser → Mining), **Best zones** at your skill. | Zones for your faction with the right ore: copper zones at 1, Outland around 300, Northrend from 350. |
| L2 | Click a zone. | Its nodes coloured for your skill, with the skill each needs and a spawn count; `Move on at`. |
| L3 | **All nodes**. | Every vein from Copper (1) to Titanium (450), coloured; clicking one lists the zones where it spawns, most first. |
| L4 | **Smelting** (Mining only). | Every smelting recipe, coloured for your skill; clicking one shows its thresholds and ore. |
| L5 | Browser → Herbalism. | Same as L1-L3 for herbs (Peacebloom 1 to Frost Lotus 450). |
| L6 | **realm** Gather a node the list shows yellow, several times. | About three in four give a skill-up (+2). |

---

## Phase 5 - secondary professions

| ID | How | Expected |
|---|---|---|
| M1 | Fishing tab. | Summary: `Skill-up chance per catch: N% (about M catches per skill-up, x2 points).` and the highest zone where nothing gets away. List: fishing zones by required skill, green (you catch everything), yellow (some get away, with %) or red. (auto) |
| M2 | Click a zone. | Its required skill, your catch chance there, and its common catches with icons. |
| M3 | **realm** Fish a while in a green zone at skill 75+. | Skill-ups come about as often as the summary says. |
| M4 | Cooking tab and First Aid tab. | Paths like Jewelcrafting's (Cooking reaches 450; First Aid stops at 410, see J3). (auto) |

---

## Phase 6 - extras

| ID | How | Expected |
|---|---|---|
| N1 | Jewelcrafting tab, **Extras**. | First row **Dalaran dailies**: the quests that give Dalaran Jewelcrafter's Tokens and everything the tokens buy, with token prices. Then **Prospecting**: every ore. (auto) |
| N2 | Click Copper Ore (and a Northrend ore). | The gems it can give, with the chance per prospect. (auto) |
| N3 | Browser → Inscription → **Extras**. | **Milling**: every herb; clicking one lists its pigments and chances. |
| N4 | Browser → Enchanting → **Extras**. | **Disenchanting**: every enchanting material; clicking Strange Dust lists green items level 5-15 or so, and so on. (auto) |
| N5 | **realm** Prospect 5 Copper Ore a few times. | Gems from N2's list, roughly in those proportions. |

---

## Map pins (0.10.0)

Best done on your skinner in Ashenvale (or any zone with mobs you can skin).

| ID | How | Expected |
|---|---|---|
| O1 | Open the world map (Mapster is fine) on the zone you are in. | Small icons with a coloured square behind them: pelts for skinnable mobs, ore or herb icons for nodes. Only things that still give you skill-ups: orange, yellow or green squares, nothing grey. (auto) |
| O2 | Hover a pin. | Tooltip: the mob or node name, a coloured line `level 18-19, needs Skinning 80` (or `needs Mining 65`), `FycoProfessions - a spawn point`. |
| O3 | Scale or move the map with Mapster, and switch Mapster's mini-map mode if you use it. | The pins stay on the same spots of the map. |
| O4 | Look at another zone on the world map, then a continent. | The other zone shows its own pins; the continent shows none. (auto) |
| O5 | Close the map and look at the minimap. | The same kind of pins around you, moving as you walk, hidden past the minimap's edge. Walk onto a pin: it sits under your arrow. (auto) |
| O6 | Zoom the minimap in and out. | The pins spread out and draw together with the map; none leave the circle. (auto) |
| O7 | If you use a rotating minimap (Interface → Display → Rotate Minimap): turn around. | The pins turn with the map and stay on the right spots. |
| O8 | Skinning tab → **Best zones** → click your zone → click a mob on the right. | It gets a blue `[pinned]`; with **Automatic** off in the settings, only pinned mobs show. Click it again to unpin. (auto) |
| O9 | `/fprof pins skin 20 22`. | The maps now show every skinnable mob of levels 20 to 22 in the zone, whatever your skill (red ones too). `/fprof pins skin auto` goes back. (auto) |
| O10 | *Settings → FycoProfessions → Map pins*. | Checkboxes: world map, minimap, automatic, mining, herbs, skinnable mobs; **Clear hand-picked pins**; sliders for the skinning level range and the two pin sizes. Every change shows on the maps at once. Nothing cut off on the right (C0). |
| O11 | `/fprof pins world`, `/fprof pins minimap`, then `/fprof pins` (and the **Map pins** checkbox under **Features**). | Each switches its pins off (and on again the second time). (auto) |
| O12 | Enter a dungeon. | No pins on the minimap inside. (auto) |
| O14 | `/fprof pins debug` (map closed). | Chat: `map file Tanaris` (your zone's map name), `your zone: 440 (Tanaris)`, your position, how many pins there are here and how many are drawn, and the switches. If pins still do not show, paste me these lines. (auto) |
| O13 | **realm** Walk to a few pins. | A mob or node of that kind spawns at or near each (mobs wander, and a node may be taken or not spawned right now). |

---

## Automated tests

`py -3.11 tests/run_tests.py` (needs `pip install lupa`) loads the real addon,
with all its generated data, into Lua 5.1 against the mock client. 49 tests,
among them:

| Test | Covers |
|---|---|
| `loads_and_logs_in`, `settings_defaults`, `rate_*`, `target_*`, `faction_*`, `materials_*` | A, C, E |
| `window_tabs_and_status`, `options_panels_build_and_refresh`, `help_lists_every_command` | B, C1, A3 |
| `tracker_*` | D, E7 |
| `detects_professions_and_tabs`, `collapsed_headers_are_read_and_restored`, `skill_up_rescans_and_recomputes`, `known_recipes_come_from_the_trade_skill_window` | F |
| `expanding_headers_does_not_loop` | expanding a collapsed skill or reputation header (which fires a change event) does not make the addon re-read forever |
| `recipe_colours_and_chances` | the colour model (Delicate Copper Wire 1/20/35/50) |
| `jewelcrafting_path_from_1`, `rate_changes_the_path`, `trainer_checkpoints_and_nearest_trainer` | G1, C3, G5 |
| `faction_decides_vendor_recipes`, `reputation_recipes_need_the_standing`, `drop_recipes_only_when_allowed` | which recipes a path may use |
| `shopping_list_counts_bags_and_bank`, `tooltip_line_on_reagents` | H |
| `auction_house_full_scan`, `scan_needs_the_auction_house` | I |
| `craft_view_modes_render`, `path_to_chat_is_plain` | G, H, N views; no raw `|` in chat |
| `every_crafting_profession_to_450`, `all_professions_browser_previews` | J (every crafting profession at x1 and x2) |
| `skinning_skill_formula`, `gathering_zones_rank_and_move_on`, `gathering_views_and_tracker` | K, L |
| `fishing_model_and_view` | M |
| `extras_data_and_views` | N |
| `every_path_computes_quickly` | two full 1-450 paths well under a second |

What the automated suite cannot tell: how the frames look, whether the real
client's API behaves exactly like the mock, and whether this realm's rules
match the stock data. That is what the **realm** rows above are for.
