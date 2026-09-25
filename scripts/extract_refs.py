"""Pull the client-side tables the data build needs out of the realm's own MPQ.

The server database (AzerothCore) knows trainers, vendors, drops and spawns,
but recipes -- which spell makes which item from which reagents, and at which
skill it turns yellow, green and grey -- live in the CLIENT's DBC files. So do
map, zone and faction names, zone map bounds and node lock requirements.

This reads them from Frostmourne Rebuffed's rebuffed.mpq, not a stock 3.3.5
archive: the realm ships its own SkillLineAbility.dbc and Spell.dbc (about 110
more recipe rows than stock), and those are what the game really uses.

Writes small JSON files to scripts/ref/, which are committed -- so the normal
data build never needs the client, and this only has to be re-run if the
client data changes.

Needs the pure-Python MPQ reader: pip install mpyq

    python scripts/extract_refs.py "D:/Whitemane/Frostmourne/FrostmourneRebuffed/Data/rebuffed.mpq"
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "ref")

# the skill lines this addon guides (Data/Constants.lua ns.Professions)
SKILLS = {171, 164, 333, 202, 773, 755, 165, 197, 186, 182, 393, 185, 129, 356}

# Spell.dbc 3.3.5a column indices, verified against known recipes
# (Delicate Copper Wire 25255, Copper Bracers 2663, the Jewelcrafting ranks)
S_FOCUS = 18                    # RequiresSpellFocus (anvil, forge, fire)
S_REAGENT, S_REAGENT_N = 52, 60 # Reagent[8], ReagentCount[8]
S_EFFECT = 71                   # Effect[3]
S_DIE, S_BASE = 74, 80          # EffectDieSides[3], EffectBasePoints[3]
S_ITEM = 107                    # EffectItemType[3]
S_MISC = 110                    # EffectMiscValue[3]
S_TRIGGER = 116                 # EffectTriggerSpell[3]
EFFECT_LEARN = 36               # learn the trigger spell
S_NAME, S_RANK = 136, 153       # SpellName, Rank (enUS slot)
S_TOTEM_CAT = 222               # TotemCategory[2]
EFFECT_SKILL = 118              # a profession rank spell: misc = skill, base = step - 1


def read_dbc(blob):
    """Return (records, string lookup) for a WDBC blob. Every field is read as
    int32; string fields are offsets into the trailing string block."""
    magic, n, fields, rec_size, _ = struct.unpack_from("<4s4i", blob, 0)
    if magic != b"WDBC":
        raise ValueError("not a WDBC file")
    recs = [struct.unpack_from("<%di" % fields, blob, 20 + i * rec_size) for i in range(n)]
    strings = blob[20 + n * rec_size:]

    def s(off):
        if off <= 0 or off >= len(strings):
            return ""
        end = strings.find(b"\0", off)
        return strings[off:end].decode("utf-8", "replace")

    return recs, s


def as_float(i):
    return struct.unpack("<f", struct.pack("<i", i))[0]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        import mpyq
    except ImportError:
        sys.exit("mpyq is not installed: pip install mpyq")

    archive = mpyq.MPQArchive(sys.argv[1], listfile=False)

    def dbc(name):
        blob = archive.read_file("DBFilesClient\\" + name)
        if blob is None:
            sys.exit("%s is not in %s" % (name, sys.argv[1]))
        return read_dbc(blob)

    os.makedirs(OUT, exist_ok=True)
    out = {}

    # Map.dbc: 0 id, 2 instance type (0 world, 1 dungeon, 2 raid, 3 bg, 4 arena), 5 name
    recs, s = dbc("Map.dbc")
    out["maps"] = {r[0]: {"name": s(r[5]), "type": r[2]} for r in recs}

    # AreaTable.dbc: 0 id, 1 map, 2 parent zone, 11 name, 28 faction group
    # (2 Alliance territory, 4 Horde territory, 0 contested)
    recs, s = dbc("AreaTable.dbc")
    out["areas"] = {r[0]: {"name": s(r[11]), "map": r[1], "zone": r[2], "side": r[28]} for r in recs}

    # Faction.dbc: 0 id, 23 name
    recs, s = dbc("Faction.dbc")
    out["factions"] = {r[0]: s(r[23]) for r in recs}

    # FactionTemplate.dbc: 0 id, 1 faction, 3 own group, 4 friend groups,
    # 5 enemy groups, 6-9 enemy factions, 10-13 friend factions
    # (groups: 1 player, 2 Alliance, 4 Horde, 8 monster)
    recs, _ = dbc("FactionTemplate.dbc")
    out["factiontpl"] = {r[0]: {"own": r[3], "friend": r[4], "enemy": r[5],
                                "enemies": [x for x in r[6:10] if x], "friends": [x for x in r[10:14] if x]}
                         for r in recs}

    # ItemExtendedCost.dbc: 0 id, 1 honor, 2 arena, 4-8 items, 9-13 counts, 14 personal rating
    recs, _ = dbc("ItemExtendedCost.dbc")
    costs = {}
    for r in recs:
        items = [[r[4 + i], r[9 + i]] for i in range(5) if r[4 + i]]
        costs[r[0]] = {"honor": r[1], "arena": r[2], "items": items, "rating": r[14]}
    out["extcost"] = costs

    # WorldMapArea.dbc: 0 id, 1 map, 2 area, 4 left, 5 right, 6 top, 7 bottom
    # (floats; left/right bound world Y, top/bottom bound world X)
    recs, _ = dbc("WorldMapArea.dbc")
    out["wma"] = {r[0]: {"map": r[1], "area": r[2], "left": as_float(r[4]), "right": as_float(r[5]),
                         "top": as_float(r[6]), "bottom": as_float(r[7])} for r in recs if r[2]}

    # Lock.dbc: 0 id, 1-8 type (2 = needs a skill), 9-16 index (lock type:
    # 2 herbalism, 3 mining), 17-24 required skill
    recs, _ = dbc("Lock.dbc")
    locks = {}
    for r in recs:
        for k in range(8):
            if r[1 + k] == 2 and r[9 + k] in (2, 3):
                locks[r[0]] = {"type": r[9 + k], "skill": r[17 + k]}
                break
    out["locks"] = locks

    # TotemCategory.dbc: 0 id, 1 name (tools: Blacksmith Hammer, Runed Copper Rod)
    recs, s = dbc("TotemCategory.dbc")
    out["tools"] = {r[0]: s(r[1]) for r in recs}

    # SpellFocusObject.dbc: 0 id, 1 name (Anvil, Forge, Cooking Fire)
    recs, s = dbc("SpellFocusObject.dbc")
    out["focus"] = {r[0]: s(r[1]) for r in recs}

    # SkillLineAbility.dbc: 0 id, 1 skill, 2 spell, 3 race mask, 4 class mask,
    # 7 min skill (orange from), 9 acquire method (1 = learned with the skill),
    # 10 trivial high (grey from), 11 trivial low (yellow from)
    recs, _ = dbc("SkillLineAbility.dbc")
    abilities = []
    for r in recs:
        if r[1] in SKILLS:
            abilities.append({"skill": r[1], "spell": r[2], "race": r[3], "class": r[4],
                              "min": r[7], "acquire": r[9], "grey": r[10], "yellow": r[11]})
    out["abilities"] = abilities
    wanted = {a["spell"] for a in abilities}

    # Spell.dbc: only the spells above, plus the profession rank spells
    recs, s = dbc("Spell.dbc")
    spells, ranks, learn = {}, {}, {}
    for r in recs:
        effects = r[S_EFFECT:S_EFFECT + 3]
        # trainers list "teach" spells that cast the real one (effect 36)
        for k in range(3):
            if effects[k] == EFFECT_LEARN and r[S_TRIGGER + k]:
                learn[r[0]] = r[S_TRIGGER + k]
        if EFFECT_SKILL in effects:
            k = effects.index(EFFECT_SKILL)
            skill = r[S_MISC + k]
            if skill in SKILLS:
                step = r[S_BASE + k] + 1
                ranks.setdefault(skill, {}).setdefault(step, []).append(r[0])
        if r[0] not in wanted:
            continue
        creates = None
        for k in range(3):
            if r[S_ITEM + k]:
                lo = r[S_BASE + k] + 1
                hi = r[S_BASE + k] + max(1, r[S_DIE + k])
                creates = [r[S_ITEM + k], lo, hi]
                break
        spells[r[0]] = {
            "name": s(r[S_NAME]),
            "reagents": [[r[S_REAGENT + i], r[S_REAGENT_N + i]] for i in range(8) if r[S_REAGENT + i] > 0],
            "creates": creates,
            "effects": [e for e in effects if e],
            "tools": [t for t in r[S_TOTEM_CAT:S_TOTEM_CAT + 2] if t],
            "focus": r[S_FOCUS],
        }
    out["spells"] = spells
    out["ranks"] = ranks
    rank_ids = {sid for steps in ranks.values() for ids in steps.values() for sid in ids}
    out["teaches"] = {t: sid for t, sid in learn.items() if sid in wanted or sid in rank_ids}

    for name, data in out.items():
        path = os.path.join(OUT, name + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        print("wrote %-32s %6d rows" % (os.path.relpath(path), len(data)))


if __name__ == "__main__":
    main()
