"""Automated tests: load the real addon in a real Lua 5.1 against a mock client.

    pip install lupa          # once; lupa bundles Lua 5.1, the version WoW 3.3.5 uses
    python tests/run_tests.py [test_name ...]

Every test starts a fresh mock client (tests/wowmock.lua), loads every file
FycoProfessions.toc lists, in order, exactly as the game would, fires
PLAYER_LOGIN, and then drives the addon: runs slash commands, clicks
dropdowns, opens the window and moves between tabs.

What this cannot tell you: whether frames LOOK right or sit where they
should, or whether the real 3.3.5a API behaves like the mock. That is what
docs/TESTING.md is for.
"""
import os
import re
import sys
import traceback

try:
    import lupa.lua51 as lupa_lua
except ImportError:
    sys.exit("lupa is not installed: pip install lupa")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOC = os.path.join(ROOT, "FycoProfessions.toc")


def toc_files():
    files = []
    for line in open(TOC, encoding="ascii"):
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(os.path.join(ROOT, line.replace("\\", os.sep)))
    return files


class Client:
    """One mock game client with the addon loaded and logged in."""

    def __init__(self, faction="Horde", saved=None, skills=(), secondary=(), level=80, setup=None):
        self.lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(self.dofile_src(os.path.join(ROOT, "tests", "wowmock.lua")))
        self.lua.execute('MOCK.faction = "%s"; MOCK.level = %d' % (faction, level))
        for name, rank, mx in skills:
            self.lua.execute('table.insert(MOCK.skills, {"%s", %d, %d})' % (name, rank, mx))
        for name, rank, mx in secondary:
            self.lua.execute('table.insert(MOCK.secondary, {"%s", %d, %d})' % (name, rank, mx))
        if setup:
            self.lua.execute(setup)
        if saved:
            self.lua.execute(saved)
        self.lua.execute("ns = {}")
        for path in toc_files():
            # the client skips a file the .toc names but the folder lacks;
            # toc_files_exist reports those as a failure of their own
            if os.path.exists(path):
                self.lua.execute(self.dofile_src(path, addon=True))
        self.lua.execute('MOCK.fire("ADDON_LOADED", "FycoProfessions"); MOCK.fire("PLAYER_LOGIN"); '
                         'MOCK.fire("PLAYER_ENTERING_WORLD")')

    @staticmethod
    def dofile_src(path, addon=False):
        p = path.replace("\\", "/")
        if addon:
            return 'local f = assert(loadfile("%s")); f("FycoProfessions", ns)' % p
        return 'dofile("%s")' % p

    def run(self, src):
        return self.lua.execute(src)

    def eval(self, expr):
        return self.lua.eval(expr)

    def chat(self):
        c = self.lua.globals().MOCK.chat
        return [c[i] for i in range(1, len(c) + 1)]

    def clear_chat(self):
        self.lua.execute("MOCK.chat = {}")

    def slash(self, text):
        self.lua.execute('SlashCmdList.FYCOPROF(%s)' % lua_quote(text))

    def last(self):
        return strip_colors(self.chat()[-1])


def lua_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def strip_colors(s):
    return re.sub(r"\|c[0-9a-zA-Z]{8}|\|r|\|H[^|]*\|h|\|h", "", s)


def options_dropdown(c, caption):
    """The global name of the options dropdown whose caption is `caption`.
    Captions are FontStrings created just before their dropdown."""
    return c.eval("""(function(cap)
        local found = false
        for _, f in ipairs(MOCK.frames) do
            if f._kind == "FontString" and f._text == cap then found = true end
            if found and f._template == "UIDropDownMenuTemplate" then return f:GetName() end
        end
    end)(%s)""" % lua_quote(caption))


# ---------------------------------------------------------------------------
# tests
# ---------------------------------------------------------------------------

TESTS = []


def test(fn):
    TESTS.append(fn)
    return fn


def no_errors(c):
    bad = [m for m in c.chat() if "failed" in m or "errored" in m]
    assert not bad, "error in chat: %s" % bad


@test
def toc_files_exist():
    missing = [p for p in toc_files() if not os.path.exists(p)]
    assert not missing, "FycoProfessions.toc lists files that do not exist: %s" % missing


@test
def loads_and_logs_in():
    c = Client()
    no_errors(c)
    greet = [strip_colors(m) for m in c.chat() if "/fprof" in m]
    assert greet, "no login greeting: %s" % c.chat()
    assert "x2" in greet[0] and "Horde" in greet[0], greet[0]
    c.run("MOCK.advance(2)")      # the ticker runs without retiring anything
    no_errors(c)


@test
def greeting_can_be_turned_off():
    c = Client(saved="FycoProfessionsDB = { general = { loginMessage = false } }")
    assert not [m for m in c.chat() if "/fprof" in m], c.chat()


@test
def settings_defaults():
    c = Client()
    assert c.eval("ns:Rate()") == 2
    assert c.eval("ns:Target()") == "rank"
    assert c.eval("ns:Faction()") == "Horde"
    assert c.eval("ns:FactionIsAuto()")
    assert c.eval("ns:Materials()") == "ah"
    assert c.eval('ns:Get("tracker", "shown")') is True
    assert c.eval('ns:Get("tracker", "locked")') is False


@test
def rate_command():
    c = Client()
    c.slash("rate 1")
    assert c.eval("ns:Rate()") == 1
    assert "x1" in c.last(), c.last()
    c.slash("rate x2")
    assert c.eval("ns:Rate()") == 2
    c.slash("rate 3")                 # only x1 and x2 are offered
    assert c.eval("ns:Rate()") == 2
    assert any("can be" in strip_colors(m) for m in c.chat()[-2:]), c.chat()[-2:]
    c.slash("rate")                   # just shows it
    assert "x2" in c.last()
    no_errors(c)


@test
def rate_saved_and_validated():
    c = Client(saved="FycoProfessionsDB = { guide = { rate = 1 } }")
    assert c.eval("ns:Rate()") == 1
    # a rate nobody can pick falls back to the default instead of being used
    c = Client(saved="FycoProfessionsDB = { guide = { rate = 5 } }")
    assert c.eval("ns:Rate()") == 2


@test
def rate_dropdown_in_options():
    c = Client()
    name = options_dropdown(c, "Skill points per skill-up")
    assert name, "no rate dropdown on the main settings page"
    assert c.eval('MOCK.pickDropdown(%s, 1)' % name)
    assert c.eval("ns:Rate()") == 1
    items = [c.eval("MOCK.dropdownButtons[%d].value" % i) for i in range(1, c.eval("#MOCK.dropdownButtons") + 1)]
    assert items == [1, 2], items
    assert c.eval("%s._ddtext" % name).startswith("x1"), c.eval("%s._ddtext" % name)


@test
def target_command_and_dropdown():
    c = Client()
    c.slash("target 300")
    assert c.eval("ns:Target()") == 300
    c.slash("target rank")
    assert c.eval("ns:Target()") == "rank"
    for bad in ("999", "0", "abc"):
        c.slash("target " + bad)
        assert c.eval("ns:Target()") == "rank", bad
    name = options_dropdown(c, "Guides stop at")
    assert c.eval('MOCK.pickDropdown(%s, 375)' % name)
    assert c.eval("ns:Target()") == 375
    assert "375" in c.eval("ns:GuideText()")
    no_errors(c)


@test
def faction_override_is_per_character():
    c = Client(faction="Horde")
    c.slash("faction alliance")
    assert c.eval("ns:Faction()") == "Alliance"
    assert not c.eval("ns:FactionIsAuto()")
    assert c.eval("FycoProfessionsCharDB.faction") == "Alliance"
    assert c.eval("FycoProfessionsDB.char") is None, "faction leaked into account settings"
    c.slash("faction auto")
    assert c.eval("ns:Faction()") == "Horde"
    c2 = Client(faction="Horde", saved='FycoProfessionsCharDB = { faction = "Alliance" }')
    assert c2.eval("ns:Faction()") == "Alliance"
    name = options_dropdown(c2, "Faction (trainers and vendors)")
    assert c2.eval('MOCK.pickDropdown(%s, "auto")' % name)
    assert c2.eval("ns:Faction()") == "Horde"
    c3 = Client(faction="Alliance")
    assert c3.eval("ns:Faction()") == "Alliance"


@test
def materials_command_and_dropdown():
    c = Client()
    c.slash("materials gathered")
    assert c.eval("ns:Materials()") == "gathered"
    assert "gathered" in c.eval("ns:GuideText()")
    c.slash("materials bogus")
    assert c.eval("ns:Materials()") == "gathered"
    name = options_dropdown(c, "Materials")
    assert c.eval('MOCK.pickDropdown(%s, "ah")' % name)
    assert c.eval("ns:Materials()") == "ah"


@test
def window_tabs_and_status():
    c = Client()
    c.slash("")
    assert c.eval("ns:WindowShown()")
    assert c.eval('ns:WindowShown("all")'), "first visible tab should be All professions"
    status = strip_colors(c.eval("FycoProfessionsWindow.status:GetText()"))
    assert "x2" in status, status
    c.slash("rate 1")
    status = strip_colors(c.eval("FycoProfessionsWindow.status:GetText()"))
    assert "x1" in status, status
    # hiding the selected tab never leaves the window on an invisible pane
    c.run('ns:AddTab("dummy", "Dummy", 1, function() end)')
    c.run('ns:OpenWindow("dummy")')
    assert c.eval('ns:WindowShown("dummy")')
    c.run('ns:ShowTab("dummy", false)')
    assert c.eval('ns:WindowShown("all")')
    c.slash("")
    assert not c.eval("ns:WindowShown()")
    no_errors(c)


@test
def browser_selects_every_profession():
    c = Client()
    n = c.eval("#ns.Professions")
    assert n == 14, n
    for i in range(1, n + 1):
        key = c.eval("ns.Professions[%d].key" % i)
        assert c.eval('ns:BrowseProfession("%s")' % key)
        assert c.eval("ns:BrowserSelected()") == key
    assert not c.eval('ns:BrowseProfession("basketweaving")')
    # skill line IDs are unique and every lookup finds its row
    ids = [c.eval("ns.Professions[%d].id" % i) for i in range(1, n + 1)]
    assert len(set(ids)) == n
    assert c.eval('ns.ProfessionByName["Jewelcrafting"].id') == 755
    no_errors(c)


@test
def tracker_commands_and_settings():
    c = Client()
    assert c.eval("ns:TrackerShown()")
    c.slash("tracker hide")
    assert not c.eval("ns:TrackerShown()")
    c.slash("tracker show")
    assert c.eval("ns:TrackerShown()")
    c.slash("tracker")
    assert not c.eval("ns:TrackerShown()")
    c.slash("tracker show")
    c.slash("tracker lock")
    assert c.eval('ns:Get("tracker", "locked")')
    c.slash("tracker unlock")
    assert not c.eval('ns:Get("tracker", "locked")')
    c.run('ns:Set("tracker", "pos", {"TOP", "TOP", 1, 2}); ns:ResetTracker()')
    assert c.eval('ns:Get("tracker", "pos")') is None
    c.run('ns:Set("tracker", "scale", 1.3)')
    assert abs(c.eval("FycoProfessionsTracker:GetScale()") - 1.3) < 1e-9
    # the Features switch hides it too
    c.run('FycoProfessionsDB.enabled.tracker = false; ns:Fire("SettingChanged", "enabled", "tracker", false)')
    assert not c.eval("ns:TrackerShown()")
    no_errors(c)


@test
def tracker_renders_pushed_lines():
    c = Client()
    c.run('ns:SetTrackerLines("Jewelcrafting 120/150", {"Make 12 x Thing", "Needs 24 x Ore"})')
    title = c.eval("(ns:TrackerLines())")
    assert title == "Jewelcrafting 120/150"
    shown = c.eval("""(function()
        local n = 0
        for _, f in ipairs(MOCK.frames) do
            if f._parent == FycoProfessionsTracker and f._kind == "FontString" and f._shown and f._text then n = n + 1 end
        end
        return n end)()""")
    assert shown == 3, shown      # title + two lines, spare lines hidden
    no_errors(c)


@test
def options_panels_build_and_refresh():
    c = Client()
    n = c.eval("#MOCK.panels")
    names = [c.eval("MOCK.panels[%d].name" % i) for i in range(1, n + 1)]
    assert names[0] == "FycoProfessions", names
    assert "Tracker" in names, names
    for i in range(1, n + 1):
        c.run('MOCK.run(MOCK.panels[%d], "OnShow")' % i)
        h = c.eval("MOCK.panels[%d].content._h" % i)
        assert h and h > 0
    # every dropdown shows its current value once refreshed
    empty = c.eval("""(function()
        local bad = {}
        for _, f in ipairs(MOCK.frames) do
            if f._template == "UIDropDownMenuTemplate" and (f._ddtext or "") == "" then bad[#bad + 1] = f:GetName() end
        end
        return table.concat(bad, ",") end)()""")
    assert empty == "", "dropdowns with no text: " + empty
    c.slash("options")
    assert c.eval("MOCK.openedPanel ~= nil")
    no_errors(c)


@test
def options_fit_the_real_panel_width():
    # 3.3.5a's options area is about 410 wide: nothing may reach past it
    # (in game, widgets past the edge could not be clicked)
    for width in (None, 410, 600):
        setup = None
        if width:
            setup = ('InterfaceOptionsFramePanelContainer = CreateFrame("Frame", "InterfaceOptionsFramePanelContainer"); '
                     'InterfaceOptionsFramePanelContainer:SetWidth(%d)' % width)
        c = Client(setup=setup)
        col_w, content_w = c.eval("ns:OptionsColumnWidth()")
        assert content_w == (width or 410) - 32, (width, content_w)
        for i in range(1, c.eval("#MOCK.panels") + 1):
            reach = c.eval("MOCK.panels[%d].reach or 0" % i)
            name = c.eval("MOCK.panels[%d].name" % i)
            assert 0 < reach <= content_w, "%s reaches %s of %s (panel %s)" % (name, reach, content_w, width)
        no_errors(c)


def slash_commands():
    """Every `cmd == "x"` the slash handler accepts, read from Core.lua."""
    src = open(os.path.join(ROOT, "Core.lua"), encoding="ascii").read()
    body = src[src.index("SlashCmdList.FYCOPROF"):]
    return sorted(set(re.findall(r'cmd == "(\w+)"', body)))


@test
def help_lists_every_command():
    c = Client()
    c.clear_chat()
    c.slash("help")
    text = " ".join(strip_colors(m) for m in c.chat())
    aliases = {"config", "settings"}
    missing = [cmd for cmd in slash_commands() if cmd not in aliases and "/fprof " + cmd not in text]
    assert not missing, "commands missing from /fprof help: %s" % missing


@test
def slash_everything_without_errors():
    c = Client()
    for cmd in ("help", "bogus", "debug", "debug", "minimap", "minimap", "options", "rate", "target",
                "faction", "faction nonsense", "materials", "tracker reset", "tracker nonsense", ""):
        c.slash(cmd)
    no_errors(c)
    # chat lines must never carry a raw "|" that is not a colour or link escape
    for m in c.chat():
        stray = re.sub(r"\|c[0-9a-fA-F]{8}|\|r|\|\|", "", m)
        assert "|" not in stray, "raw | in chat: %r" % m


# ---------------------------------------------------------------------------
# phase 1: detection
# ---------------------------------------------------------------------------

JC_SKIN = dict(skills=[("Jewelcrafting", 120, 150), ("Skinning", 80, 150)],
               secondary=[("Cooking", 1, 75), ("Fishing", 40, 75)])


@test
def detects_professions_and_tabs():
    c = Client(**JC_SKIN)
    keys = [c.eval("ns:PlayerProfessions()[%d].key" % i) for i in range(1, c.eval("#ns:PlayerProfessions()") + 1)]
    assert keys == ["jewelcrafting", "skinning", "cooking", "fishing"], keys
    assert c.eval('ns:ProfessionState("jewelcrafting").skill') == 120
    assert c.eval('ns:ProfessionState("jewelcrafting").max') == 150
    for k in keys:
        assert not c.eval('ns:TabHidden("%s")' % k), k
    for k in ("alchemy", "mining", "firstaid"):
        assert c.eval('ns:TabHidden("%s")' % k), k
    assert not c.eval('ns:ProfessionState("alchemy")')
    no_errors(c)


@test
def skills_arriving_just_after_login_are_detected():
    # reported from game: every profession showed 1/75. At login the client
    # has no skill list yet; it arrives with SKILL_LINES_CHANGED straight
    # after the addon's own login scan -- which a blanket loop guard ignored
    c = Client()
    assert not c.eval('ns:HasProfession("skinning")')
    c.run('table.insert(MOCK.skills, {"Skinning", 300, 300}); '
          'table.insert(MOCK.skills, {"Jewelcrafting", 350, 375}); MOCK.fire("SKILL_LINES_CHANGED")')
    assert c.eval('ns:ProfessionState("skinning").skill') == 300
    assert c.eval('ns:ProfessionState("jewelcrafting").max') == 375
    assert not c.eval('ns:TabHidden("skinning")')
    no_errors(c)


@test
def skills_arriving_without_an_event_are_found_by_the_retry():
    c = Client()
    c.run('table.insert(MOCK.skills, {"Skinning", 300, 300})')
    c.run("MOCK.advance(3.5)")
    assert c.eval('ns:ProfessionState("skinning").skill') == 300


@test
def a_loading_screen_read_does_not_forget_professions():
    c = Client(**JC_SKIN)
    c.run('MOCK.skills, MOCK.secondary = {}, {}; ns:ScanProfessions()')
    assert c.eval('ns:ProfessionState("jewelcrafting").skill') == 120
    # the trade skill window disagreeing with what we know forces a re-read
    c.run('MOCK.skills = { {"Jewelcrafting", 130, 150} }; '
          'MOCK.trade = { line = "Jewelcrafting", rank = 130, recipes = { 25255 } }; MOCK.fire("TRADE_SKILL_SHOW")')
    assert c.eval('ns:ProfessionState("jewelcrafting").skill') == 130


@test
def professions_report_command():
    c = Client(**JC_SKIN)
    c.clear_chat()
    c.slash("professions")
    text = [strip_colors(m) for m in c.chat()]
    assert any("Jewelcrafting: 120 / 150" in m for m in text), text
    assert any("Skinning: 80 / 150" in m for m in text), text
    c2 = Client()
    c2.clear_chat()
    c2.slash("professions")
    assert any("no profession detected" in strip_colors(m) for m in c2.chat())


@test
def collapsed_headers_are_read_and_restored():
    c = Client(setup='MOCK.collapsed["Professions"] = true; MOCK.collapsed["Secondary Skills"] = true', **JC_SKIN)
    assert c.eval('ns:HasProfession("jewelcrafting")')
    assert c.eval('ns:HasProfession("fishing")')
    assert c.eval('MOCK.collapsed["Professions"]'), "the header was left expanded"
    assert c.eval('MOCK.collapsed["Secondary Skills"]')


@test
def skill_up_rescans_and_recomputes():
    c = Client(**JC_SKIN)
    first = c.eval('ns:GetPath("jewelcrafting").from')
    assert first == 120
    c.run('MOCK.skills[1][2] = 124; MOCK.fire("CHAT_MSG_SKILL", "Your skill in Jewelcrafting has increased to 124.")')
    assert c.eval('ns:ProfessionState("jewelcrafting").skill') == 124
    assert c.eval('ns:GetPath("jewelcrafting").from') == 124
    # learning a new profession shows its tab
    c.run('MOCK.advance(1); table.insert(MOCK.skills, {"Mining", 1, 75}); MOCK.fire("SKILL_LINES_CHANGED")')
    assert not c.eval('ns:TabHidden("mining")')
    no_errors(c)


@test
def known_recipes_come_from_the_trade_skill_window():
    c = Client(**JC_SKIN)
    assert not c.eval('ns:KnowsRecipe("jewelcrafting", 25278)')
    c.run('MOCK.trade = { line = "Jewelcrafting", recipes = { 25255, 25278 } }; MOCK.fire("TRADE_SKILL_SHOW")')
    assert c.eval('ns:KnowsRecipe("jewelcrafting", 25278)')
    assert c.eval('ns:KnownCount("jewelcrafting")') == 2
    # someone else's linked window does not count as yours
    c.run('MOCK.trade = { line = "Jewelcrafting", recipes = { 25283 }, linked = true }; MOCK.fire("TRADE_SKILL_SHOW")')
    assert not c.eval('ns:KnowsRecipe("jewelcrafting", 25283)')
    # it survives a relog
    known = c.eval('FycoProfessionsCharDB.known.jewelcrafting[25278]')
    assert known
    no_errors(c)


# ---------------------------------------------------------------------------
# phase 2: Jewelcrafting end to end
# ---------------------------------------------------------------------------

def recipe(c, prof, spell):
    return c.eval("""(function()
        for _, r in ipairs(ns.Recipes.%s) do if r.sp == %d then return r end end end)()""" % (prof, spell))


@test
def recipe_colours_and_chances():
    c = Client()
    c.run("r = (function() for _, r in ipairs(ns.Recipes.jewelcrafting) do if r.sp == 25255 then return r end end end)()")
    assert c.eval("r.n") == "Delicate Copper Wire"
    for skill, colour, chance in ((1, "orange", 1), (19, "orange", 1), (20, "yellow", 0.75), (34, "yellow", 0.75),
                                  (35, "green", 0.25), (49, "green", 0.25), (50, "grey", 0)):
        assert c.eval("ns:RecipeColor(r, %d)" % skill) == colour, (skill, c.eval("ns:RecipeColor(r, %d)" % skill))
        assert c.eval("ns:RecipeChance(r, %d)" % skill) == chance
    # trainer recipes start orange at their trainer skill, not at 1
    c.run("b = (function() for _, r in ipairs(ns.Recipes.jewelcrafting) do if r.sp == 25278 then return r end end end)()")
    assert c.eval("b.o") == 50 and c.eval("ns:RecipeColor(b, 49)") == "red"


def path_steps(c, expr):
    c.run("_p = %s" % expr)
    n = c.eval("#_p.steps")
    return [dict(kind=c.eval("_p.steps[%d].kind" % i), frm=c.eval("_p.steps[%d].from" % i),
                 to=c.eval("_p.steps[%d].to" % i), count=c.eval("_p.steps[%d].count" % i),
                 name=c.eval("_p.steps[%d].rec and _p.steps[%d].rec.n" % (i, i)))
            for i in range(1, n + 1)]


@test
def jewelcrafting_path_from_1():
    c = Client(skills=[("Jewelcrafting", 1, 75)])
    steps = path_steps(c, 'ns:GetPath("jewelcrafting")')
    assert steps, "no steps"
    assert all(s["kind"] == "craft" for s in steps), steps
    assert steps[0]["frm"] == 1 and steps[-1]["to"] == 75, steps
    for a, b in zip(steps, steps[1:]):
        assert a["to"] == b["frm"], (a, b)
    assert all(s["count"] >= 1 for s in steps)
    # every recipe on it is one this character can get
    ok = c.eval("""(function()
        for _, st in ipairs(_p.steps) do
            local ok, how = ns:RecipeStatus("jewelcrafting", st.rec)
            if not ok or how == "drop" then return st.rec.n end
        end return true end)()""")
    assert ok is True, ok
    no_errors(c)


@test
def rate_changes_the_path():
    c = Client(skills=[("Jewelcrafting", 1, 75)])
    x2 = c.eval('ns:GetPath("jewelcrafting").crafts')
    c.slash("rate 1")
    x1 = c.eval('ns:GetPath("jewelcrafting").crafts')
    assert x1 > x2 * 1.6, (x1, x2)       # about twice as many crafts at x1
    assert c.eval('ns:GetPath("jewelcrafting").rate') == 1


@test
def trainer_checkpoints_and_nearest_trainer():
    c = Client(skills=[("Jewelcrafting", 70, 75)], level=15)
    c.slash("target 300")
    steps = path_steps(c, 'ns:GetPath("jewelcrafting")')
    trains = [s for s in steps if s["kind"] == "train"]
    assert trains, steps
    assert c.eval("_p.steps[%d].cap" % (steps.index(trains[0]) + 1)) == 150
    assert trains[0]["frm"] == 75
    caps = [c.eval("_p.steps[%d].cap" % (i + 1)) for i, s in enumerate(steps) if s["kind"] == "train"]
    assert caps == [150, 225, 300], caps
    assert c.eval("_p.to") == 300
    # levels come from the trainer data
    lvl = c.eval('ns.RankInfo.jewelcrafting[3].lvl')
    assert lvl and lvl >= 10, lvl
    near = c.eval('#ns:NearestTrainers("jewelcrafting", 150, 3)')
    assert near >= 1
    side = c.eval('ns:NearestTrainers("jewelcrafting", 150, 1)[1].t.side')
    assert side in ("H", "B"), side
    no_errors(c)


@test
def faction_decides_vendor_recipes():
    c = Client(faction="Horde")
    # Black Whelp Cloak: sold only by Alliance vendors
    c.run("r = (function() for _, r in ipairs(ns.Recipes.leatherworking) do if r.sp == 9070 then return r end end end)()")
    c.run("_ok, _how, _why = ns:RecipeStatus('leatherworking', r)")
    assert not c.eval("_ok") and c.eval("_why") == "faction", c.eval("_why")
    c.slash("faction alliance")
    assert c.eval("(ns:RecipeStatus('leatherworking', r))")


@test
def reputation_recipes_need_the_standing():
    c = Client()
    c.run("r = (function() for _, r in ipairs(ns.Recipes.alchemy) do if r.sp == 17559 then return r end end end)()")
    c.run("_ok, _how, _why = ns:RecipeStatus('alchemy', r)")
    assert not c.eval("_ok") and c.eval("_why") == "rep", c.eval("_why")
    c.run('MOCK.advance(1.5); MOCK.factions = { {"Argent Dawn", 6} }; MOCK.fire("UPDATE_FACTION")')
    assert c.eval("(ns:RecipeStatus('alchemy', r))")
    c.run('MOCK.advance(1.5); MOCK.factions = { {"Argent Dawn", 5} }; MOCK.fire("UPDATE_FACTION")')
    assert not c.eval("(ns:RecipeStatus('alchemy', r))")


@test
def expanding_headers_does_not_loop():
    # the client fires SKILL_LINES_CHANGED / UPDATE_FACTION when a header is
    # expanded; reacting to our own expanding must not start a loop
    c = Client(setup='MOCK.collapsed["Professions"] = true', **JC_SKIN)
    c.run('MOCK.advance(1); MOCK.skillEvents = 0; MOCK.fire("SKILL_LINES_CHANGED"); MOCK.advance(2)')
    assert c.eval("MOCK.skillEvents") <= 4, c.eval("MOCK.skillEvents")
    assert c.eval('MOCK.collapsed["Professions"]')
    c.run('MOCK.factions = { {"Argent Dawn", 6} }; MOCK.factionCollapsed = true')
    c.run('MOCK.advance(2); MOCK.factionEvents = 0; MOCK.fire("UPDATE_FACTION"); MOCK.advance(2)')
    assert c.eval("MOCK.factionEvents") <= 4, c.eval("MOCK.factionEvents")
    assert c.eval('ns:RepAtLeast("Argent Dawn", "Honored")')
    assert c.eval("MOCK.factionCollapsed"), "the reputation header was left expanded"
    no_errors(c)


@test
def drop_recipes_only_when_allowed():
    c = Client()
    c.run("""_drop = (function() for _, r in ipairs(ns.Recipes.tailoring) do
        if #r.src == 1 and r.src[1].t == "world" then return r end end end)()""")
    assert c.eval("_drop ~= nil")
    assert not c.eval("(ns:RecipeStatus('tailoring', _drop))")
    c.slash("drops")
    assert c.eval("(ns:RecipeStatus('tailoring', _drop))")
    # a recipe you know is always usable
    c.slash("drops")
    c.run('FycoProfessionsCharDB.known = { tailoring = { [_drop.sp] = true } }')
    assert c.eval("(ns:RecipeStatus('tailoring', _drop))")


@test
def shopping_list_counts_bags_and_bank():
    c = Client(skills=[("Jewelcrafting", 1, 75)])
    c.run('_p = ns:GetPath("jewelcrafting")')
    n = c.eval("#_p.shopping")
    assert n >= 1
    item = c.eval("_p.shopping[1].id")
    need = c.eval("_p.shopping[1].need")
    c.run("ns:CountShopping(_p.shopping)")
    assert c.eval("_p.shopping[1].missing") == need
    c.run("MOCK.bags[%d] = 2" % item)
    c.run('MOCK.bank[-1] = { {%d, 3} }; MOCK.fire("BANKFRAME_OPENED"); MOCK.fire("BANKFRAME_CLOSED")' % item)
    c.run("MOCK.bank = {}")          # the bank is closed; what we saw is remembered
    assert c.eval("(ns:ItemHave(%d))" % item) == 5
    c.run("ns:CountShopping(_p.shopping)")
    assert c.eval("_p.shopping[1].missing") == max(0, need - 5)
    assert c.eval("ns:BankKnown()")


@test
def auction_house_full_scan():
    c = Client(skills=[("Jewelcrafting", 1, 75)])
    c.run('AuctionFrame = CreateFrame("Frame", "AuctionFrame", UIParent); MOCK.fire("AUCTION_HOUSE_SHOW")')
    assert c.eval("FycoProfessionsAHScan ~= nil"), "no scan button on the Auction House"
    c.run("MOCK.auctions = { {2840, 20, 2000}, {2840, 5, 750}, {99999999, 1, 5} }")
    assert c.eval("ns:ScanAll()")
    assert c.eval("MOCK.queries[1].all") is True
    c.run('MOCK.fire("AUCTION_ITEM_LIST_UPDATE"); MOCK.advance(1)')
    assert c.eval("(ns:AHPrice(2840))") == 100, c.eval("(ns:AHPrice(2840))")   # 2000 / 20 beats 750 / 5
    assert c.eval("(ns:AHPrice(99999999))") is None, "unknown items are not stored"
    assert c.eval('(ns:ItemCost(2840))') <= 100
    # gathered-only ignores the Auction House
    c.slash("materials gathered")
    cost, kind = c.eval('ns:ItemCost(2840)')
    assert kind != "ah", kind
    # no full scan twice within 15 minutes: falls back to the shopping scan
    c.slash("materials ah")
    c.run("MOCK.canQueryAll = false; MOCK.queries = {}")
    c.slash("scan")
    c.run("MOCK.advance(0.5)")
    assert c.eval("#MOCK.queries") >= 1 and c.eval("MOCK.queries[1].all") is not True
    no_errors(c)


def open_ah(c):
    c.run('AuctionFrame = CreateFrame("Frame", "AuctionFrame", UIParent); MOCK.fire("AUCTION_HOUSE_SHOW")')


def full_scan(c, auctions):
    c.run("MOCK.canQueryAll = true; MOCK.auctions = { %s }" % ", ".join("{%d, %d, %d}" % a for a in auctions))
    assert c.eval("ns:ScanAll()")
    c.run('MOCK.fire("AUCTION_ITEM_LIST_UPDATE"); MOCK.advance(1)')


@test
def prices_account_for_how_many_are_listed():
    # reported from game: paths planned on one cheap listing cost far more.
    # One Deep Peridot at 50c and five at 2s: twenty cost far more than 50c each
    c = Client(skills=[("Jewelcrafting", 300, 375)])
    open_ah(c)
    full_scan(c, [(23079, 1, 50), (23079, 5, 1000)])
    avg, _, supply, cheapest = c.eval("ns:AHPrice(23079)")
    assert supply == 6 and cheapest == 50, (supply, cheapest)
    want = (50 + 5 * 200 + 14 * 200 * 1.25) / 20
    assert abs(avg - want) < 1e-6, (avg, want)
    assert c.eval("(ns:AHPrice(23079, 1))") == 50
    assert c.eval("(ns:AHPrice(23079, 6))") == (50 + 1000) / 6
    # the path uses the price for a real amount, not the single cheap gem
    assert c.eval("(ns:ItemCost(23079))") > 150
    # a later full scan forgets what is no longer listed
    c.run("MOCK.advance(1)")
    full_scan(c, [(2840, 20, 2000)])
    assert c.eval("(ns:AHPrice(23079))") is None
    assert c.eval("(ns:AHPrice(2840))") == 100
    no_errors(c)


@test
def shopping_scan_reads_every_page():
    c = Client(skills=[("Jewelcrafting", 1, 75)])
    open_ah(c)
    c.run("MOCK.canQueryAll = false; MOCK.queries = {}; MOCK.auctions = {}; MOCK.auctionTotal = 120")
    c.slash("scan list")
    for _ in range(8):
        c.run('MOCK.advance(0.2); MOCK.fire("AUCTION_ITEM_LIST_UPDATE")')
    first = c.eval("MOCK.queries[1].name")
    pages = [c.eval("MOCK.queries[%d].page" % i) for i in range(1, c.eval("#MOCK.queries") + 1)
             if c.eval("MOCK.queries[%d].name" % i) == first]
    assert pages[:3] == [0, 1, 2], pages       # 120 results = pages 0, 1, 2
    no_errors(c)


@test
def prospecting_can_be_the_cheaper_source():
    # Saronite Ore at 20s; its gems sell at 1g: prospecting beats buying gems
    auctions = [(36912, 20, 20 * 2000)] + [(g, 20, 20 * 10000) for g in
                (36917, 36920, 36923, 36926, 36929, 36932)]
    c = Client(skills=[("Jewelcrafting", 350, 375)])
    open_ah(c)
    full_scan(c, auctions)
    cost, kind = c.eval("ns:ItemCost(36932)")
    assert kind == "prospect" and cost < 10000, (cost, kind)
    assert c.eval("(ns:ConversionSource(36932))") == 36912
    lines = " ".join(strip_colors(l) for l in c.eval("ns:ItemSourceLines(36932)").values())
    assert "Prospecting: Saronite Ore works out at" in lines, lines
    # a non-jewelcrafter cannot prospect: the gem costs what the AH asks
    c2 = Client(skills=[("Blacksmithing", 350, 375)])
    open_ah(c2)
    full_scan(c2, auctions)
    cost, kind = c2.eval("ns:ItemCost(36932)")
    assert kind == "ah" and cost == 10000, (cost, kind)
    no_errors(c)


@test
def price_command_shows_the_listings():
    c = Client()
    open_ah(c)
    full_scan(c, [(23079, 1, 50), (23079, 5, 1000)])
    c.clear_chat()
    c.slash("price deep peridot")
    text = " ".join(strip_colors(m) for m in c.chat())
    assert "Deep Peridot" in text and "1 at 50c" in text and "5 at 2s 00c" in text, text
    assert "only 6 listed" in text, text
    c.slash("price no such thing")
    assert "no material called" in strip_colors(c.chat()[-1])


@test
def scan_needs_the_auction_house():
    c = Client()
    c.clear_chat()
    c.slash("scan")
    assert any("open the Auction House" in strip_colors(m) for m in c.chat()), c.chat()


@test
def tooltip_line_on_reagents():
    c = Client(skills=[("Jewelcrafting", 1, 75)])
    item = c.eval('ns:GetPath("jewelcrafting").shopping[1].id')
    c.run('GameTooltip:SetHyperlink("item:%d:0:0:0:0:0:0:0:0")' % item)
    c.run('MOCK.run(GameTooltip, "OnTooltipSetItem")')     # fires twice in the real client too
    lines = [strip_colors(l) for l in c.eval("GameTooltip._lines").values()]
    hits = [l for l in lines if "Needed for your Jewelcrafting path" in l]
    assert len(hits) == 1, lines
    c.run('GameTooltip:SetHyperlink("item:6948:0:0:0:0:0:0:0:0")')   # Hearthstone: nothing
    assert not [l for l in c.eval("GameTooltip._lines").values() if "Needed" in l]


@test
def tracker_follows_the_current_step():
    c = Client(skills=[("Jewelcrafting", 1, 75)])
    title, lines = c.eval("ns:TrackerLines()")
    assert "Jewelcrafting 1/75 (x2)" in title, title
    text = [strip_colors(l) for l in lines.values()]
    assert text[0].startswith("Make "), text
    assert "until" in text[1]
    assert any("/" in l for l in text[2:]), text          # have / need per material
    no_errors(c)


@test
def craft_view_modes_render():
    c = Client(skills=[("Jewelcrafting", 120, 150)])
    c.run('ns:OpenWindow("jewelcrafting")')
    c.run('_v = ns:TabPane("jewelcrafting").view')
    assert c.eval("_v.left:Count()") >= 1
    assert c.eval("_v.right:Count()") >= 3
    assert "Jewelcrafting" in c.eval("_v.title:GetText()")
    for i in range(1, c.eval("#_v.buttons") + 1):
        c.run('MOCK.run(_v.buttons[%d], "OnClick")' % i)
        assert c.eval("_v.left:Count()") >= 1, c.eval("_v.mode")
    # clicking a row selects it and shows its detail
    c.run('_v.mode = "path"; _v:Refresh(); _v.left.data[2].onClick(_v.left.data[2])')
    assert c.eval("_v.selected.path") == 2
    no_errors(c)


@test
def path_to_chat_is_plain():
    c = Client(skills=[("Jewelcrafting", 120, 150)])
    c.clear_chat()
    c.slash("path")
    text = c.chat()
    assert any("Jewelcrafting 120/150" in strip_colors(m) for m in text), text
    for m in text:
        stray = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", m)
        assert "|" not in stray, m
    c.slash("path alch")
    assert "do not have" in strip_colors(c.chat()[-1])


# ---------------------------------------------------------------------------
# phase 3: every crafting profession
# ---------------------------------------------------------------------------

CRAFT = ["Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Inscription", "Jewelcrafting",
         "Leatherworking", "Tailoring"]


@test
def every_crafting_profession_to_450():
    report = []
    for rate in (2, 1):
        for name in CRAFT + ["Cooking", "First Aid"]:
            key = name.lower().replace(" ", "")
            c = Client(skills=[(name, 1, 75)] if name not in ("Cooking", "First Aid") else (),
                       secondary=[(name, 1, 75)] if name in ("Cooking", "First Aid") else ())
            c.slash("rate %d" % rate)
            c.slash("target 450")
            steps = path_steps(c, 'ns:GetPath("%s")' % key)
            stuck = [s for s in steps if s["kind"] == "stuck"]
            crafts = [s for s in steps if s["kind"] == "craft"]
            assert crafts, name
            # the first rank must always be possible from trainer recipes alone
            assert not stuck or stuck[0]["frm"] >= 75, (name, stuck)
            report.append("%s x%d: %d steps, %s" % (name, rate, len(steps),
                          ("stuck at %d" % stuck[0]["frm"]) if stuck else "reaches %d" % c.eval("_p.to")))
            no_errors(c)
    print("      " + "\n      ".join(report))


@test
def all_professions_browser_previews():
    c = Client(**JC_SKIN)
    for i in range(1, c.eval("#ns.Professions") + 1):
        key = c.eval("ns.Professions[%d].key" % i)
        assert c.eval('ns:BrowseProfession("%s")' % key)
        c.run("_v = ns:BrowserView()")
        assert c.eval("_v:IsShown()"), key
        assert c.eval("_v.left:Count()") >= 1, key
    c.run('ns:BrowseProfession("alchemy")')
    assert "preview" in strip_colors(c.eval("ns:BrowserView().title:GetText()"))
    c.run('ns:BrowseProfession("jewelcrafting")')
    assert "120 / 150" in strip_colors(c.eval("ns:BrowserView().title:GetText()"))
    no_errors(c)


# ---------------------------------------------------------------------------
# phase 4: gathering
# ---------------------------------------------------------------------------

@test
def skinning_skill_formula():
    c = Client()
    for lvl, skill in ((1, 1), (10, 1), (11, 10), (15, 50), (20, 100), (21, 105), (60, 300), (80, 400)):
        assert c.eval("ns:SkinSkillFor(%d)" % lvl) == skill, lvl
    for req, skill, colour in ((100, 99, "red"), (100, 100, "orange"), (100, 125, "yellow"),
                               (100, 150, "green"), (100, 200, "grey")):
        assert c.eval('ns:GatherColor(%d, %d)' % (req, skill)) == colour, (req, skill)


@test
def gathering_zones_rank_and_move_on():
    c = Client(skills=[("Mining", 1, 75), ("Skinning", 1, 75)], level=10)
    zones = c.eval('ns:RankZones("mining", 1)')
    assert zones[1], "no mining zones at skill 1"
    best = c.eval('ns.Zones[ns:RankZones("mining", 1)[1].zone].n')
    assert best, best
    # at 1 only Copper gives skill-ups; the best zone has copper
    has_copper = c.eval("""(function()
        local z = ns:RankZones("mining", 1)[1].zone
        for _, n in ipairs(ns.Nodes.mining) do
            if n.n == "Copper Vein" then for _, zc in ipairs(n.z) do if zc[1] == z then return true end end end
        end return false end)()""")
    assert has_copper
    at = c.eval('(ns:MoveOnAt("mining", ns:RankZones("mining", 1)[1].zone, 1, 450))')
    assert at and 1 < at <= 450, at
    # herbalism and skinning rank too, and a high skill ranks higher-level zones
    assert c.eval('#ns:RankZones("herbalism", 1)') > 0
    low = c.eval('ns.Zones[ns:RankZones("skinning", 1)[1].zone].hi or 0')
    high = c.eval('ns.Zones[ns:RankZones("skinning", 300)[1].zone].hi or 0')
    assert high > low, (low, high)
    no_errors(c)


@test
def gathering_views_and_tracker():
    c = Client(skills=[("Mining", 50, 75), ("Skinning", 75, 75)], level=20)
    for key in ("mining", "skinning"):
        c.run('ns:OpenWindow("%s"); _v = ns:TabPane("%s").view' % (key, key))
        assert c.eval("_v.left:Count()") >= 1, key
        for i in range(1, c.eval("#_v.buttons") + 1):
            c.run('MOCK.run(_v.buttons[%d], "OnClick")' % i)
            assert c.eval("_v.left:Count()") >= 1, (key, c.eval("_v.mode"))
    # at the cap, the view and tracker say to train
    c.run('ns:SetChar("tracked", "skinning")')
    title, lines = c.eval("ns:TrackerLines()")
    assert "Train Journeyman" in strip_colors(lines[1]), [strip_colors(x) for x in lines.values()]
    c.run('ns:SetChar("tracked", "mining")')
    title, lines = c.eval("ns:TrackerLines()")
    assert strip_colors(lines[1]).startswith("Go to "), [strip_colors(x) for x in lines.values()]
    no_errors(c)


# ---------------------------------------------------------------------------
# phase 5: secondary professions
# ---------------------------------------------------------------------------

@test
def fishing_model_and_view():
    c = Client(secondary=[("Fishing", 40, 75), ("Cooking", 1, 75), ("First Aid", 1, 75)])
    assert c.eval("ns:FishSkillUpChance(40)") == 1
    assert abs(c.eval("ns:FishSkillUpChance(300)") - 0.1) < 1e-9
    assert c.eval("ns:FishCatchChance(100, 50)") == 1
    assert abs(c.eval("ns:FishCatchChance(50, 100)") - 0.25) < 1e-9
    c.run('ns:OpenWindow("fishing"); _v = ns:TabPane("fishing").view')
    assert c.eval("_v.left:Count()") > 10
    assert "Skill-up chance per catch: 100%" in strip_colors(c.eval("_v.summary:GetText()"))
    for key in ("cooking", "firstaid"):
        assert c.eval('#ns:GetPath("%s").steps' % key) >= 1, key
    no_errors(c)


# ---------------------------------------------------------------------------
# phase 6: extras
# ---------------------------------------------------------------------------

@test
def extras_data_and_views():
    c = Client(skills=[("Jewelcrafting", 350, 375), ("Enchanting", 1, 75)])
    assert c.eval("#ns.Prospect[2770]") >= 3, "copper ore prospects to at least three gems"
    assert c.eval("#ns.Mill[765]") >= 1, "Silverleaf mills to a pigment"
    assert c.eval("#ns.Disenchant[10940]") >= 1, "Strange Dust has disenchant sources"
    assert c.eval("#ns.JCDaily.rewards") >= 5
    assert c.eval("#ns.JCDaily.quests") >= 1
    c.run('ns:OpenWindow("jewelcrafting"); _v = ns:TabPane("jewelcrafting").view; _v.mode = "extras"; _v:Refresh()')
    assert "Dalaran" in strip_colors(c.eval("_v.right.data[1].text"))
    c.run('_v.selected.extras = 2770; _v:Refresh()')
    assert c.eval("_v.right:Count()") >= 4
    c.run('ns:OpenWindow("enchanting"); _v = ns:TabPane("enchanting").view; _v.mode = "extras"; _v:Refresh()')
    assert c.eval("_v.right:Count()") >= 2
    no_errors(c)


# ---------------------------------------------------------------------------
# map pins
# ---------------------------------------------------------------------------

ASHENVALE = 331


def in_ashenvale(skill=100, extra=""):
    """A skinner standing in Ashenvale with the world map closed."""
    c = Client(skills=[("Skinning", skill, 150)], level=30, setup=extra or None)
    c.run('MOCK.playerMapFile = "Ashenvale"; MOCK.mapFile = nil')
    c.run('MOCK.advance(2.5)')          # the zone check runs every 2 s
    assert c.eval("ns:PlayerZone()") == ASHENVALE
    return c, "Ashenvale"


def pin_names(c, zone=ASHENVALE):
    c.run("_pins = ns:PinsFor(%d)" % zone)
    return {c.eval("_pins[%d].name" % i) for i in range(1, c.eval("#_pins") + 1)}


@test
def pins_follow_skill_level_range_and_hand_picks():
    c, _ = in_ashenvale(skill=100)
    names = pin_names(c)
    assert names, "no automatic skinning pins in Ashenvale at skill 100"
    colours = {c.eval("_pins[%d].color" % i) for i in range(1, c.eval("#_pins") + 1)}
    assert colours <= {"orange", "yellow", "green"}, colours
    # every pin is a position on the zone map
    for i in range(1, min(50, c.eval("#_pins")) + 1):
        x, y = c.eval("_pins[%d].x" % i), c.eval("_pins[%d].y" % i)
        assert 0 <= x <= 1 and 0 <= y <= 1, (x, y)
    # at skill 1 nothing there can be skinned: no automatic pins
    c1, _ = in_ashenvale(skill=1)
    assert not pin_names(c1)
    # a level range pins exactly the mobs of those levels
    c1.slash("pins skin 20 22")
    ranged = pin_names(c1)
    assert ranged, "no mobs of level 20-22 in Ashenvale"
    for mob in c1.eval("ns.SkinSpawns[%d]" % ASHENVALE).values():
        overlaps = mob["hi"] >= 20 and mob["lo"] <= 22
        assert (mob["n"] in ranged) == overlaps, mob["n"]
    c1.slash("pins skin auto")
    assert not pin_names(c1)
    # a hand-picked mob shows even with automatic pins off
    first = c1.eval("ns.SkinSpawns[%d][1].n" % ASHENVALE)
    c1.run('ns:Set("pins", "auto", false)')
    assert c1.eval('ns:TogglePin("skinning", "%s")' % first)
    assert pin_names(c1) == {first}
    c1.slash("pins clear")
    assert not pin_names(c1)
    no_errors(c1)


@test
def pins_on_the_world_map():
    c, mapfile = in_ashenvale(skill=100)
    c.run('MOCK.mapFile = "%s"; WorldMapFrame:Show()' % mapfile)
    n = c.eval("ns:WorldPinCount()")
    assert n > 0, "no pins drawn on the world map"
    assert n == min(800, c.eval("#ns:PinsFor(%d)" % ASHENVALE))
    # anchored inside the map canvas
    pts = c.eval("""(function()
        local out = {}
        for _, f in ipairs(MOCK.frames) do
            if f._parent == WorldMapButton and f._shown and f.data then
                local p = f._points[#f._points]
                out[#out + 1] = p[4] .. "," .. p[5]
            end
        end return table.concat(out, ";") end)()""")
    for pair in pts.split(";")[:100]:
        x, y = (float(v) for v in pair.split(","))
        assert 0 <= x <= 1002 and -668 <= y <= 0, pair
    # another zone on the map: its own pins; a continent: none
    c.run('MOCK.mapFile = "Tanaris"; MOCK.fire("WORLD_MAP_UPDATE")')
    tanaris = c.eval("ns:WorldPinCount()")
    assert tanaris == min(800, c.eval("#ns:PinsFor(440)")), tanaris
    c.run('MOCK.mapFile = "Kalimdor"; MOCK.fire("WORLD_MAP_UPDATE")')
    assert c.eval("ns:WorldPinCount()") == 0
    c.slash("pins world")
    c.run('MOCK.mapFile = "%s"; MOCK.fire("WORLD_MAP_UPDATE")' % mapfile)
    assert c.eval("ns:WorldPinCount()") == 0, "world pins still drawn after switching them off"
    no_errors(c)


@test
def pins_in_tanaris_hand_picked_and_auto():
    # the case reported from game: a skinner in Tanaris, pins on, nothing shown
    c = Client(skills=[("Skinning", 225, 225)], level=45)
    c.run('MOCK.playerMapFile = "Tanaris"; MOCK.mapFile = nil; MOCK.advance(2.5)')
    assert c.eval("ns:PlayerZone()") == 440
    assert c.eval("#ns:PinsFor(440)") > 0, "no automatic pins in Tanaris at skinning 225"
    mob = c.eval("ns.SkinSpawns[440][1].n")
    c.run('ns:Set("pins", "auto", false); ns:TogglePin("skinning", "%s")' % mob)
    c.run('_p = ns:PinsFor(440)[1]; MOCK.mapX, MOCK.mapY = _p.x, _p.y; MOCK.advance(0.3)')
    assert c.eval("ns:MinimapPinCount()") >= 1
    c.run('MOCK.mapFile = "Tanaris"; WorldMapFrame:Show()')
    assert c.eval("ns:WorldPinCount()") == c.eval("#ns:PinsFor(440)")
    # the diagnostic prints what the game reports
    c.run("WorldMapFrame:Hide()")
    c.clear_chat()
    c.slash("pins debug")
    text = " ".join(strip_colors(m) for m in c.chat())
    assert "map file Tanaris" in text and "Tanaris" in text and "pins here:" in text, text
    no_errors(c)


@test
def player_zone_falls_back_to_its_name():
    # a map the data does not know by name: the zone text still finds it
    c = Client(skills=[("Skinning", 100, 150)])
    c.run('MOCK.playerMapFile = "SomethingNew"; MOCK.zone = "Ashenvale"; MOCK.advance(2.5)')
    assert c.eval("ns:PlayerZone()") == ASHENVALE


@test
def pins_on_the_minimap():
    c, _ = in_ashenvale(skill=100)
    c.run("_p = ns:PinsFor(%d)[1]" % ASHENVALE)
    # stand on a spawn point: it is drawn at the minimap's centre
    c.run("MOCK.mapX, MOCK.mapY = _p.x, _p.y; MOCK.advance(0.3)")
    assert c.eval("ns:MinimapPinCount()") >= 1
    centre = c.eval("""(function()
        for _, f in ipairs(MOCK.frames) do
            if f._parent == Minimap and f._shown and f.data == _p then
                local pt = f._points[#f._points]
                return math.abs(pt[4]) + math.abs(pt[5])
            end
        end end)()""")
    assert centre is not None and centre < 0.01, centre
    # nothing drawn outside the minimap's circle
    c.run("MOCK.zoom = 5; MOCK.advance(0.3)")
    far = c.eval("""(function()
        local worst = 0
        for _, f in ipairs(MOCK.frames) do
            if f._parent == Minimap and f._shown and f.data then
                local pt = f._points[#f._points]
                worst = math.max(worst, math.sqrt(pt[4] ^ 2 + pt[5] ^ 2))
            end
        end return worst end)()""")
    assert far <= 70, far
    # a rotating minimap works too
    c.run('MOCK.cvars.rotateMinimap = "1"; MOCK.facing = 1.2; MOCK.advance(0.3)')
    assert c.eval("ns:MinimapPinCount()") >= 1
    # in an instance (no map position) nothing is drawn
    c.run("MOCK.mapX, MOCK.mapY = 0, 0; MOCK.advance(0.3)")
    assert c.eval("ns:MinimapPinCount()") == 0
    # switched off
    c.run("MOCK.mapX, MOCK.mapY = _p.x, _p.y")
    c.slash("pins minimap")
    c.run("MOCK.advance(0.3)")
    assert c.eval("ns:MinimapPinCount()") == 0
    c.slash("pins minimap")
    c.slash("pins")                     # the master switch
    c.run("MOCK.advance(0.3)")
    assert c.eval("ns:MinimapPinCount()") == 0
    no_errors(c)


@test
def pin_from_the_skinning_tab():
    c, _ = in_ashenvale(skill=100)
    c.run('ns:OpenWindow("skinning"); _v = ns:TabPane("skinning").view')
    c.run('_v.selected.zones = %d; _v:Refresh()' % ASHENVALE)
    row = c.eval("_v.right.data[2]")
    name_text = strip_colors(row["text"])
    c.run("_v.right.data[2].onClick(_v.right.data[2])")
    assert "[pinned]" in strip_colors(c.eval("_v.right.data[2].text")), name_text
    assert c.eval('next(FycoProfessionsCharDB.pinned) ~= nil')
    c.run("_v.right.data[2].onClick(_v.right.data[2])")
    assert "[pinned]" not in strip_colors(c.eval("_v.right.data[2].text"))
    no_errors(c)


@test
def every_path_computes_quickly():
    import time as _t
    c = Client(skills=[("Jewelcrafting", 1, 75), ("Tailoring", 1, 75)])
    c.slash("target 450")
    t0 = _t.time()
    c.run('ns:InvalidatePaths(); ns:GetPath("jewelcrafting"); ns:GetPath("tailoring")')
    dt = _t.time() - t0
    assert dt < 5, "two full paths took %.1f s" % dt
    print("      two paths 1-450: %.2f s in lupa" % dt)


def main():
    only = sys.argv[1:]
    passed = failed = 0
    for t in TESTS:
        if only and t.__name__ not in only:
            continue
        try:
            t()
            print("PASS  " + t.__name__)
            passed += 1
        except Exception as e:
            failed += 1
            print("FAIL  " + t.__name__)
            msg = str(e) or traceback.format_exc()
            for line in msg.splitlines()[:25]:
                print("      " + line)
    # every frame method the addon used that the mock only pretended to have
    c = Client()
    c.run('ns:OpenWindow("all"); MOCK.advance(0.5)')
    for i in range(1, c.eval("#MOCK.panels") + 1):
        c.run('MOCK.run(MOCK.panels[%d], "OnShow")' % i)
    um = c.eval("MOCK.unknownMethods")
    names = sorted(um.keys())
    print("\n%d passed, %d failed" % (passed, failed))
    if names:
        print("frame methods used but not modelled by the mock (check they exist in 3.3.5a):")
        print("  " + ", ".join(names))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
