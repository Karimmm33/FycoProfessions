# FycoProfessions — rules for working in this addon

WoW 3.3.5a (Interface 30300). Read this before changing anything here. Most
of these rules were learned the hard way in FycoPvP and FycoPvE, the sister
addons, whose structure this one copies.

---

## HARD RULE 1 — never hand-place an options widget

The Interface Options content area is roughly 500 x 500 pixels and **does not
clip its children**. A widget placed past the bottom renders outside the
frame, over the game world.

- Never write a literal Y offset. Use the layout cursor in
  `Modules/Options.lua` (`Column:Check`, `:Slider`, `:Title`, `:Note`,
  `:Button`, `:Buttons`, `:Dropdown`). Each advances by its real height.
- Every options panel is a scroll frame (`MakePanel()`), sized by `Finish()`.
- Two columns maximum, at `COL1 = 8` and `COL2 = 250`, each 230 wide.
- Modules add settings pages through `ns:RegisterOptions(key, title, order,
  build)`; `build(L, R)` gets the two columns. Do not add pages by editing
  `Options.lua`.

The main window's tabs are fixed-size panes; anything that can grow (a list,
a detail text) goes in a scroll frame there too.

## HARD RULE 2 — write Lua with the Write/Edit tools

Bash heredocs and `python -c` in this environment silently eat backslashes.
`"Interface\\Icons\\X"` arrives as `"Interface\Icons\X"`, an invalid escape,
and the addon refuses to load with no clue why. Author `.lua` (and `.toc`)
with Write/Edit; if a scripted patch is needed, write the script to a file.

## HARD RULE 3 — check every file before saying it is done

```
py -3.11 scripts/luacheck.py Core.lua Widgets.lua Sources.lua Data/*.lua Modules/*.lua
```

ASCII only (the client renders anything else as mojibake), valid escapes,
balanced blocks, no orphaned ALL_CAPS constants. It is a lexer, not a
parser: a clean run is not proof the file parses, and never proof it runs.

Then run the automated suite, which loads the real addon in Lua 5.1 against
a mock client (`tests/wowmock.lua`) and drives it:

```
py -3.11 -m pip install lupa    # once (already done on Karim's machine)
py -3.11 tests/run_tests.py
```

Every feature gets tests there, and every in-game check goes in
`docs/TESTING.md` with an ID. A new frame method the mock does not model is
listed at the end of a run; confirm it exists in 3.3.5a.

## HARD RULE 4 — generated data is never edited by hand

Files under `Data/` other than `Constants.lua` are written by
`scripts/build_data.py`, and the next build overwrites them. To fix a record,
fix the build. `scripts/ref/*.json` is written by `scripts/extract_refs.py`
from the realm client and committed.

## HARD RULE 5 — grep for orphaned references after deleting anything

Lua resolves a deleted `local` to a nil global. That parses perfectly and only
fails at runtime. After removing or renaming anything:

```
grep -rn "OLD_NAME" --include=*.lua .     # expect zero hits
```

## HARD RULE 6 — the skill-up rate is a setting, never a constant

This realm gives 2 skill points per skill-up (confirmed in game); the stock
game gives 1. The chance of a skill-up per recipe colour is the stock one
(orange 100%, yellow 75%, green 25%, grey 0%). Every path, craft count and
shopping list is computed from `ns:Rate()`, and nothing may hard-code 2.

---

## Architecture

`Core.lua` owns everything shared, and modules use it rather than duplicate it:

- **one** event dispatcher — `ns:On(event, fn)`
- **one** 10 Hz ticker — `ns:OnTick(fn)`, inside a pcall
- **one** message bus — `ns:Subscribe(msg, fn)` / `ns:Fire(msg, ...)`.
  `SettingChanged(section, key, value)` is the one every module listens to
  (section `"char"` for per-character settings).
- settings — `ns:Get(section, key)` / `ns:Set(section, key, value)`, with
  every default in `ns.Defaults`; per-character ones through
  `ns:GetChar(key)` / `ns:SetChar(key, value)` and `ns.CharDefaults`. Never
  read `FycoProfessionsDB` fields directly for a setting; the default would
  be missed.
- the guide settings, validated — `ns:Rate()`, `ns:Target()`,
  `ns:Faction()`, `ns:Materials()`, and `ns:GuideText()` for display.
- modules — `ns:Module(name, order)` with an `OnLoad`, run in `order` inside a
  pcall. `ns:Enabled(name)` is checked at use time.
- the window — `ns:AddTab(key, label, order, build, onShow)`; content is built
  the first time the tab opens. `ns:ShowTab(key, shown)` hides the tabs of
  professions the character does not have.
- the tracker — guide modules push `ns:SetTrackerLines(title, lines)`.

The modules, in load order:

| Module | Owns |
|---|---|
| `Window` | the window shell, tabs, minimap button |
| `Professions` | reading skills, known recipes, reputations, the bank; one tab per profession |
| `Engine` | recipe colours and chances, which recipes you can use, material costs, the path solver, shopping lists |
| `Prices` | Auction House scans and saved prices |
| `Views` | `ns:CreateView`, the crafting view (Path, Shopping list, Extras), trainers, `/fprof path` |
| `Gather` | gathering and fishing models and views |
| `Browser` | the All professions tab |
| `Tracker` | the on-screen step frame; asks `ns.TrackerProviders[kind]` for its lines |
| `Tooltip` | "Needed for your ... path" lines |
| `Options` | the settings pages |

Messages: `ProfessionsChanged` (skills, known recipes, reputation),
`PricesChanged`, `GuideChanged` (every path is invalid; views and the
tracker redraw), `BagsChanged`.

Adding a feature module: new file in `Modules/`, add it to
`FycoProfessions.toc`, add its switch to `moduleDefaults` in `Core.lua` and
the Features list in `Options.lua`, register a tab and/or a settings page,
document it in `README.md`.

## The data pipeline

```
rebuffed.mpq ── scripts/extract_refs.py ──> scripts/ref/*.json ──┐
AzerothCore world DB (.cache/acore/) ────────────────────────────┼─ scripts/build_data.py ─> Data/Recipes.lua,
                                                                  ┘   Data/Items.lua, Data/World.lua, Data/Extras.lua
```

- Spell.dbc columns were verified against known spells (see the constants
  at the top of `extract_refs.py`). SkillLineAbility gives orange-from (7),
  grey (10) and yellow (11); green is (yellow + grey) / 2, as the server does.
- SkillLineAbility's min skill is 1 for most learned recipes; the build
  raises it to the trainer's or recipe item's required skill.
- AzerothCore moved most trainers to `trainer` / `trainer_spell` /
  `creature_default_trainer`, listing "teach" spells; `teaches.json` maps
  each to the recipe or rank it grants. `npc_trainer` is still read too.
- Spawn rows mostly have no zone; zones and map coordinates come from the
  spawn position and the realm's WorldMapArea bounds. AreaTable's faction
  group marks each side's home zones.
- Generated files wrap every table in its own function (Lua 5.1 constant
  limit), each starting with `;` so Lua does not read it as a call.

## 3.3.5a facts that matter here

- No C_Timer. Everything runs off events and the shared ticker.
- `GetItemInfo` returns nil for items the client has not cached; use our own
  data for names and quality, and `GetItemIcon` for icons.
- `OnTooltipSetItem` can fire more than once per item; guard with a flag
  cleared in `OnTooltipCleared`.
- Dropdowns (`UIDropDownMenuTemplate`), edit boxes (`InputBoxTemplate`) and
  faux scroll frames need global names.
- Chat text must not contain a raw `|` (it starts an escape such as `|t`).
  Write `||` or words. Anything sent with `SendChatMessage` must contain no
  `|` at all.

## Honesty in the UI

Recipe data comes from this realm's own client files. Trainers, vendors,
drops and spawns come from the AzerothCore database, which describes the
stock 3.3.5 game. The UI says so where sources are shown, and never presents
a guess as fact: a vendor whose location is unknown shows no location rather
than a wrong one, and a recipe the database does not know says
"source unknown (realm-specific)".

## Before telling Karim it is done

1. `scripts/luacheck.py` is clean over every `.lua` file.
2. New commands are in `Core.lua`'s slash handler *and* its help output
   (the test `help_lists_every_command` enforces this).
3. New modules are in `FycoProfessions.toc`, `moduleDefaults` and the
   options list.
4. Every new setting is reachable from the options UI, not only a command.
5. `README.md` covers any new feature and command.
6. Say what was actually verified. A static check is not a runtime check.
