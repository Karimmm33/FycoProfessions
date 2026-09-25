# FycoProfessions in-game testing sheet

> **Status (0.1.0, phase 0): not yet tested in game.**

Work through the sections in order. For each test, do exactly what the **How**
column says, compare with **Expected**, and report back by ID, for example:

> A1 ok, A2 ok, C3 FAIL - the Target dropdown shows nothing, screenshot attached

Anything marked **auto** has already been checked by the automated test suite
(`python tests/run_tests.py`, see the bottom of this file), so for those you
only need to confirm that the game agrees with the mock. If you see red error
text anywhere, copy it into your report exactly.

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
4. Log in on a character with at least one profession.

To report a Lua error with its full text, you can run `/console scriptErrors 1`
once and `/reload`. Errors then pop up in a window you can screenshot.

---

## Phase 0 — foundation

### A. Loading

| ID | How | Expected |
|---|---|---|
| A1 | Log in and look at chat. | One line: `FycoProfessions v0.1.0 - x2, target: your rank's cap, <your faction>. /fprof to open.` (auto) |
| A2 | Look at the edge of the minimap. | A round button with a note icon, next to FycoPvE's book button if that addon is on. |
| A3 | Type `/fprof help`. | A list of nine commands, with no red text. (auto) |
| A4 | Type `/reload`. | The same greeting again, and no errors. |

### B. Main window

| ID | How | Expected |
|---|---|---|
| B1 | Type `/fprof`. | A window titled **FycoProfessions v0.1.0**. Under the title, grey text `Guide: x2, target: your rank's cap, <faction>`. One tab button, **All professions**, and a **Settings** button top-right. |
| B2 | Look at the **All professions** tab. | A list of 14 professions with icons on the left: Alchemy to Tailoring, then Mining, Herbalism, Skinning, Cooking, First Aid, Fishing. Jewelcrafting is highlighted. |
| B3 | Click **Skinning**, then **Fishing**, then **Cooking**. | The right side changes each time: the name, `(secondary)` for Fishing and Cooking, a one-line description, and six trainer ranks from Apprentice (1 to 75, level 5) to Grand Master (375 to 450, level 65), marked as stock levels. Last line: the guide is not built yet. Nothing overlaps or runs off the window. |
| B4 | Drag the window by its title area, close it with X, then `/fprof` again. | It reopens where you left it. |
| B5 | With the window open, press **Escape**. | It closes. |
| B6 | Left-click the minimap button, then right-click it. | Left opens and closes the window. Right opens *Interface → AddOns → FycoProfessions*. |
| B7 | Drag the minimap button around the minimap, then `/reload`. | It slides along the minimap's edge and stays where you left it. |
| B8 | Hover the minimap button. | A tooltip: `FycoProfessions`, the guide line (`Guide: x2, ...`) and click hints. |

### C. Settings

| ID | How | Expected |
|---|---|---|
| C1 | `/fprof options`. | *Interface → AddOns → FycoProfessions* opens. Left: **Leveling guide** with four dropdowns (Skill points per skill-up, Guides stop at, Faction, Materials), each with a grey note under it. Right: **Window**, **Features**, **About the data**. Nothing runs past the bottom of the panel. |
| C2 | Open **Skill points per skill-up**. | Two choices: `x1 (stock)` and `x2`. `x2` is ticked. Pick `x1`. |
| C3 | Open the window (`/fprof`). | The grey guide line now says `x1`. Set it back to `x2` in the settings; the window line follows. (auto) |
| C4 | Open **Guides stop at**. | `Your rank's cap`, then `75 (Apprentice)` to `450 (Grand Master)`. Pick `375 (Master)`; the window's guide line says `target: 375`. (auto) |
| C5 | Open **Faction**. | `Auto (<your faction>)`, `Alliance`, `Horde`. Pick the other faction; the window line shows it. Log in on another character: it is back to Auto there. Set it back to Auto. |
| C6 | Open **Materials**. | `Buy or gather` and `Gathered only`. Pick `Gathered only`; the window line ends with `gathered materials only`. Set it back. |
| C7 | Expand FycoProfessions in the left list of the options. | A **Tracker** sub-page. |
| C8 | Change **Window scale** to 1.2. | The window grows at once. Set it back to 1. |
| C9 | Untick **Minimap button**. | The button disappears. Tick it again; it comes back. |
| C10 | `/reload`, then open the settings. | Every choice you left is still set. |

### D. Tracker

| ID | How | Expected |
|---|---|---|
| D1 | After login, look at the right side of the screen. | A small dark frame titled **FycoProfessions** with grey text `No step to track yet.` |
| D2 | Drag it somewhere else, then `/reload`. | It stays where you put it. |
| D3 | *Settings → FycoProfessions → Tracker*: tick **Lock it in place**, then try to drag the tracker. | It does not move. Untick it; it can be dragged again. |
| D4 | Move the **Tracker scale** slider to 1.4. | The tracker grows at once. |
| D5 | Click **Reset position**. | It jumps back to the right side of the screen. |
| D6 | Untick **Show the tracker**. | It disappears. Tick it; it comes back. |
| D7 | Right-click the tracker. | The main window opens. |
| D8 | On the main settings page, under **Features**, untick **Tracker**. | The tracker disappears. Tick it again; it comes back. |

### E. Commands

| ID | How | Expected |
|---|---|---|
| E1 | `/fprof rate 1`, then `/fprof rate 2`, then `/fprof rate 3`. | `skill points per skill-up: x1`, then `x2`. The third says the rate can be 1 or 2, and it stays at x2. (auto) |
| E2 | `/fprof target 300`, then `/fprof target rank`, then `/fprof target 999`. | `guides stop at: 300`, then `your rank's cap`. The third shows the usage line and leaves it unchanged. (auto) |
| E3 | `/fprof faction horde`, then `/fprof faction auto`. | `faction: Horde (chosen)`, then `faction: <yours> (yours)`. (auto) |
| E4 | `/fprof materials gathered`, then `/fprof materials ah`. | `materials: Gathered only`, then `materials: Buy or gather`. (auto) |
| E5 | `/fprof tracker hide`, `/fprof tracker show`, `/fprof tracker lock`, `/fprof tracker unlock`, `/fprof tracker reset`. | The tracker hides, shows, locks and unlocks, and goes back to its default spot. Each prints one status line. (auto) |
| E6 | Open the settings page, then type `/fprof rate 1`. | The rate dropdown on the open page shows `x1` at once. |

---

## Automated tests

`python tests/run_tests.py` loads the real addon into Lua 5.1 against the mock
client and checks, among others:

| Test | Covers |
|---|---|
| `loads_and_logs_in`, `greeting_can_be_turned_off` | A1, A4 |
| `settings_defaults`, `rate_saved_and_validated` | defaults; a saved rate that is not x1 or x2 falls back to x2 |
| `rate_command`, `rate_dropdown_in_options` | C2, C3, E1 |
| `target_command_and_dropdown` | C4, E2 |
| `faction_override_is_per_character` | C5, E3 |
| `materials_command_and_dropdown` | C6, E4 |
| `window_tabs_and_status` | B1, C3; hiding the selected tab never leaves an empty window |
| `browser_selects_every_profession` | B2, B3 |
| `tracker_commands_and_settings`, `tracker_renders_pushed_lines` | D3 to D8, E5 |
| `options_panels_build_and_refresh` | C1, C7; every dropdown shows a value |
| `help_lists_every_command` | A3; every slash command is in the help |
| `slash_everything_without_errors` | no chat line carries a raw `|` |
