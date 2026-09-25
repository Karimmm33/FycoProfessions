# AGENTS.md

Canonical instruction file for AI agents working in this repository.

Follow the shared repo-local rules first:

@docs/conventions/agent-global-rules.md

Then the rules specific to this addon. They are not optional:

@docs/conventions/addon-rules.md

The backend and frontend style guides do not apply here — this is Lua 5.1
against the WoW 3.3.5a client API, plus Python build scripts.

---

## What this project is

A profession leveling guide for WoW 3.3.5a (Interface 30300), played on
Whitemane's Frostmourne Rebuffed realm, where each skill-up gives 2 points.
A sister of FycoPvE (https://github.com/Karimmm33/FycoPvE) and FycoPvP, built
on the same core, window, settings and test harness. Do not change those two
repositories from here.

It detects the character's professions and skill, and for each one shows the
path from the current skill to a target: the cheapest recipes step by step
for crafting professions, the best zones and nodes for gathering, with a
shopping list, trainer checkpoints and a small on-screen tracker.

## The development loop

**This project is the source of truth. The copy inside the WoW client is
disposable.**

```powershell
# 1. edit here, in D:\Projects\FycoProfessions
# 2. check every Lua file, then run the automated suite (pip install lupa, once)
python scripts\luacheck.py Core.lua Widgets.lua Data\Constants.lua Modules\Browser.lua Modules\Options.lua Modules\Tracker.lua Modules\Window.lua
python tests\run_tests.py
# 3. push it into the client and test in game, following docs\TESTING.md
.\scripts\deploy.ps1          # -WhatIf to preview
#    then /reload in game
```

`deploy.ps1` **mirrors** `Data\` and `Modules\`, so anything edited in the
client folder is overwritten. `.git`, `docs\`, `scripts\`, `.cache\` and the
agent files are never deployed: the client folder looks exactly like what a
user unzips.

Do not run deploy or package unless Karim asks. Do run luacheck and the test
suite.

## Releasing

```powershell
# bump '## Version:' in FycoProfessions.toc first -- package.ps1 reads it from there
.\scripts\package.ps1
gh release create v0.1.0 .\dist\FycoProfessions-0.1.0.zip --title "FycoProfessions 0.1.0" --notes-file notes.md
```

Never point anyone at GitHub's "Code -> Download ZIP": it extracts as
`FycoProfessions-main`, which WoW does not recognise.

## Pushing

Plain `git push` hangs on this machine (Git Credential Manager waits on an
invisible prompt). Push with:

```
GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c "credential.helper=!gh auth git-credential" push
```

## Before telling Karim something is done

See the checklist at the end of `docs/conventions/addon-rules.md`.
