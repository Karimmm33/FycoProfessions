--[[ FycoProfessions - Core.lua
     Shared plumbing every module reads, built the same way as FycoPvE's core:
       1. one event dispatcher and one throttled ticker for the whole addon
       2. a message bus, so modules react to each other without knowing each other
       3. the module registry, and settings with per-key defaults
       4. the guide settings every path depends on: skill-up rate, target,
          faction and where materials may come from
     3.3.5a notes: no C_Timer. Everything runs off events and the one ticker. ]]

local ADDON, ns = ...

local tinsert = table.insert

----------------------------------------------------------------------
-- event dispatch
----------------------------------------------------------------------

local frame    = CreateFrame("Frame", ADDON .. "Core", UIParent)
local handlers = {}

--- Register fn to run on event. Several modules may take the same event.
function ns:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	tinsert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		list[i](event, ...)
	end
end)

----------------------------------------------------------------------
-- one ticker, 10 Hz, shared
----------------------------------------------------------------------

local tickers, dead, acc = {}, {}, 0
local current

function ns:OnTick(fn)
	tinsert(tickers, fn)
end

local function RunTickers(now)
	for i = 1, #tickers do
		if not dead[i] then
			current = i
			tickers[i](now)
		end
	end
end

frame:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.1 then return end
	acc = 0

	-- One module's bug must not silently stop every other module's updates.
	-- Retire the offender, say so, let the rest run. (Lesson from FycoPvP.)
	local ok, err = pcall(RunTickers, GetTime())
	if not ok then
		dead[current or 0] = true
		ns:Print("|cffff4040a module errored and its updates were stopped:|r")
		ns:Print("  " .. tostring(err))
		ns:Print("|cff808080Everything else keeps running. |cffffff00/reload|r to try it again.|r")
	end
end)

----------------------------------------------------------------------
-- output
----------------------------------------------------------------------

function ns:Print(...)
	local msg = ""
	for i = 1, select("#", ...) do
		msg = msg .. tostring(select(i, ...)) .. " "
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffFycoProfessions|r " .. msg)
end

function ns:Debug(...)
	if FycoProfessionsDB and FycoProfessionsDB.debug then self:Print("|cff808080dbg|r", ...) end
end

----------------------------------------------------------------------
-- message bus
----------------------------------------------------------------------

local subs = {}

function ns:Subscribe(msg, fn)
	if not subs[msg] then subs[msg] = {} end
	tinsert(subs[msg], fn)
end

function ns:Fire(msg, ...)
	local list = subs[msg]
	if not list then return end
	for i = 1, #list do
		list[i](...)
	end
end

----------------------------------------------------------------------
-- module registry
----------------------------------------------------------------------

ns.modules, ns.moduleOrder = {}, {}

--- `order` fixes load order. pairs() order is unspecified, and a module whose
--- OnLoad expects another's to have run first must not depend on luck.
function ns:Module(name, order)
	local m = { name = name, order = order or 50 }
	ns.modules[name] = m
	tinsert(ns.moduleOrder, m)
	return m
end

--- Is this module switched on right now? Checked at use time rather than only
--- at load, so the checkboxes take effect immediately.
function ns:Enabled(name)
	return FycoProfessionsDB and FycoProfessionsDB.enabled and FycoProfessionsDB.enabled[name] ~= false
end

--- Settings panels a module contributes. Registered at file load, built by
--- Modules/Options.lua at login -- so a new module adds its own panel without
--- touching the options file. build(L, R, panel) receives two layout columns.
ns.OptionPanels = {}

function ns:RegisterOptions(key, title, order, build)
	tinsert(ns.OptionPanels, { key = key, title = title, order = order, build = build })
end

----------------------------------------------------------------------
-- settings
----------------------------------------------------------------------

-- Every setting's default, by section. Read through ns:Get, so a key added
-- in a later version works at once without resetting saved choices.
ns.Defaults = {
	general = {
		minimap = true,
		minimapAngle = 200,
		windowScale = 1.0,
		loginMessage = true,
	},
	guide = {
		rate = 2,             -- skill points per skill-up (this realm: 2)
		target = "rank",      -- "rank" = the cap of the rank you have, or a skill number
		materials = "ah",     -- "ah" buy or gather, "gathered" gathered materials only
		drops = false,        -- also use recipes that only drop (or come from the Auction House)
	},
	pins = {
		world = true,         -- pins on the world map
		minimap = true,       -- pins on the minimap
		auto = true,          -- pin what still gives skill-ups
		mining = true, herbalism = true, skinning = true,
		skinMin = 0,          -- skinnable mob level range; both 0 = automatic
		skinMax = 0,
		worldSize = 14,
		miniSize = 12,
	},
	tracker = {
		shown = true,
		locked = false,
		scale = 1.0,
	},
}

-- Per-character settings: things that belong to one character, not the account.
ns.CharDefaults = {
	faction = "auto",         -- "auto" = your own, or "Alliance" / "Horde"
}

-- module switches, written one key at a time so a module added later turns
-- itself on without resetting what has been saved
local moduleDefaults = { tracker = true, tooltip = true, pins = true }

function ns:Get(section, key)
	local s = FycoProfessionsDB and FycoProfessionsDB[section]
	if s and s[key] ~= nil then return s[key] end
	local d = ns.Defaults[section]
	if d then return d[key] end
end

function ns:Set(section, key, value)
	FycoProfessionsDB[section] = FycoProfessionsDB[section] or {}
	FycoProfessionsDB[section][key] = value
	ns:Fire("SettingChanged", section, key, value)
end

function ns:GetChar(key)
	local v = FycoProfessionsCharDB and FycoProfessionsCharDB[key]
	if v ~= nil then return v end
	return ns.CharDefaults[key]
end

function ns:SetChar(key, value)
	FycoProfessionsCharDB[key] = value
	ns:Fire("SettingChanged", "char", key, value)
end

----------------------------------------------------------------------
-- the guide settings, validated in one place
----------------------------------------------------------------------

--- Points per skill-up. Anything saved that is not an offered rate falls
--- back to the default rather than producing a path for a rate nobody chose.
function ns:Rate()
	local r = ns:Get("guide", "rate")
	for i = 1, #ns.Rates do
		if ns.Rates[i] == r then return r end
	end
	return ns.Defaults.guide.rate
end

function ns:SetRate(r)
	for i = 1, #ns.Rates do
		if ns.Rates[i] == r then
			ns:Set("guide", "rate", r)
			return true
		end
	end
	return false
end

--- "rank" or a skill number from 1 to MAX_SKILL.
function ns:Target()
	local t = ns:Get("guide", "target")
	if t == "rank" then return t end
	t = tonumber(t)
	if t and t >= 1 and t <= ns.MAX_SKILL then return math.floor(t) end
	return "rank"
end

function ns:SetTarget(t)
	if t ~= "rank" then
		t = tonumber(t)
		if not t or t < 1 or t > ns.MAX_SKILL then return false end
		t = math.floor(t)
	end
	ns:Set("guide", "target", t)
	return true
end

function ns:TargetText()
	local t = ns:Target()
	return t == "rank" and "your rank's cap" or tostring(t)
end

--- The faction whose trainers and vendors the guide uses.
function ns:Faction()
	local f = ns:GetChar("faction")
	if f == "Alliance" or f == "Horde" then return f end
	return UnitFactionGroup("player") or "Alliance"
end

function ns:FactionIsAuto()
	local f = ns:GetChar("faction")
	return f ~= "Alliance" and f ~= "Horde"
end

function ns:SetFaction(f)
	if f ~= "Alliance" and f ~= "Horde" then f = "auto" end
	ns:SetChar("faction", f)
end

function ns:Materials()
	return ns:Get("guide", "materials") == "gathered" and "gathered" or "ah"
end

ns.MaterialsText = { ah = "Buy or gather", gathered = "Gathered only" }

--- A short "x2, target: your rank's cap, Horde" for headers and chat.
function ns:GuideText()
	return string.format("x%d, target: %s, %s%s", ns:Rate(), ns:TargetText(), ns:Faction(),
		ns:Materials() == "gathered" and ", gathered materials only" or "")
end

----------------------------------------------------------------------
-- saved variables + login
----------------------------------------------------------------------

ns:On("PLAYER_LOGIN", function()
	FycoProfessionsDB = FycoProfessionsDB or {}
	FycoProfessionsCharDB = FycoProfessionsCharDB or {}
	FycoProfessionsDB.enabled = FycoProfessionsDB.enabled or {}
	for k, v in pairs(moduleDefaults) do
		if FycoProfessionsDB.enabled[k] == nil then FycoProfessionsDB.enabled[k] = v end
	end

	-- Each OnLoad runs inside a pcall: one broken module costs that module and
	-- says so, instead of aborting this handler and every module after it --
	-- which in FycoPvP once made the whole addon vanish from Interface Options.
	table.sort(ns.moduleOrder, function(a, b) return a.order < b.order end)
	for i = 1, #ns.moduleOrder do
		local m = ns.moduleOrder[i]
		if m.OnLoad then
			local ok, err = pcall(m.OnLoad, m)
			if ok then
				ns:Debug("module loaded:", m.name)
			else
				ns:Print("|cffff4444module '" .. m.name .. "' failed to load:|r " .. tostring(err))
			end
		end
	end

	if ns:Get("general", "loginMessage") then
		ns:Print("v" .. (GetAddOnMetadata(ADDON, "Version") or "?") .. " - " .. ns:GuideText()
		      .. ". |cffffff00/fprof|r to open.")
	end
end)

----------------------------------------------------------------------
-- slash
----------------------------------------------------------------------

SLASH_FYCOPROF1 = "/fprof"
SLASH_FYCOPROF2 = "/fycoprof"

local Y = "|cffffff00"

local function Help()
	ns:Print("commands:")
	ns:Print("  " .. Y .. "/fprof|r            - open the FycoProfessions window")
	ns:Print("  " .. Y .. "/fprof options|r    - open the settings")
	ns:Print("  " .. Y .. "/fprof rate [1 or 2]|r - show or set skill points per skill-up")
	ns:Print("  " .. Y .. "/fprof target [rank or 1-450]|r - show or set where guides stop")
	ns:Print("  " .. Y .. "/fprof faction [auto, alliance, horde]|r - whose trainers and vendors to use")
	ns:Print("  " .. Y .. "/fprof materials [ah or gathered]|r - allow buying materials, or gathered only")
	ns:Print("  " .. Y .. "/fprof drops|r      - also use recipes that only drop, on or off")
	ns:Print("  " .. Y .. "/fprof path [profession]|r - the next steps, in chat")
	ns:Print("  " .. Y .. "/fprof scan [list]|r - scan Auction House prices (Auction House open)")
	ns:Print("  " .. Y .. "/fprof price <item>|r - what your last scan saw for one material")
	ns:Print("  " .. Y .. "/fprof tracker [show, hide, lock, unlock, reset]|r - the step tracker")
	ns:Print("  " .. Y .. "/fprof pins [world, minimap, skin <min> <max>, skin auto, clear, debug]|r - map pins")
	ns:Print("  " .. Y .. "/fprof professions|r - which professions and skill levels were detected")
	ns:Print("  " .. Y .. "/fprof minimap|r    - show or hide the minimap button")
	ns:Print("  " .. Y .. "/fprof debug|r      - toggle debug output")
end

SlashCmdList.FYCOPROF = function(input)
	input = input or ""
	local cmd, rest = input:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	rest = (rest or ""):lower()

	if cmd == "" then
		if ns.ToggleWindow then ns:ToggleWindow() end

	elseif cmd == "options" or cmd == "config" or cmd == "settings" then
		if ns.OpenOptions then ns:OpenOptions() end

	elseif cmd == "rate" then
		local r = tonumber((rest:gsub("^x", "")))
		if rest ~= "" and not ns:SetRate(r) then
			ns:Print("the rate can be " .. Y .. "1|r or " .. Y .. "2|r")
		end
		ns:Print("skill points per skill-up: " .. Y .. "x" .. ns:Rate() .. "|r")

	elseif cmd == "target" then
		if rest ~= "" and not ns:SetTarget(rest == "rank" and "rank" or rest) then
			ns:Print("usage: " .. Y .. "/fprof target rank|r or " .. Y .. "/fprof target <1-450>|r")
		end
		ns:Print("guides stop at: " .. Y .. ns:TargetText() .. "|r")

	elseif cmd == "faction" then
		if rest == "alliance" then ns:SetFaction("Alliance")
		elseif rest == "horde" then ns:SetFaction("Horde")
		elseif rest == "auto" then ns:SetFaction("auto")
		elseif rest ~= "" then ns:Print("usage: " .. Y .. "/fprof faction auto, alliance or horde|r") end
		ns:Print("faction: " .. Y .. ns:Faction() .. "|r" .. (ns:FactionIsAuto() and " (yours)" or " (chosen)"))

	elseif cmd == "materials" then
		if rest == "ah" or rest == "gathered" then
			ns:Set("guide", "materials", rest)
		elseif rest ~= "" then
			ns:Print("usage: " .. Y .. "/fprof materials ah|r or " .. Y .. "gathered|r")
		end
		ns:Print("materials: " .. Y .. ns.MaterialsText[ns:Materials()] .. "|r")

	elseif cmd == "drops" then
		ns:Set("guide", "drops", not ns:Get("guide", "drops"))
		ns:Print("recipes from drops: " .. Y .. (ns:Get("guide", "drops") and "used" or "not used") .. "|r")

	elseif cmd == "path" then
		if ns.PathToChat then ns:PathToChat(rest) end

	elseif cmd == "scan" then
		if not ns.ScanAll then
			ns:Print("prices module is off")
		elseif rest == "list" then
			ns:ScanShopping()
		elseif not ns:ScanAll() and ns:AuctionOpen() then
			ns:ScanShopping()
		end

	elseif cmd == "price" then
		if ns.PriceReport then ns:PriceReport(rest) end

	elseif cmd == "professions" then
		if ns.ProfessionsReport then ns:ProfessionsReport() end

	elseif cmd == "pins" then
		if ns.PinsCommand then ns:PinsCommand(rest) end

	elseif cmd == "tracker" then
		if not ns.TrackerCommand then
			ns:Print("tracker module is off")
		else
			ns:TrackerCommand(rest)
		end

	elseif cmd == "minimap" then
		ns:Set("general", "minimap", not ns:Get("general", "minimap"))
		ns:Print("minimap button " .. (ns:Get("general", "minimap") and "shown" or "hidden"))

	elseif cmd == "debug" then
		FycoProfessionsDB.debug = not FycoProfessionsDB.debug
		ns:Print("debug " .. (FycoProfessionsDB.debug and "on" or "off"))

	else
		Help()
	end
end
