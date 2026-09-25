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

    def __init__(self, faction="Horde", saved=None):
        self.lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(self.dofile_src(os.path.join(ROOT, "tests", "wowmock.lua")))
        self.lua.execute('MOCK.faction = "%s"' % faction)
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
