"""Build FycoProfessions' data files from their sources.

    python scripts/build_data.py            # uses cached downloads when present
    python scripts/build_data.py --refresh  # re-download everything

Inputs
  scripts/ref/*.json    client tables from the realm's rebuffed.mpq -- recipes,
                        reagents, colour thresholds, zones, locks, factions
                        (see scripts/extract_refs.py)
  AzerothCore world DB  trainers, vendors, loot, quests and spawns, downloaded
                        to .cache/acore/ (git-ignored)

Outputs -- GENERATED, never edit by hand, the next build overwrites them
  Data/Recipes.lua   every recipe per profession, with how to learn it; rank
                     requirements; trainers with their location
  Data/Items.lua     every reagent, product and recipe item: name, quality,
                     prices, and where it comes from
  Data/World.lua     zones, gathering nodes by zone, skinnable mobs by zone,
                     fishing zones
  Data/Extras.lua    prospecting, milling, disenchanting, Dalaran
                     jewelcrafting dailies

The client tables are this realm's own. The database describes the stock
3.3.5 game, and the addon says so wherever it shows a source.
"""
import gzip
import json
import os
import re
import sys
import time
import unicodedata
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
CACHE = os.path.join(ROOT, ".cache")
DATA = os.path.join(ROOT, "Data")
ACORE_URL = "https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/master/data/sql/base/db_world/%s.sql"
ACORE_TABLES = [
    "item_template", "creature_template", "creature", "creature_loot_template",
    "reference_loot_template", "gameobject_template", "gameobject",
    "gameobject_loot_template", "npc_vendor", "quest_template", "npc_trainer",
    "skinning_loot_template", "prospecting_loot_template", "milling_loot_template",
    "disenchant_loot_template", "skill_fishing_base_level", "fishing_loot_template",
    "trainer", "trainer_spell", "creature_default_trainer",
]

# skill line -> key, matching Data/Constants.lua ns.Professions
PROF = {171: "alchemy", 164: "blacksmithing", 333: "enchanting", 202: "engineering",
        773: "inscription", 755: "jewelcrafting", 165: "leatherworking", 197: "tailoring",
        186: "mining", 182: "herbalism", 393: "skinning", 185: "cooking", 129: "firstaid",
        356: "fishing"}
CONTINENTS = {0: "Eastern Kingdoms", 1: "Kalimdor", 530: "Outland", 571: "Northrend"}

REP_RANKS = {3: "Neutral", 4: "Friendly", 5: "Honored", 6: "Revered", 7: "Exalted"}
ALLIANCE_RACES = 1 | 4 | 8 | 64 | 1024
HORDE_RACES = 2 | 16 | 32 | 128 | 512
ALLIANCE_FACTION, HORDE_FACTION = 469, 67
LEARN_SPELLS = {483, 55884}        # "Learning" spells a recipe item casts first

WORLD_DROP_CREATURES = 12          # dropped by more kinds than this: a world drop
MAX_NAMED = 3                      # vendors / droppers named per source
MOB_DROP_MIN_CREATURES = 3         # a reagent many mobs drop (cloth, meat)

CREATURE_TYPE_CRITTER = 8
SKIN_NEEDS_OTHER = 0x100 | 0x200 | 0x8000   # herb-, mining- or engineering-skinned


# ---------------------------------------------------------------------------
# downloads and the SQL dump reader
# ---------------------------------------------------------------------------

def fetch(url, path, refresh):
    if os.path.exists(path) and not refresh:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    print("  downloading", url)
    req = urllib.request.Request(url, headers={"User-Agent": "FycoProfessions-build/0.1"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            break
        except Exception as e:
            if attempt == 4:
                raise
            print("    retry %d: %s" % (attempt + 1, e))
            time.sleep(10 * (attempt + 1))
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    with open(path, "wb") as f:
        f.write(data)


TOKEN = re.compile(r"'(?:[^'\\]|\\.|'')*'|NULL|-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?|[(),;]")


def unquote(s):
    s = s[1:-1].replace("''", "'")
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "r": "", "t": "\t", "0": ""}.get(m.group(1), m.group(1)), s)


def read_table(name):
    """Yield each row of an AzerothCore dump as a dict keyed by column name."""
    src = open(os.path.join(CACHE, "acore", name + ".sql"), encoding="utf-8", errors="replace").read()
    create = src[src.index("CREATE TABLE"):]
    create = create[:create.index("ENGINE")]
    cols = re.findall(r"^\s*`(\w+)`", create, re.M)

    pos = 0
    while True:
        i = src.find("INSERT INTO", pos)
        if i == -1:
            break
        j = src.index("VALUES", i) + 6
        row, depth = None, 0
        for m in TOKEN.finditer(src, j):
            t = m.group(0)
            if t == "(":
                row, depth = [], 1
            elif t == ")":
                yield dict(zip(cols, row))
                row, depth = None, 0
            elif t == ";":
                pos = m.end()
                break
            elif t == ",":
                continue
            elif depth:
                if t == "NULL":
                    row.append(None)
                elif t[0] == "'":
                    row.append(unquote(t))
                elif "." in t or "e" in t or "E" in t:
                    row.append(float(t))
                else:
                    row.append(int(t))
        else:
            break


def load_ref(name, int_keys=True):
    with open(os.path.join(SCRIPTS, "ref", name + ".json"), encoding="utf-8") as f:
        d = json.load(f)
    if int_keys and isinstance(d, dict):
        return {int(k): v for k, v in d.items()}
    return d


# ---------------------------------------------------------------------------
# Lua output
# ---------------------------------------------------------------------------

def ascii_only(s):
    """The 3.3.5a client renders anything outside ASCII as mojibake."""
    s = unicodedata.normalize("NFKD", s or "")
    return s.encode("ascii", "ignore").decode("ascii")


def lua_str(s):
    s = ascii_only(s)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def lua_key(k):
    if isinstance(k, int):
        return "[%d]" % k
    if IDENT.match(k):
        return k
    return "[%s]" % lua_str(k)


def lua_value(v, indent=0):
    pad = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return ("%.2f" % v).rstrip("0").rstrip(".")
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, (list, tuple)):
        if all(not isinstance(x, (dict, list, tuple)) for x in v):
            return "{ " + ", ".join(lua_value(x) for x in v) + " }"
        return "{\n" + "".join(pad + "\t" + lua_value(x, indent + 1) + ",\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        keys = [k for k in v if v[k] is not None]
        flat = all(not isinstance(v[k], (dict, list, tuple)) or
                   (isinstance(v[k], (list, tuple)) and all(not isinstance(x, (dict, list, tuple)) for x in v[k]))
                   for k in keys)
        if flat and len(keys) <= 12:
            return "{ " + ", ".join("%s = %s" % (lua_key(k), lua_value(v[k])) for k in keys) + " }"
        return "{\n" + "".join("%s\t%s = %s,\n" % (pad, lua_key(k), lua_value(v[k], indent + 1))
                               for k in keys) + pad + "}"
    raise TypeError(repr(v))


def lua_file(header, assignments):
    """One generated file. Every assignment runs in its own function, so no
    single Lua function comes near the 5.1 limit on constants."""
    out = ["-- " + line if line else "--" for line in header.split("\n")]
    out.append("-- GENERATED by scripts/build_data.py -- do not edit, the next build overwrites it.")
    out.append("")
    out.append("local _, ns = ...")
    out.append("")
    for target, value in assignments:
        # the leading ";" stops Lua 5.1 reading "(function" as a call on the line before
        out.append(";(function() %s = %s end)()" % (target, lua_value(value, 0)))
        out.append("")
    return "\n".join(out)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write(text)
    print("wrote %-24s %7d bytes" % (os.path.relpath(path, ROOT), len(text)))


# ---------------------------------------------------------------------------
# geography
# ---------------------------------------------------------------------------

class Geo:
    """Resolve a world position to a zone and that zone's map coordinates,
    using the realm client's WorldMapArea bounds. AzerothCore leaves zoneId
    at 0 on most spawn rows, so the position is the reliable part."""

    def __init__(self, wma, areas, maps):
        self.by_map = {}
        for w in wma.values():
            self.by_map.setdefault(w["map"], []).append(w)
        self.areas, self.maps = areas, maps

    def locate(self, map_id, x, y):
        best, best_size = None, None
        for w in self.by_map.get(map_id, []):
            if w["bottom"] <= x <= w["top"] and w["right"] <= y <= w["left"]:
                size = (w["top"] - w["bottom"]) * (w["left"] - w["right"])
                if best is None or size < best_size:
                    best, best_size = w, size
        if not best:
            return None, None, None
        mx = (best["left"] - y) / (best["left"] - best["right"]) * 100
        my = (best["top"] - x) / (best["top"] - best["bottom"]) * 100
        return best["area"], round(mx, 1), round(my, 1)

    def box(self, area):
        """The WorldMapArea bounds of a zone's own map, or None."""
        for boxes in self.by_map.values():
            for w in boxes:
                if w["area"] == area:
                    return w
        return None

    def is_world(self, map_id):
        m = self.maps.get(map_id)
        return m is not None and m["type"] == 0

    def zone_name(self, area):
        a = self.areas.get(area)
        return a["name"] if a else None


def side_of_template(ft):
    """"A", "H" or "B" (both) from a faction template: who can use this NPC."""
    if not ft:
        return "B"
    a_ok = not (ft["enemy"] & 2) and ALLIANCE_FACTION not in ft["enemies"]
    h_ok = not (ft["enemy"] & 4) and HORDE_FACTION not in ft["enemies"]
    if a_ok and h_ok:
        return "B"
    if a_ok:
        return "A"
    if h_ok:
        return "H"
    return None


def side_of_races(races):
    if races and races != -1:
        if not races & HORDE_RACES:
            return "A"
        if not races & ALLIANCE_RACES:
            return "H"
    return None


def pack(mx, my):
    """A zone map position (0-100 each, 0.1 precision) as one integer:
    x * 10 * 1001 + y * 10. Unpacked in Modules/Pins.lua."""
    x = max(0, min(1000, int(round(mx * 10))))
    y = max(0, min(1000, int(round(my * 10))))
    return x * 1001 + y


def pct(values, p):
    values = sorted(values)
    if not values:
        return None
    return values[min(len(values) - 1, int(len(values) * p))]


# ---------------------------------------------------------------------------
# build
# ---------------------------------------------------------------------------

def main():
    refresh = "--refresh" in sys.argv
    print("sources")
    for t in ACORE_TABLES:
        fetch(ACORE_URL % t, os.path.join(CACHE, "acore", t + ".sql"), refresh)

    maps, areas = load_ref("maps"), load_ref("areas")
    factions, factiontpl = load_ref("factions"), load_ref("factiontpl")
    extcost, wma, locks = load_ref("extcost"), load_ref("wma"), load_ref("locks")
    tools, focus = load_ref("tools"), load_ref("focus")
    spells, ranks = load_ref("spells"), load_ref("ranks")
    abilities = load_ref("abilities", int_keys=False)
    geo = Geo(wma, areas, maps)

    # --- database -----------------------------------------------------------
    print("reading database")
    items = {r["entry"]: r for r in read_table("item_template")}
    ctpl = {r["entry"]: r for r in read_table("creature_template")}

    cspawns = {}       # creature entry -> [(zone, x, y)] on world maps
    zone_levels = {}   # zone -> [mob level]
    for r in read_table("creature"):
        if not geo.is_world(r["map"]):
            continue
        zone, mx, my = geo.locate(r["map"], r["position_x"], r["position_y"])
        if not zone:
            continue
        e = r["id1"]
        cspawns.setdefault(e, []).append((zone, mx, my, r["map"]))
        t = ctpl.get(e)
        if t and t["npcflag"] == 0 and t["type"] != CREATURE_TYPE_CRITTER and t["rank"] in (0, 1) \
                and t["minlevel"] > 0:
            zone_levels.setdefault(zone, []).append((t["minlevel"] + t["maxlevel"]) / 2)

    used_zones = set()

    def first_place(entry):
        s = cspawns.get(entry)
        if not s:
            return None
        used_zones.add(s[0][0])
        return s[0]

    # --- trainers -----------------------------------------------------------
    # AzerothCore keeps most trainers in trainer / trainer_spell /
    # creature_default_trainer, and some older ones in npc_trainer (whose
    # negative SpellID points at a shared list). Both are read into one shape.
    # Trainers list "teach" spells; teaches.json maps each to what it grants.
    teaches = load_ref("teaches")

    def norm(spell, cost, skill, level, spec):
        return {"SpellID": teaches.get(spell, spell), "MoneyCost": cost, "ReqSkillRank": skill,
                "ReqLevel": level, "ReqSpell": spec}

    legacy = {}        # npc_trainer list id -> raw rows
    for r in read_table("npc_trainer"):
        legacy.setdefault(r["ID"], []).append(r)

    def legacy_spells(list_id, seen):
        if list_id in seen:
            return []
        seen.add(list_id)
        out = []
        for r in legacy.get(list_id, []):
            if r["SpellID"] < 0:
                out += legacy_spells(-r["SpellID"], seen)
            else:
                out.append(norm(r["SpellID"], r["MoneyCost"], r["ReqSkillRank"], r["ReqLevel"], r["ReqSpell"]))
        return out

    new_lists = {}     # trainer id -> rows
    for r in read_table("trainer_spell"):
        spec = r["ReqAbility1"] or None
        new_lists.setdefault(r["TrainerId"], []).append(
            norm(r["SpellId"], r["MoneyCost"], r["ReqSkillRank"], r["ReqLevel"], spec))
    trainer_rows = {}  # creature entry -> rows
    for r in read_table("creature_default_trainer"):
        trainer_rows.setdefault(r["CreatureId"], []).extend(new_lists.get(r["TrainerId"], []))
    for cid in legacy:
        if cid in ctpl:
            trainer_rows.setdefault(cid, []).extend(legacy_spells(cid, set()))

    def trainer_spells(entry):
        return trainer_rows.get(entry, [])

    rank_of = {}       # rank spell -> (skill, step)
    for skill, steps in ranks.items():
        for step, ids in steps.items():
            for sid in ids:
                rank_of[sid] = (skill, int(step))

    rank_req = {}      # (skill, step) -> [(level, skill rank, cost)]
    recipe_train = {}  # spell -> {cost, lvl, skill, spec, sides}
    trainers = {}      # prof key -> [trainer]
    for entry, t in ctpl.items():
        if entry not in trainer_rows:
            continue
        rows = trainer_spells(entry)
        side = side_of_template(factiontpl.get(t["faction"]))
        spawn = first_place(entry)
        taught = {}    # skill -> highest step
        for r in rows:
            sid = r["SpellID"]
            if sid in rank_of:
                skill, step = rank_of[sid]
                taught[skill] = max(taught.get(skill, 0), step)
                rank_req.setdefault((skill, step), []).append((r["ReqLevel"], r["ReqSkillRank"], r["MoneyCost"]))
            elif sid in spells:
                rt = recipe_train.setdefault(sid, {"cost": r["MoneyCost"], "lvl": r["ReqLevel"],
                                                   "skill": r["ReqSkillRank"], "sides": set()})
                rt["cost"] = min(rt["cost"], r["MoneyCost"])
                if r["ReqSpell"]:
                    rt["spec"] = r["ReqSpell"]
                if spawn and side:
                    rt["sides"].add(side)
        if not spawn or not side:
            continue
        for skill, step in taught.items():
            if skill in PROF:
                zone, mx, my, map_id = spawn
                trainers.setdefault(PROF[skill], []).append({
                    "n": t["name"], "t": t["subname"] or None, "z": zone, "x": mx, "y": my,
                    "c": map_id, "side": side, "max": step * 75})

    rank_info = {}
    for (skill, step), reqs in sorted(rank_req.items()):
        if skill not in PROF:
            continue
        # the most common requirement across trainers (a few are scripted oddities)
        common = max(set(reqs), key=reqs.count)
        rank_info.setdefault(PROF[skill], {})[step] = {"cap": step * 75, "lvl": common[0],
                                                        "skill": common[1], "cost": common[2]}

    # --- loot indexes -------------------------------------------------------
    print("reading loot")

    def index_loot(table):
        direct, refs = {}, {}
        for r in read_table(table):
            if r["Reference"]:
                refs.setdefault(r["Reference"], []).append((r["Entry"], r["Chance"]))
            else:
                direct.setdefault(r["Item"], []).append((r["Entry"], r["Chance"]))
        return direct, refs

    def loot_by_entry(table):
        out = {}
        for r in read_table(table):
            out.setdefault(r["Entry"], []).append(r)
        return out

    c_direct, c_refs = index_loot("creature_loot_template")
    r_direct, r_refs = index_loot("reference_loot_template")
    ref_by_entry = loot_by_entry("reference_loot_template")

    def expand(rows, seen=None):
        """Loot rows with references replaced by what they contain."""
        seen = seen or set()
        out = []
        for r in rows:
            if r["Reference"]:
                if r["Reference"] in seen:
                    continue
                seen.add(r["Reference"])
                out += expand(ref_by_entry.get(r["Reference"], []), seen)
            else:
                out.append(r)
        return out

    loot_owner = {}
    for e, t in ctpl.items():
        if t["lootid"]:
            loot_owner.setdefault(t["lootid"], []).append(e)

    def creature_droppers(item):
        lootids = [e for e, _ in c_direct.get(item, [])]
        todo, seen = [e for e, _ in r_direct.get(item, [])], set()
        while todo:
            ref = todo.pop()
            if ref in seen:
                continue
            seen.add(ref)
            lootids += [e for e, _ in c_refs.get(ref, [])]
            todo += [e for e, _ in r_refs.get(ref, [])]
        out = set()
        for lid in lootids:
            out.update(loot_owner.get(lid, []))
        return out

    # --- gathering nodes ----------------------------------------------------
    gobj_loot = loot_by_entry("gameobject_loot_template")
    node_tpl = {}      # gameobject entry -> (kind, skill, name, lootid)
    for r in read_table("gameobject_template"):
        if r["type"] == 3 and r["Data0"] in locks:
            lk = locks[r["Data0"]]
            node_tpl[r["entry"]] = ("mining" if lk["type"] == 3 else "herbalism", lk["skill"], r["name"], r["Data1"])
    node_zone = {}     # (kind, name) -> {zone: count}
    node_pos = {}      # (kind, name) -> {zone: set of packed map positions}
    for r in read_table("gameobject"):
        n = node_tpl.get(r["id"])
        if not n or not geo.is_world(r["map"]):
            continue
        zone, mx, my = geo.locate(r["map"], r["position_x"], r["position_y"])
        if zone:
            d = node_zone.setdefault((n[0], n[2]), {})
            d[zone] = d.get(zone, 0) + 1
            node_pos.setdefault((n[0], n[2]), {}).setdefault(zone, set()).add(pack(mx, my))
            used_zones.add(zone)

    gathered = {}      # item -> set of tags
    nodes = {"mining": [], "herbalism": []}
    node_seen = {}
    for entry, (kind, skill, name, lootid) in sorted(node_tpl.items()):
        yields = [r for r in expand(gobj_loot.get(lootid, [])) if r["Chance"] >= 10 or r["GroupId"]]
        for r in yields:
            gathered.setdefault(r["Item"], set()).add("m" if kind == "mining" else "h")
        key = (kind, name)
        if key not in node_zone or key in node_seen:
            continue
        # quest objects (Alterac Granite) use the same locks; skip anything
        # that yields only quest items
        if not yields or all(items.get(r["Item"], {}).get("class") == 12 for r in yields):
            continue
        top = sorted(yields, key=lambda r: -(r["Chance"] or 50))[:3]
        node_seen[key] = {"n": name, "sk": skill, "items": [r["Item"] for r in top],
                          "z": sorted(([z, c] for z, c in node_zone[key].items()), key=lambda zc: -zc[1])}
        nodes[kind].append(node_seen[key])
    for kind in nodes:
        nodes[kind].sort(key=lambda n: (n["sk"], n["n"]))
    node_spawns = {"mining": {}, "herbalism": {}}
    for (kind, name), node in node_seen.items():
        node_spawns[kind][name] = {z: sorted(p) for z, p in node_pos[(kind, name)].items()}

    # --- skinning -----------------------------------------------------------
    skin_loot = loot_by_entry("skinning_loot_template")
    skin_zone = {}     # zone -> {entry: count}
    skin_pos = {}      # zone -> {name: {lo, hi, positions}}
    for e, t in ctpl.items():
        if not t["skinloot"] or t["type_flags"] & SKIN_NEEDS_OTHER or t["rank"] not in (0, 4):
            continue
        for r in expand(skin_loot.get(t["skinloot"], [])):
            gathered.setdefault(r["Item"], set()).add("s")
        for zone, mx, my, _ in cspawns.get(e, []):
            d = skin_zone.setdefault(zone, {})
            d[e] = d.get(e, 0) + 1
            used_zones.add(zone)
            m = skin_pos.setdefault(zone, {}).setdefault(t["name"], {"lo": t["minlevel"], "hi": t["maxlevel"], "p": set()})
            m["lo"], m["hi"] = min(m["lo"], t["minlevel"]), max(m["hi"], t["maxlevel"])
            m["p"].add(pack(mx, my))
    skinning = {}
    for zone, ents in skin_zone.items():
        mobs = {}
        for e, cnt in ents.items():
            t = ctpl[e]
            m = mobs.setdefault(t["name"], {"n": t["name"], "lo": t["minlevel"], "hi": t["maxlevel"], "c": 0})
            m["lo"], m["hi"] = min(m["lo"], t["minlevel"]), max(m["hi"], t["maxlevel"])
            m["c"] += cnt
        skinning[zone] = sorted(mobs.values(), key=lambda m: (-m["c"], m["n"]))[:12]

    # every spawn point, for the map pins (Modules/Pins.lua)
    skin_spawns = {}
    for zone, mobs in skin_pos.items():
        skin_spawns[zone] = [{"n": name, "lo": m["lo"], "hi": m["hi"], "p": sorted(m["p"])}
                             for name, m in sorted(mobs.items())]

    # --- fishing ------------------------------------------------------------
    fish_loot = loot_by_entry("fishing_loot_template")
    for rows in fish_loot.values():
        for r in expand(rows):
            gathered.setdefault(r["Item"], set()).add("f")
    fishing = []
    for r in read_table("skill_fishing_base_level"):
        a = areas.get(r["entry"])
        if not a or not geo.is_world(a["map"]):
            continue
        catch = sorted(expand(fish_loot.get(r["entry"], [])), key=lambda x: -(x["Chance"] or 0))
        fishing.append({"a": r["entry"], "n": a["name"], "c": a["map"], "sk": r["skill"],
                        "zone": a["zone"] or None, "fish": [x["Item"] for x in catch[:4]]})
    fishing.sort(key=lambda f: (f["sk"], f["n"]))

    # --- prospecting, milling, disenchanting --------------------------------
    def conversion(table, tag):
        out = {}
        for entry, rows in loot_by_entry(table).items():
            got = []
            for r in expand(rows):
                gathered.setdefault(r["Item"], set()).add(tag)
                got.append([r["Item"], round(r["Chance"] or 0, 1), r["MinCount"], r["MaxCount"]])
            got.sort(key=lambda g: -g[1])
            out[entry] = got
        return out

    prospect = conversion("prospecting_loot_template", "p")
    mill = conversion("milling_loot_template", "l")

    de_rows = loot_by_entry("disenchant_loot_template")
    de_groups = {}     # DisenchantID -> [item rows]
    for row in items.values():
        did = row.get("DisenchantID")
        if did:
            de_groups.setdefault(did, []).append(row)
    disenchant = {}    # material -> [{q, lo, hi, sk, ch}]
    for did, rows in de_rows.items():
        src = de_groups.get(did)
        if not src:
            continue
        lvls = [r["ItemLevel"] for r in src]
        qual = max(set(r["Quality"] for r in src), key=[r["Quality"] for r in src].count)
        skill = min(r["RequiredDisenchantSkill"] for r in src if r["RequiredDisenchantSkill"] is not None)
        for r in expand(rows):
            gathered.setdefault(r["Item"], set()).add("d")
            disenchant.setdefault(r["Item"], []).append({"q": qual, "lo": min(lvls), "hi": max(lvls),
                                                         "sk": max(skill, 0), "ch": round(r["Chance"] or 0, 1)})
    for mat in disenchant:
        disenchant[mat].sort(key=lambda d: (d["lo"], d["q"]))

    # --- vendors ------------------------------------------------------------
    vendor_rows = {}
    for r in read_table("npc_vendor"):
        vendor_rows.setdefault(r["entry"], []).append(r)
    sold_by = {}       # item -> [(vendor entry, row)]
    for v, rows in vendor_rows.items():
        for r in rows:
            if r["item"] > 0:
                sold_by.setdefault(r["item"], []).append((v, r))
            else:
                for r2 in vendor_rows.get(-r["item"], []):
                    if r2["item"] > 0:
                        sold_by.setdefault(r2["item"], []).append((v, r2))

    # --- quests -------------------------------------------------------------
    rewarded_by = {}
    for q in read_table("quest_template"):
        for k in range(1, 5):
            if q["RewardItem%d" % k]:
                rewarded_by.setdefault(q["RewardItem%d" % k], []).append(q)
        for k in range(1, 7):
            if q["RewardChoiceItemID%d" % k]:
                rewarded_by.setdefault(q["RewardChoiceItemID%d" % k], []).append(q)

    # --- recipes ------------------------------------------------------------
    print("recipes")
    recipe_items = {}  # recipe spell -> [recipe item entries]
    for e, it in items.items():
        if it["class"] != 9:
            continue
        s1, s2 = it["spellid_1"], it["spellid_2"]
        sid = s2 if s1 in LEARN_SPELLS else s1
        if sid in spells:
            recipe_items.setdefault(sid, []).append(e)

    wanted_items = set()

    def place_text(entry):
        p = first_place(entry)
        return geo.zone_name(p[0]) if p else None

    def vendor_cost(item_row, r):
        c = {}
        x = extcost.get(r["ExtendedCost"]) if r["ExtendedCost"] else None
        if x and x["items"]:
            c["items"] = [v for pair in x["items"] for v in pair]
            wanted_items.update(pair[0] for pair in x["items"])
        if item_row["BuyPrice"] and (not r["ExtendedCost"] or item_row["FlagsExtra"] & 4):
            c["gold"] = item_row["BuyPrice"]
        return c

    def recipe_item_sources(ri):
        row = items[ri]
        out = []
        rep = None
        if row["RequiredReputationFaction"]:
            rep = [factions.get(row["RequiredReputationFaction"], "?"),
                   REP_RANKS.get(row["RequiredReputationRank"], "?")]
        item_side = side_of_races(row["AllowableRace"])
        if row["FlagsExtra"] & 1:
            item_side = "H"
        elif row["FlagsExtra"] & 2:
            item_side = "A"
        vend = {}
        for v, r in sold_by.get(ri, []):
            t = ctpl.get(v)
            if not t or not cspawns.get(v):
                continue
            side = side_of_template(factiontpl.get(t["faction"]))
            if item_side and side == "B":
                side = item_side
            key = (t["name"], side)
            if key in vend:
                continue
            vend[key] = {"t": "vendor", "item": ri, "who": t["name"], "zone": place_text(v),
                         "cost": vendor_cost(row, r) or None, "rep": rep, "side": side,
                         "lim": True if r["maxcount"] else None}
        out += list(vend.values())[:MAX_NAMED]
        droppers = creature_droppers(ri)
        if len(droppers) > WORLD_DROP_CREATURES:
            out.append({"t": "world", "item": ri, "n": len(droppers)})
        else:
            named = {}
            for e in droppers:
                t = ctpl.get(e)
                if t and t["name"] not in named:
                    named[t["name"]] = {"t": "drop", "item": ri, "who": t["name"], "zone": place_text(e)}
            out += list(named.values())[:MAX_NAMED]
        for q in rewarded_by.get(ri, [])[:MAX_NAMED]:
            zone = areas.get(q["QuestSortID"], {}).get("name") if q["QuestSortID"] > 0 else None
            out.append({"t": "quest", "item": ri, "who": q["LogTitle"], "zone": zone,
                        "side": side_of_races(q["AllowableRaces"]) or item_side})
        if not out:
            out.append({"t": "item", "item": ri})
        wanted_items.add(ri)
        return out

    recipes = {}
    creators = {}      # item -> {prof key}
    skipped = 0
    for a in abilities:
        sp = spells.get(a["spell"])
        prof = PROF.get(a["skill"])
        if not sp or not prof or a["grey"] <= 0:
            continue
        if not sp["reagents"] and not sp["creates"]:
            skipped += 1
            continue
        yellow, grey = a["yellow"], a["grey"]
        green = (yellow + grey) // 2
        rec = {"sp": a["spell"], "n": sp["name"], "o": a["min"], "y": yellow, "g": green, "gr": grey,
               "r": [v for pair in sp["reagents"] for v in pair]}
        if sp["creates"]:
            it, lo, hi = sp["creates"]
            rec["it"] = it
            if lo != 1 or hi != 1:
                rec["qty"] = round((lo + hi) / 2, 1) if lo != hi else lo
            wanted_items.add(it)
            creators.setdefault(it, set()).add(prof)
        wanted_items.update(pair[0] for pair in sp["reagents"])
        tl = [tools[t] for t in sp["tools"] if t in tools]
        if sp["focus"] and sp["focus"] in focus:
            tl.append(focus[sp["focus"]])
        if tl:
            rec["tl"] = tl
        if a["race"]:
            rec["race"] = a["race"]

        src = []
        if a["acquire"] in (1, 2):
            src.append({"t": "auto"})
        tr = recipe_train.get(a["spell"])
        if tr:
            sides = tr["sides"]
            side = None if not sides or "B" in sides or sides == {"A", "H"} else sides.pop()
            src.append({"t": "trainer", "cost": tr["cost"], "lvl": tr["lvl"] or None, "skill": tr["skill"],
                        "side": side, "spec": tr.get("spec"), "unspawned": None if sides or not tr else True})
        for ri in recipe_items.get(a["spell"], []):
            src += recipe_item_sources(ri)
            spec = items[ri]["requiredspell"]
            if spec:
                rec["spec"] = spec
        if tr and tr.get("spec"):
            rec["spec"] = tr["spec"]
        rec["src"] = src
        # SkillLineAbility says 1 for most learned recipes; the real point it
        # can first be made is the skill its trainer or recipe item asks for
        learn = [tr["skill"]] if tr else []
        learn += [items[ri]["RequiredSkillRank"] for ri in recipe_items.get(a["spell"], [])]
        learn = [x for x in learn if x]
        if learn and a["acquire"] not in (1, 2):
            rec["o"] = max(rec["o"], min(learn))
        recipes.setdefault(prof, []).append(rec)
    for prof in recipes:
        recipes[prof].sort(key=lambda r: (r["o"], r["y"], r["n"]))
    print("  %s" % ", ".join("%s %d" % (k, len(v)) for k, v in sorted(recipes.items())))
    print("  skipped %d abilities with nothing to craft" % skipped)

    # --- Dalaran jewelcrafting dailies ----------------------------------------
    TOKEN_ID = 41596   # Dalaran Jewelcrafter's Token
    daily = {"token": TOKEN_ID, "quests": [], "rewards": []}
    for q in rewarded_by.get(TOKEN_ID, []):
        daily["quests"].append(q["LogTitle"])
    daily["quests"] = sorted(set(daily["quests"]))
    seen_rewards = set()
    for item, sellers in sold_by.items():
        for v, r in sellers:
            x = extcost.get(r["ExtendedCost"]) if r["ExtendedCost"] else None
            if not x or item in seen_rewards:
                continue
            for tok, cnt in x["items"]:
                if tok == TOKEN_ID:
                    seen_rewards.add(item)
                    daily["rewards"].append({"item": item, "cost": cnt, "who": ctpl[v]["name"] if v in ctpl else None})
                    wanted_items.add(item)
    daily["rewards"].sort(key=lambda r: (r["cost"], items.get(r["item"], {}).get("name", "")))
    wanted_items.add(TOKEN_ID)

    # --- items ----------------------------------------------------------------
    for n in nodes.values():
        for node in n:
            wanted_items.update(node["items"])
    for f in fishing:
        wanted_items.update(f["fish"])
    for table in (prospect, mill):
        for src_item, got in table.items():
            wanted_items.add(src_item)
            wanted_items.update(g[0] for g in got)
    wanted_items.update(disenchant)

    out_items = {}
    for iid in sorted(wanted_items):
        row = items.get(iid)
        if not row:
            continue
        it = {"n": row["name"], "q": row["Quality"]}
        if row["SellPrice"]:
            it["s"] = row["SellPrice"]
        # a plain vendor price, per single item, from an unlimited vendor
        vendors = [(v, r) for v, r in sold_by.get(iid, []) if not r["ExtendedCost"] and not r["maxcount"]]
        if vendors and row["BuyPrice"]:
            it["v"] = max(1, row["BuyPrice"] // max(1, row["BuyCount"] or 1))
            names = []
            for v, _ in vendors:
                t = ctpl.get(v)
                if t and cspawns.get(v):
                    label = t["name"] + (" - " + place_text(v) if place_text(v) else "")
                    if label not in names:
                        names.append(label)
            if names:
                it["vw"] = names[0] if len(names) == 1 else "%d vendors, e.g. %s" % (len(names), names[0])
        tags = set(gathered.get(iid, ()))
        if len(creature_droppers(iid)) >= MOB_DROP_MIN_CREATURES:
            tags.add("x")
        tag_s = "".join(sorted(tags))
        if tag_s:
            it["g"] = tag_s
        if iid in creators:
            it["c"] = sorted(creators[iid])
        out_items[iid] = it

    # --- zones ----------------------------------------------------------------
    for f in fishing:
        used_zones.add(f["zone"] or f["a"])
    zones = {}
    for z in sorted(used_zones):
        a = areas.get(z)
        if not a:
            continue
        lv = zone_levels.get(z, [])
        box = geo.box(z)
        zones[z] = {"n": a["name"], "c": a["map"], "lo": int(pct(lv, 0.1)) if lv else None,
                    "hi": int(pct(lv, 0.9)) if lv else None,
                    "side": {2: "A", 4: "H"}.get(a.get("side")),
                    # the zone map's size in yards, for minimap pins
                    "w": round(box["left"] - box["right"], 1) if box else None,
                    "h": round(box["top"] - box["bottom"], 1) if box else None}
    # The pins need to know which zone a map shows. GetMapInfo() gives the
    # map's internal name ("Tanaris") -- the reliable key. GetCurrentMapAreaID()
    # is kept as a second key, but what it returns in 3.3.5a is not certain.
    map_to_zone = {wid: w["area"] for wid, w in wma.items() if w["area"] in zones}
    file_to_zone = {w["file"]: w["area"] for w in wma.values() if w["area"] in zones and w.get("file")}

    # --- write ----------------------------------------------------------------
    write(os.path.join(DATA, "Recipes.lua"), lua_file(
        "FycoProfessions - Data/Recipes.lua\n"
        "Every recipe per profession: orange (o), yellow (y), green (g) and grey (gr)\n"
        "skill, reagents (r = id, count, ...), the item made (it, qty), tools (tl),\n"
        "and how to learn it (src). Thresholds and reagents are this realm's own\n"
        "(rebuffed.mpq); sources are the stock AzerothCore database.",
        [("ns.Recipes", {}), ("ns.RankInfo", rank_info), ("ns.Trainers", {})]
        + [("ns.Recipes.%s" % k, v) for k, v in sorted(recipes.items())]
        + [("ns.Trainers.%s" % k, sorted(v, key=lambda t: (t["c"], t["z"] or 0, t["n"])))
           for k, v in sorted(trainers.items())]))

    write(os.path.join(DATA, "Items.lua"), lua_file(
        "FycoProfessions - Data/Items.lua\n"
        "Reagents, products and recipe items: name (n), quality (q), vendor sell\n"
        "price (s), vendor buy price (v) and where (vw), gather tags (g: m mining,\n"
        "h herbalism, s skinning, f fishing, p prospecting, l milling,\n"
        "d disenchanting, x mob drop) and the professions that craft it (c).",
        [("ns.Items", out_items)]))

    write(os.path.join(DATA, "World.lua"), lua_file(
        "FycoProfessions - Data/World.lua\n"
        "Zones (name, continent map, mob levels), gathering nodes with the zones\n"
        "they spawn in, skinnable mobs by zone, and fishing zones by skill.\n"
        "Spawns are the stock AzerothCore ones; zones are resolved from spawn\n"
        "positions with this realm's WorldMapArea bounds.",
        [("ns.Continents", CONTINENTS), ("ns.Zones", zones), ("ns.Nodes", nodes),
         ("ns.SkinZones", skinning), ("ns.FishingZones", fishing), ("ns.MapToZone", map_to_zone),
         ("ns.MapFileToZone", file_to_zone)]))

    write(os.path.join(DATA, "Spawns.lua"), lua_file(
        "FycoProfessions - Data/Spawns.lua\n"
        "Every gathering node and skinnable mob spawn point, for the map pins.\n"
        "Positions are packed zone map coordinates: x * 10 * 1001 + y * 10\n"
        "(0-100 each, 0.1 precision). Stock AzerothCore spawns; mobs wander.",
        [("ns.NodeSpawns", {}), ("ns.SkinSpawns", {})]
        + [("ns.NodeSpawns.%s" % k, v) for k, v in sorted(node_spawns.items())]
        + [("ns.SkinSpawns[%d]" % z, v) for z, v in sorted(skin_spawns.items())]))

    write(os.path.join(DATA, "Extras.lua"), lua_file(
        "FycoProfessions - Data/Extras.lua\n"
        "Prospecting and milling results (item, chance %, min, max), disenchanting\n"
        "sources per material, and the Dalaran jewelcrafting daily tokens.",
        [("ns.Prospect", prospect), ("ns.Mill", mill), ("ns.Disenchant", disenchant),
         ("ns.JCDaily", daily)]))

    print("done: %d items, %d zones, %d trainers" % (len(out_items), len(zones),
                                                      sum(len(v) for v in trainers.values())))


if __name__ == "__main__":
    main()
