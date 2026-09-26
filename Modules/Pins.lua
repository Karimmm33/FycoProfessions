--[[ FycoProfessions - Modules/Pins.lua
     Pins on the world map and the minimap for gathering nodes and skinnable
     mobs, from the spawn points in Data/Spawns.lua.

     WHAT IS PINNED, in the zone the map shows (or you stand in):
       - automatically: every node and skinnable mob that still gives you
         skill-ups (orange, yellow, green), for each gathering profession you
         have and have not switched off here;
       - skinnable mobs in a level range, when you set one (instead of auto);
       - anything you pinned by hand by clicking it in the Skinning, Mining
         or Herbalism tab (per character, until you unpin it).
     Each pin shows its item or pelt icon on a square in its difficulty
     colour; hovering it says what it is and what skill it needs.

     WORLD MAP. Pins sit on WorldMapButton, the map's own drawing surface,
     so they follow the map however an addon like Mapster scales or moves
     the window.

     MINIMAP. The player's zone position (GetPlayerMapPosition) and the
     zone's size in yards (WorldMapArea bounds) give each pin's offset in
     yards; the minimap's zoom gives yards per pixel (the same table
     Astrolabe uses), and a rotating minimap is turned by GetPlayerFacing.
     Pins outside the minimap's circle are hidden.

     Spawns are the stock database's, and mobs wander: a pin marks where
     something spawns, not where it stands now.                          ]]

local _, ns = ...
local M = ns:Module("pins", 45)
local UI = ns.UI

local MAX_WORLD, MAX_MINI = 800, 120
local SKIN_ICON = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01"
local COLOR = {
	orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 },
	grey = { 0.5, 0.5, 0.5 }, red = { 1, 0.13, 0.13 },
}
-- minimap diameter in yards per zoom level (0-5), outdoors and indoors
local MINI_OUT = { 466.6667, 400, 333.3333, 266.6667, 200, 133.3333 }
local MINI_IN = { 300, 240, 180, 120, 80, 50 }

----------------------------------------------------------------------
-- what to pin
----------------------------------------------------------------------

local function PinKey(kind, name)
	return kind .. "|" .. name
end

function ns:IsPinned(kind, name)
	local p = FycoProfessionsCharDB and FycoProfessionsCharDB.pinned
	return p and p[PinKey(kind, name)] or false
end

local cache = {}

local function Invalidate()
	cache = {}
	ns:Fire("PinsChanged")
end

function ns:TogglePin(kind, name)
	FycoProfessionsCharDB.pinned = FycoProfessionsCharDB.pinned or {}
	local k = PinKey(kind, name)
	FycoProfessionsCharDB.pinned[k] = not FycoProfessionsCharDB.pinned[k] or nil
	Invalidate()
	return FycoProfessionsCharDB.pinned[k] == true
end

function ns:ClearPins()
	FycoProfessionsCharDB.pinned = {}
	Invalidate()
end

local nodeInfo    -- kind -> name -> node record (skill, items)

local function NodeInfo(kind, name)
	if not nodeInfo then
		nodeInfo = {}
		for k, list in pairs(ns.Nodes) do
			nodeInfo[k] = {}
			for _, n in ipairs(list) do nodeInfo[k][n.n] = n end
		end
	end
	return nodeInfo[kind] and nodeInfo[kind][name]
end

local function Skill(kind)
	local s = ns:ProfessionState(kind)
	return s and s.skill
end

local function Useful(color)
	return color == "orange" or color == "yellow" or color == "green"
end

--- The skinning level range the player set, or nil for automatic.
function ns:SkinLevelRange()
	local lo, hi = ns:Get("pins", "skinMin") or 0, ns:Get("pins", "skinMax") or 0
	if lo <= 0 and hi <= 0 then return nil end
	if hi <= 0 then hi = 83 end
	if lo > hi then lo, hi = hi, lo end
	return lo, hi
end

--- Every pin for a zone: { x, y (0-1), kind, name, color, icon, tip }.
function ns:PinsFor(zone)
	if not zone then return {} end
	if cache[zone] then return cache[zone] end
	local out = {}
	local auto = ns:Get("pins", "auto")

	for _, kind in ipairs({ "mining", "herbalism" }) do
		if ns:Get("pins", kind) then
			local skill = Skill(kind)
			for name, zones in pairs(ns.NodeSpawns[kind] or {}) do
				local list = zones[zone]
				if list then
					local node = NodeInfo(kind, name)
					local req = node and math.max(1, node.sk) or 1
					local color = skill and ns:GatherColor(req, skill) or "grey"
					if ns:IsPinned(kind, name) or (auto and skill and Useful(color)) then
						local icon = node and node.items[1] and UI.ItemIcon(node.items[1]) or nil
						local tip = { name, "needs " .. (kind == "mining" and "Mining" or "Herbalism") .. " " .. req }
						for i = 1, #list do
							local p = list[i]
							out[#out + 1] = { x = math.floor(p / 1001) / 1000, y = (p % 1001) / 1000,
								kind = kind, name = name, color = color, icon = icon, tip = tip }
						end
					end
				end
			end
		end
	end

	if ns:Get("pins", "skinning") then
		local skill = Skill("skinning")
		local lo, hi = ns:SkinLevelRange()
		for _, mob in ipairs(ns.SkinSpawns[zone] or {}) do
			local req = ns:SkinSkillFor(mob.lo)
			local color = skill and ns:GatherColor(req, skill) or "grey"
			local show = ns:IsPinned("skinning", mob.n)
			if not show and lo then
				show = mob.hi >= lo and mob.lo <= hi
			elseif not show then
				show = auto and skill ~= nil and Useful(color)
			end
			if show then
				local tip = { mob.n, "level " .. mob.lo .. (mob.hi ~= mob.lo and ("-" .. mob.hi) or "")
					.. ", needs Skinning " .. req }
				for i = 1, #mob.p do
					local p = mob.p[i]
					out[#out + 1] = { x = math.floor(p / 1001) / 1000, y = (p % 1001) / 1000,
						kind = "skinning", name = mob.n, color = color, icon = SKIN_ICON, tip = tip }
				end
			end
		end
	end
	cache[zone] = out
	return out
end

----------------------------------------------------------------------
-- pin frames
----------------------------------------------------------------------

local function MakePin(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints(f)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT", 2, -2)
	f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f:EnableMouse(true)
	f:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(d.tip[1])
		local c = COLOR[d.color] or COLOR.grey
		GameTooltip:AddLine(d.tip[2], c[1], c[2], c[3])
		if ns:IsPinned(d.kind, d.name) then GameTooltip:AddLine("pinned by you", 0.4, 0.8, 1) end
		GameTooltip:AddLine("FycoProfessions - a spawn point", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return f
end

local function Dress(f, d, size)
	f.data = d
	f:SetWidth(size)
	f:SetHeight(size)
	local c = COLOR[d.color] or COLOR.grey
	f.bg:SetTexture(c[1], c[2], c[3], 0.9)
	f.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
end

----------------------------------------------------------------------
-- world map
----------------------------------------------------------------------

local worldPins = {}
local worldShown = 0

local function HideWorld(from)
	for i = from or 1, #worldPins do worldPins[i]:Hide() end
	worldShown = 0
end

--- The zone the world map is showing, or nil (continent, instance level).
--- The map's internal name (GetMapInfo, e.g. "Tanaris") is the key that
--- works; the numeric map id is only a fallback -- in game it did not match
--- the WorldMapArea ids, and no pin was ever drawn.
local function MapZone()
	if GetCurrentMapDungeonLevel and (GetCurrentMapDungeonLevel() or 0) > 0 then return nil end
	local file = GetMapInfo and GetMapInfo()
	if file and ns.MapFileToZone[file] then return ns.MapFileToZone[file] end
	local id = GetCurrentMapAreaID and GetCurrentMapAreaID()
	return id and ns.MapToZone[id] or nil
end

local zoneByName

--- The zone you stand in, by its name, when the map cannot say.
local function ZoneByName()
	if not zoneByName then
		zoneByName = {}
		for id, z in pairs(ns.Zones) do zoneByName[z.n] = id end
	end
	return zoneByName[GetRealZoneText() or ""]
end

function ns:UpdateWorldPins()
	local canvas = WorldMapButton
	if not canvas or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
	if not ns:Enabled("pins") or not ns:Get("pins", "world") then
		HideWorld()
		return
	end
	local pins = ns:PinsFor(MapZone())
	local w, h = canvas:GetWidth(), canvas:GetHeight()
	local size = ns:Get("pins", "worldSize")
	local n = math.min(#pins, MAX_WORLD)
	for i = 1, n do
		local f = worldPins[i]
		if not f then
			f = MakePin(canvas)
			worldPins[i] = f
		end
		Dress(f, pins[i], size)
		f:SetFrameLevel(canvas:GetFrameLevel() + 5)
		f:ClearAllPoints()
		f:SetPoint("CENTER", canvas, "TOPLEFT", pins[i].x * w, -pins[i].y * h)
		f:Show()
	end
	HideWorld(n + 1)
	worldShown = n
end

function ns:WorldPinCount()
	return worldShown
end

----------------------------------------------------------------------
-- minimap
----------------------------------------------------------------------

local miniPins = {}
local miniShown = 0

local function Indoors()
	if IsIndoors then return IsIndoors() and true or false end
	local out, inside = tonumber(GetCVar("minimapZoom")), tonumber(GetCVar("minimapInsideZoom"))
	return out ~= inside and Minimap:GetZoom() == inside
end

--- Yards across the minimap at its current zoom.
function ns:MinimapYards()
	local zoom = (Minimap:GetZoom() or 0) + 1
	local t = Indoors() and MINI_IN or MINI_OUT
	return t[zoom] or t[1]
end

local playerZone

local function HideMini(from)
	for i = from or 1, #miniPins do miniPins[i]:Hide() end
end

function ns:UpdateMinimapPins()
	if not ns:Enabled("pins") or not ns:Get("pins", "minimap") then
		HideMini()
		miniShown = 0
		return
	end
	-- the world map being open means the "current map" may be another
	-- zone; keep the pins where they were until it closes
	if WorldMapFrame and WorldMapFrame:IsShown() then return end
	local zone = playerZone
	local z = zone and ns.Zones[zone]
	local px, py = GetPlayerMapPosition("player")
	if not z or not z.w or not px or (px == 0 and py == 0) then
		HideMini()
		miniShown = 0
		return
	end
	local pins = ns:PinsFor(zone)
	local yards = ns:MinimapYards()
	local radius = yards / 2
	local perYard = Minimap:GetWidth() / yards
	local size = ns:Get("pins", "miniSize")
	local rotate = GetCVar("rotateMinimap") == "1"
	local s, c = 0, 1
	if rotate and GetPlayerFacing then
		local facing = GetPlayerFacing()
		s, c = math.sin(facing), math.cos(facing)
	end
	local n = 0
	for i = 1, #pins do
		local d = pins[i]
		local dx, dy = (d.x - px) * z.w, (d.y - py) * z.h
		if rotate then dx, dy = dx * c - dy * s, dx * s + dy * c end
		if dx * dx + dy * dy <= (radius - 4) * (radius - 4) and n < MAX_MINI then
			n = n + 1
			local f = miniPins[n]
			if not f then
				f = MakePin(Minimap)
				f:SetFrameStrata("MEDIUM")
				miniPins[n] = f
			end
			Dress(f, d, size)
			f:ClearAllPoints()
			f:SetPoint("CENTER", Minimap, "CENTER", dx * perYard, -dy * perYard)
			f:Show()
		end
	end
	HideMini(n + 1)
	miniShown = n
end

function ns:MinimapPinCount()
	return miniShown
end

--- Where you are: the zone of your own position. The "current map" is
--- reset to it whenever the world map is closed.
local function FindPlayerZone()
	if WorldMapFrame and WorldMapFrame:IsShown() then return end
	if SetMapToCurrentZone then SetMapToCurrentZone() end
	playerZone = MapZone() or ZoneByName()
end

--- "/fprof pins debug": what the game reports and what the pins make of it.
function ns:PinsDebug()
	FindPlayerZone()
	local file = GetMapInfo and GetMapInfo()
	local id = GetCurrentMapAreaID and GetCurrentMapAreaID()
	local px, py = GetPlayerMapPosition("player")
	ns:Print("pins debug:")
	ns:Print(string.format("  map file %s, map id %s, zone text %s", tostring(file), tostring(id),
		tostring(GetRealZoneText())))
	local z = playerZone and ns.Zones[playerZone]
	ns:Print(string.format("  your zone: %s (%s), position %.3f, %.3f", tostring(playerZone),
		z and z.n or "not found", px or 0, py or 0))
	ns:Print(string.format("  pins here: %d, on minimap now: %d, on world map: %d",
		#ns:PinsFor(playerZone), miniShown, worldShown))
	ns:Print(string.format("  switches: module %s, world %s, minimap %s, auto %s",
		tostring(ns:Enabled("pins")), tostring(ns:Get("pins", "world")),
		tostring(ns:Get("pins", "minimap")), tostring(ns:Get("pins", "auto"))))
end

function ns:PlayerZone()
	return playerZone
end

----------------------------------------------------------------------
-- settings and commands
----------------------------------------------------------------------

local Y = "|cffffff00"

function ns:PinsCommand(rest)
	local sub, a, b = rest:match("^(%S*)%s*(%S*)%s*(%S*)")
	if sub == "" then
		local on = not ns:Enabled("pins")
		FycoProfessionsDB.enabled.pins = on
		ns:Fire("SettingChanged", "enabled", "pins", on)
		ns:Print("map pins " .. (on and "on" or "off"))
	elseif sub == "world" or sub == "minimap" then
		ns:Set("pins", sub, not ns:Get("pins", sub))
		ns:Print(sub .. " pins " .. (ns:Get("pins", sub) and "on" or "off"))
	elseif sub == "skin" then
		if a == "auto" or a == "" then
			ns:Set("pins", "skinMin", 0)
			ns:Set("pins", "skinMax", 0)
			ns:Print("skinning pins: automatic (mobs that still give skill-ups)")
		else
			local lo, hi = tonumber(a), tonumber(b ~= "" and b or a)
			if not lo or not hi then
				ns:Print("usage: " .. Y .. "/fprof pins skin <min level> [max level]|r or " .. Y .. "auto|r")
				return
			end
			ns:Set("pins", "skinMin", math.max(1, math.floor(lo)))
			ns:Set("pins", "skinMax", math.max(1, math.floor(hi)))
			local l, h = ns:SkinLevelRange()
			ns:Print("skinning pins: mobs of level " .. l .. " to " .. h)
		end
	elseif sub == "clear" then
		ns:ClearPins()
		ns:Print("your hand-picked pins are cleared")
	elseif sub == "debug" then
		ns:PinsDebug()
	else
		ns:Print("usage: " .. Y .. "/fprof pins|r (on or off), " .. Y .. "world|r, " .. Y .. "minimap|r, "
			.. Y .. "skin <min> [max]|r, " .. Y .. "skin auto|r, " .. Y .. "clear|r, " .. Y .. "debug|r")
	end
end

ns:RegisterOptions("Pins", "Map pins", 25, function(L, R)
	L:Title("Map pins")
	L:Note("Spawn points of nodes and skinnable mobs on your maps. Automatic: "
	    .. "what still gives you skill-ups, coloured orange, yellow or green.")
	L:Check("On the world map", "Works with Mapster: the pins sit on the map itself",
		function() return ns:Get("pins", "world") end,
		function(v) ns:Set("pins", "world", v) end)
	L:Check("On the minimap", nil,
		function() return ns:Get("pins", "minimap") end,
		function(v) ns:Set("pins", "minimap", v) end)
	L:Check("Automatic (skill-ups)", "Off: only what you pinned by hand, or the level range",
		function() return ns:Get("pins", "auto") end,
		function(v) ns:Set("pins", "auto", v) end)
	L:Check("Mining nodes", nil,
		function() return ns:Get("pins", "mining") end,
		function(v) ns:Set("pins", "mining", v) end)
	L:Check("Herbs", nil,
		function() return ns:Get("pins", "herbalism") end,
		function(v) ns:Set("pins", "herbalism", v) end)
	L:Check("Skinnable mobs", nil,
		function() return ns:Get("pins", "skinning") end,
		function(v) ns:Set("pins", "skinning", v) end)
	L:Button("Clear hand-picked pins", function() ns:ClearPins() end)

	R:Title("Skinning levels")
	R:Note("Set a range to pin every skinnable mob of those levels instead of "
	    .. "the automatic choice. Both at 0 = automatic.")
	R:Slider("Lowest mob level", 0, 83, 1,
		function() return ns:Get("pins", "skinMin") end,
		function(v) ns:Set("pins", "skinMin", v) end)
	R:Slider("Highest mob level", 0, 83, 1,
		function() return ns:Get("pins", "skinMax") end,
		function(v) ns:Set("pins", "skinMax", v) end)
	R:Title("Size")
	R:Slider("World map pin size", 8, 24, 1,
		function() return ns:Get("pins", "worldSize") end,
		function(v) ns:Set("pins", "worldSize", v) end)
	R:Slider("Minimap pin size", 8, 20, 1,
		function() return ns:Get("pins", "miniSize") end,
		function(v) ns:Set("pins", "miniSize", v) end)
	R:Note("Click a mob or node in the Skinning, Mining or Herbalism tab to "
	    .. "pin or unpin it. Spawns are the stock database's; mobs wander.")
end)

----------------------------------------------------------------------

function M:OnLoad()
	FindPlayerZone()
	ns:Subscribe("ProfessionsChanged", Invalidate)
	ns:Subscribe("SettingChanged", function(section, key)
		if section == "pins" or (section == "enabled" and key == "pins") then Invalidate() end
	end)
	ns:Subscribe("PinsChanged", function()
		ns:UpdateWorldPins()
		ns:UpdateMinimapPins()
	end)
	ns:On("WORLD_MAP_UPDATE", function() ns:UpdateWorldPins() end)
	ns:On("ZONE_CHANGED_NEW_AREA", FindPlayerZone)
	ns:On("PLAYER_ENTERING_WORLD", FindPlayerZone)
	if WorldMapFrame then
		WorldMapFrame:HookScript("OnShow", function() ns:UpdateWorldPins() end)
		WorldMapFrame:HookScript("OnHide", function()
			HideWorld()
			FindPlayerZone()
		end)
	end
	-- the minimap follows you: 10 times a second, and the zone check every 2 s
	local lastZone = 0
	ns:OnTick(function(now)
		if now - lastZone >= 2 then
			lastZone = now
			FindPlayerZone()
		end
		ns:UpdateMinimapPins()
	end)
end
