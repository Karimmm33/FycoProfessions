# FycoProfessions

A profession leveling guide for **World of Warcraft 3.3.5a** (Wrath of the
Lich King), made for Whitemane's **Frostmourne Rebuffed** realm, where every
skill-up gives 2 points instead of 1.

It is a sister of [FycoPvE](https://github.com/Karimmm33/FycoPvE) and
[FycoPvP](https://github.com/Karimmm33/FycoPvP).

## Features

| | |
|---|---|
| **Your professions** | Read from the game: skill and max skill for every profession you have, one window tab each. Recipes you already know are read whenever you open your profession window. |
| **Crafting path** | For Alchemy, Blacksmithing, Enchanting, Engineering, Inscription, Jewelcrafting, Leatherworking, Tailoring, Cooking and First Aid: the cheapest path from your skill to your target, step by step (`Make 12 x Bronze Setting, 50 to 74`), recomputed as your skill rises. Worked out from this realm's own recipe data and your skill-up rate, not copied from a website. |
| **Only recipes you can get** | Recipes you know, trainer recipes, vendor recipes for your faction (with cost and reputation), quest recipes, and, if you allow it, drops. Each step says how to learn its recipe. |
| **Trainer checkpoints** | The path stops at 75, 150, 225, 300, 375 and 450 with the level each rank needs and the nearest trainers for your faction, with coordinates. |
| **Shopping list** | Every material for the whole path, minus what is in your bags and your bank. |
| **Prices** | Vendor prices, your own Auction House scans (one click on the Auction House window), or the cost of crafting a material yourself. Anything else is a marked estimate. |
| **Gathering** | Mining, Herbalism, Skinning: the best zones for your skill (not the other faction's home zones), which nodes or mobs still give skill-ups, and the skill at which to move on. |
| **Fishing** | Every fishing zone by required skill, your catch chance there, and how many catches a skill-up takes. |
| **Extras** | Jewelcrafting: prospecting results and the Dalaran daily tokens. Inscription: milling. Enchanting: where each material disenchants from. Mining: smelting. |
| **All professions** | Browse any profession, even one you do not have, as a preview from skill 1. |
| **Tracker** | A small movable frame with your current step and its materials (have / need). |
| **Tooltips** | `Needed for your Jewelcrafting path: 14 (you have 3)` on every material your paths use. |

## How the path is worked out

The same rules the server uses (AzerothCore, the stock 3.3.5 core):

- A recipe is **orange** from the skill you can learn it at, **yellow**,
  **green**, then **grey**, at the skills in this realm's client files.
- A craft gives a skill-up with a chance of 100% (orange), 75% (yellow),
  25% (green) or 0% (grey).
- Each skill-up gives the points you set (x2 on this realm).

The cheapest mix of recipes is found for every skill point, and consecutive
points on the same recipe become one step.

## Settings

Everything is under *Interface → AddOns → FycoProfessions*, or the window's
**Settings** button.

| Setting | |
|---|---|
| Skill points per skill-up | x1 (stock) or x2 (this realm). Every path is worked out for the rate chosen. |
| Guides stop at | Your rank's cap, or a skill from 75 to 450. |
| Faction | Whose trainers and vendors to use. Auto = this character's. Saved per character. |
| Materials | Buy or gather, or gathered materials only. |
| Use recipes that only drop | Off by default. |
| Tracker | Show, lock, scale, reset position, which profession to follow. |
| Auction House | Full scan, shopping-list scan, forget prices. |
| Window | Minimap button, login greeting, window scale; Tracker and Tooltips on or off. |

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
| `/fprof drops` | also use recipes that only drop, on or off |
| `/fprof path [profession]` | the next steps, in chat |
| `/fprof scan [list]` | scan Auction House prices (with the Auction House open) |
| `/fprof tracker [show, hide, lock, unlock, reset]` | the step tracker |
| `/fprof minimap` | show or hide the minimap button |
| `/fprof debug` | toggle debug output |

## About the data

Recipes, skill thresholds, reagents, zone maps and node requirements come
from this realm's own client files (`rebuffed.mpq`). Trainers, vendors,
drops, quests and spawns come from the
[AzerothCore](https://www.azerothcore.org/) 3.3.5 database, which describes
the stock game. This realm can differ, so when the game disagrees with
FycoProfessions, the game is right.

## Install

Download the zip from the latest release and extract it into
`World of Warcraft\Interface\AddOns`, so you get
`Interface\AddOns\FycoProfessions\FycoProfessions.toc`.

## License

MIT
