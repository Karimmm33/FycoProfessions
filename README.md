# FycoProfessions

A profession leveling guide for **World of Warcraft 3.3.5a** (Wrath of the
Lich King), made for Whitemane's **Frostmourne Rebuffed** realm, where every
skill-up gives 2 points instead of 1.

It is a sister of [FycoPvE](https://github.com/Karimmm33/FycoPvE) and
[FycoPvP](https://github.com/Karimmm33/FycoPvP).

> **Status: 0.1.0, the foundation.** The window, settings and tracker work.
> The guides themselves arrive phase by phase (see *Roadmap*).

## What it will do

- Read your professions and skill, and start every guide from where you are.
- **Crafting** (Alchemy, Blacksmithing, Enchanting, Engineering, Inscription,
  Jewelcrafting, Leatherworking, Tailoring, Cooking, First Aid): the cheapest
  path to your target, step by step (`make 12 x Item until 185`), recomputed
  as your skill rises. Worked out from this realm's own recipe data and your
  chosen skill-up rate, not copied from a website.
- **Shopping list** for the whole path, minus what is already in your bags
  and bank.
- **Trainer checkpoints** at 75, 150, 225, 300, 375 and 450, with the level
  each rank needs and the nearest trainer for your faction.
- **Gathering** (Mining, Herbalism, Skinning) and **Fishing**: the best zones
  for your skill, and when to move on.
- A small **tracker** on screen with the current step, and tooltip lines on
  reagents (`Needed for your Jewelcrafting path: 14`).

## Settings

Everything is under *Interface → AddOns → FycoProfessions*, or the window's
**Settings** button.

| Setting | |
|---|---|
| Skill points per skill-up | x1 (stock) or x2 (this realm). Every path is worked out for the rate chosen. |
| Guides stop at | Your rank's cap, or a skill from 75 to 450. |
| Faction | Whose trainers and vendors to use. Auto = this character's. Saved per character. |
| Materials | Buy or gather, or gathered materials only. |
| Tracker | Show, lock, scale, reset position. |
| Window | Minimap button, login greeting, window scale. |

## Commands

Everything below is also in the settings UI.

| Command | |
|---|---|
| `/fprof` | open or close the window |
| `/fprof options` | open the settings |
| `/fprof rate [1 or 2]` | show or set skill points per skill-up |
| `/fprof target [rank or 1-450]` | show or set where guides stop |
| `/fprof faction [auto, alliance, horde]` | whose trainers and vendors to use |
| `/fprof materials [ah or gathered]` | allow buying materials, or gathered only |
| `/fprof tracker [show, hide, lock, unlock, reset]` | the step tracker |
| `/fprof minimap` | show or hide the minimap button |
| `/fprof debug` | toggle debug output |

## About the data

Recipes, skill thresholds and reagents come from this realm's own client
files (`rebuffed.mpq`). Trainers, vendors, drops and spawns come from the
[AzerothCore](https://www.azerothcore.org/) 3.3.5 database, which describes
the stock game. This realm can differ, so when the game disagrees with
FycoProfessions, the game is right.

## Roadmap

0. Foundation: window, settings, tracker, tests. *(this release)*
1. Detecting your professions and skill.
2. Jewelcrafting end to end, with an optional Auction House price scan.
3. Every crafting profession.
4. Gathering: Skinning, then Mining and Herbalism.
5. Cooking, First Aid and Fishing.
6. Extras: prospecting, milling, disenchanting, Dalaran jewelcrafting dailies.

## Install

Download the zip from the latest release and extract it into
`World of Warcraft\Interface\AddOns`, so you get
`Interface\AddOns\FycoProfessions\FycoProfessions.toc`.

## License

MIT
