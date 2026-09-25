--[[ FycoProfessions - Modules/Gather.lua
     Gathering (Mining, Herbalism, Skinning) and Fishing: where to go.

     MODEL (AzerothCore, the stock 3.3.5 server rules, with this realm's rate)
       - A node or a corpse needs skill `req`. It is orange below req + 25,
         yellow below req + 50, green below req + 100, then grey; the chance
         of a skill-up per gather is 100 / 75 / 25 / 0 %, as for recipes.
       - Skinning req by mob level: 1 up to level 10, (level - 10) x 10 for
         11-20, level x 5 above that.
       - Each skill-up gives ns:Rate() points.
       - Fishing: a skill-up chance per catch of 100% below skill 75, then
         2500 / (skill - 50) %. Below a zone's fishing skill some catches
         get away: the catch chance is (skill / zone skill) squared.

     A zone's score is the skill-ups its spawns offer at your skill: the sum
     over its nodes (or skinnable mobs) of count x chance. "Move on at" is
     the first skill where another zone scores clearly better, or this one
     runs dry. Spawns are the stock database's; zone density is not known,
     so the score compares zones, it does not promise a rate.            ]]

local _, ns = ...
local M = ns:Module("gather", 22)
local UI = ns.UI

local CHANCE = { orange = 1, yellow = 0.75, green = 0.25, grey = 0, red = 0 }
local BETTER = 1.25          -- another zone must score 25% more to say "move on"
local GREY, WHITE, GOLD, RED, GREEN, BLUE = "|cffa0a0a0", "|cffffffff", "|cffffd200", "|cffff6060", "|cff60ff60", "|cff66ccff"

----------------------------------------------------------------------
-- model
----------------------------------------------------------------------

function ns:SkinSkillFor(level)
	if level <= 10 then return 1 end
	if level <= 20 then return (level - 10) * 10 end
	return level * 5
end

function ns:GatherColor(req, skill)
	req = math.max(req or 1, 1)
	if skill < req then return "red" end
	local d = skill - req
	if d < 25 then return "orange" end
	if d < 50 then return "yellow" end
	if d < 100 then return "green" end
	return "grey"
end

local function MobChance(mob, skill)
	local sum, n = 0, 0
	for lvl = mob.lo, mob.hi do
		sum = sum + CHANCE[ns:GatherColor(ns:SkinSkillFor(lvl), skill)]
		n = n + 1
	end
	return n > 0 and sum / n or 0
end

local function MobColor(mob, skill)
	-- the colour of the mob's highest level: the one you need the skill for
	return ns:GatherColor(ns:SkinSkillFor(mob.hi), skill)
end

--- zone -> { { node, count } } per gathering kind, built once
local byZone = {}

local function ZoneNodes(kind)
	if byZone[kind] then return byZone[kind] end
	local out = {}
	for _, node in ipairs(ns.Nodes[kind] or {}) do
		for _, zc in ipairs(node.z) do
			out[zc[1]] = out[zc[1]] or {}
			table.insert(out[zc[1]], { node = node, count = zc[2] })
		end
	end
	byZone[kind] = out
	return out
end

local function ZoneScore(kind, zone, skill)
	local score = 0
	if kind == "skinning" then
		for _, mob in ipairs(ns.SkinZones[zone] or {}) do
			score = score + mob.c * MobChance(mob, skill)
		end
	else
		for _, e in ipairs(ZoneNodes(kind)[zone] or {}) do
			score = score + e.count * CHANCE[ns:GatherColor(e.node.sk, skill)]
		end
	end
	return score
end

local function Zones(kind)
	if kind == "skinning" then return ns.SkinZones end
	return ZoneNodes(kind)
end

--- The other faction's home zones count for a quarter: their guards and
--- players make them a poor place to gather.
local function Hostile(zone)
	local z = ns.Zones[zone]
	local mine = ns:Faction() == "Horde" and "H" or "A"
	return z and z.side ~= nil and z.side ~= mine
end

--- Zones ranked by skill-ups on offer at `skill`: { {zone, score}, ... }
function ns:RankZones(kind, skill)
	local out = {}
	for zone in pairs(Zones(kind)) do
		local s = ZoneScore(kind, zone, skill)
		if Hostile(zone) then s = s * 0.25 end
		if s > 0 and ns.Zones[zone] then out[#out + 1] = { zone = zone, score = s } end
	end
	table.sort(out, function(a, b) return a.score > b.score end)
	return out
end

--- The first skill above `skill` where `zone` stops being worth it.
function ns:MoveOnAt(kind, zone, skill, cap)
	local step = 5
	for s = skill + step, math.min(cap or ns.MAX_SKILL, ns.MAX_SKILL), step do
		local mine = ZoneScore(kind, zone, s)
		if mine <= 0 then return s end
		if Hostile(zone) then mine = mine * 0.25 end
		local ranked = ns:RankZones(kind, s)
		if ranked[1] and ranked[1].zone ~= zone and ranked[1].score > mine * BETTER then return s, ranked[1].zone end
	end
	return nil
end

local function ZoneLabel(zone)
	local z = ns.Zones[zone]
	if not z then return "?" end
	local t = z.n
	if z.lo and z.hi then
		local lvl = UnitLevel("player") or 80
		local col = z.lo > lvl + 2 and RED or GREY
		t = t .. col .. " (mobs " .. z.lo .. "-" .. z.hi .. ")|r"
	end
	if Hostile(zone) then t = t .. RED .. " (" .. (z.side == "A" and "Alliance" or "Horde") .. " land)|r" end
	return t
end

----------------------------------------------------------------------
-- fishing model
----------------------------------------------------------------------

function ns:FishSkillUpChance(skill)
	if skill < 75 then return 1 end
	return math.min(1, 25 / math.max(1, skill - 50))
end

function ns:FishCatchChance(skill, zoneSkill)
	if skill >= zoneSkill or zoneSkill <= 0 then return 1 end
	return math.max(0.01, (skill / zoneSkill) ^ 2)
end

----------------------------------------------------------------------
-- rank reminder shared by both views
----------------------------------------------------------------------

local function NextRankRow(prof, state)
	if not state or state.preview or state.skill < state.max or state.max >= ns.MAX_SKILL then return nil end
	for step = 1, 6 do
		local r = ns.RankInfo[prof.key] and ns.RankInfo[prof.key][step]
		if r and r.cap > state.max then
			return r, step
		end
	end
end

local function TrainRows(prof, r, step)
	local rows = { { text = BLUE .. "Train " .. ns.Ranks[step].name .. "|r (skill cap " .. r.cap .. ")" } }
	if r.lvl and r.lvl > 0 then rows[#rows + 1] = { text = "Needs level " .. r.lvl } end
	for _, e in ipairs(ns:NearestTrainers(prof.key, r.cap, 4)) do
		rows[#rows + 1] = { text = ns:TrainerText(e) }
	end
	return rows
end

----------------------------------------------------------------------
-- gathering view
----------------------------------------------------------------------

local function Picker(v, key)
	return function()
		v.selected[v.mode] = key
		v:Refresh()
	end
end

local function ZoneDetail(v, prof, zone, skill, cap)
	local rows = { { text = GOLD .. ZoneLabel(zone) .. "|r" } }
	if prof.key == "skinning" then
		for _, mob in ipairs(ns.SkinZones[zone] or {}) do
			local col = MobColor(mob, skill)
			rows[#rows + 1] = { text = UI.Colored(col, mob.n) .. GREY .. " level " .. mob.lo
				.. (mob.hi ~= mob.lo and ("-" .. mob.hi) or "") .. "|r",
				right = "skill " .. ns:SkinSkillFor(mob.hi) .. ", " .. mob.c .. "x" }
		end
	else
		local list = {}
		for _, e in ipairs(ZoneNodes(prof.key)[zone] or {}) do list[#list + 1] = e end
		table.sort(list, function(a, b) return a.node.sk < b.node.sk end)
		for _, e in ipairs(list) do
			local col = ns:GatherColor(e.node.sk, skill)
			rows[#rows + 1] = { text = UI.Colored(col, e.node.n), right = "skill " .. math.max(1, e.node.sk) .. ", " .. e.count .. "x",
				icon = e.node.items[1] and UI.ItemIcon(e.node.items[1]), item = e.node.items[1] }
		end
	end
	local at, nextZone = ns:MoveOnAt(prof.key, zone, skill, cap)
	if at then
		rows[#rows + 1] = { text = GOLD .. "Move on at " .. at .. "|r" .. (nextZone and (" to " .. ZoneLabel(nextZone)) or "") }
	end
	rows[#rows + 1] = { text = GREY .. "Spawn counts are the stock database's.|r" }
	return rows
end

local function ZonesMode(v, prof, state)
	local skill = state.skill
	local ranked = ns:RankZones(prof.key, skill)
	local rows = {}
	local r, step = NextRankRow(prof, state)
	if r then
		rows[#rows + 1] = { key = "train", icon = "Interface\\Icons\\INV_Misc_Book_11",
			text = BLUE .. "Train " .. ns.Ranks[step].name .. "|r - you are at your cap", onClick = Picker(v, "train") }
	end
	for i = 1, math.min(#ranked, 25) do
		local e = ranked[i]
		rows[#rows + 1] = { key = e.zone, text = ZoneLabel(e.zone), right = string.format("%.0f", e.score),
			onClick = Picker(v, e.zone) }
	end
	if #ranked == 0 then rows[#rows + 1] = { text = RED .. "No zone offers skill-ups at " .. skill .. ".|r" } end
	v.left:SetData(rows, true)
	local sel = v.selected.zones or (r and "train") or (ranked[1] and ranked[1].zone)
	v.left:Select(sel)
	if sel == "train" and r then
		v.right:SetData(TrainRows(prof, r, step))
	elseif sel then
		v.right:SetData(ZoneDetail(v, prof, sel, skill, state.max))
	else
		v.right:SetData({})
	end
	local best = ranked[1]
	local s = best and ("Best now: " .. ZoneLabel(best.zone)) or "No zone found"
	if best then
		local at = ns:MoveOnAt(prof.key, best.zone, skill, state.max)
		if at then s = s .. ". Move on at " .. at end
	end
	v.summary:SetText(s .. ".\n" .. GREY .. "Score = skill-ups on offer (spawns x chance). Orange 100%, yellow 75%, "
		.. "green 25% per " .. (prof.key == "skinning" and "corpse" or "node") .. ", x" .. ns:Rate() .. " points each.|r")
end

local function ListMode(v, prof, state)
	local skill = state.skill
	local rows = {}
	if prof.key == "skinning" then
		for lvl = 5, 80, 5 do
			local req = ns:SkinSkillFor(lvl)
			rows[#rows + 1] = { text = UI.Colored(ns:GatherColor(req, skill), "Mob level " .. lvl), right = "skill " .. req }
		end
		v.left:SetData(rows, true)
		v.right:SetData({ { text = GOLD .. "Skinning skill by mob level|r" },
			{ text = "Up to level 10: skill 1" }, { text = "Levels 11-20: (level - 10) x 10" },
			{ text = "Above 20: level x 5" },
			{ text = GREY .. "Colours are for your skill now.|r" } })
		v.summary:SetText("Which mobs you can skin, and how much they teach.")
		return
	end
	for _, node in ipairs(ns.Nodes[prof.key] or {}) do
		rows[#rows + 1] = { key = node.n, icon = node.items[1] and UI.ItemIcon(node.items[1]),
			text = UI.Colored(ns:GatherColor(node.sk, skill), node.n), right = "skill " .. math.max(1, node.sk),
			onClick = Picker(v, node.n) }
	end
	v.left:SetData(rows, true)
	local sel = v.selected.nodes
	v.left:Select(sel)
	local detail = {}
	for _, node in ipairs(ns.Nodes[prof.key] or {}) do
		if node.n == sel then
			detail[#detail + 1] = { text = GOLD .. node.n .. "|r", right = "skill " .. math.max(1, node.sk) }
			for _, id in ipairs(node.items) do
				detail[#detail + 1] = { text = UI.ItemName(id), icon = UI.ItemIcon(id), item = id }
			end
			detail[#detail + 1] = { text = GOLD .. "Where|r" }
			for i = 1, math.min(#node.z, 15) do
				detail[#detail + 1] = { text = ZoneLabel(node.z[i][1]), right = node.z[i][2] .. "x" }
			end
		end
	end
	v.right:SetData(detail)
	v.summary:SetText("Every " .. (prof.key == "mining" and "mining node" or "herb") .. ", coloured for your skill ("
		.. skill .. "). Click one to see where it grows.")
end

ns.ViewBuilders.gather = function(v, prof, state)
	state = state or { skill = 1, max = 75, preview = true }
	local modes = { { key = "zones", label = "Best zones", w = 80 },
		{ key = "nodes", label = prof.key == "skinning" and "Mob levels" or "All nodes", w = 80 } }
	if ns.Extras[prof.key] then modes[#modes + 1] = { key = "extras", label = "Smelting", w = 70 } end
	v.mode = v.mode or "zones"
	v:SetModes(modes)
	v.title:SetText(ns:StateTitle(prof, state))
	if v.mode == "nodes" then
		ListMode(v, prof, state)
	elseif v.mode == "extras" and ns.Extras[prof.key] then
		local rows, sel, detail = ns.Extras[prof.key](v, state)
		v.left:SetData(rows, true)
		v.left:Select(sel)
		v.right:SetData(detail)
		v.summary:SetText("Smelting ore also raises Mining. Colours are for your skill (" .. state.skill .. ").")
	else
		ZonesMode(v, prof, state)
	end
end

----------------------------------------------------------------------
-- fishing view
----------------------------------------------------------------------

ns.ViewBuilders.fish = function(v, prof, state)
	state = state or { skill = 1, max = 75, preview = true }
	local skill = state.skill
	v.mode = "zones"
	v:SetModes({})
	v.title:SetText(ns:StateTitle(prof, state))
	local rows = {}
	local r, step = NextRankRow(prof, state)
	if r then
		rows[#rows + 1] = { key = "train", text = BLUE .. "Train " .. ns.Ranks[step].name .. "|r - you are at your cap",
			onClick = Picker(v, "train") }
	end
	local bestFull
	for _, f in ipairs(ns.FishingZones) do
		local catch = ns:FishCatchChance(skill, f.sk)
		local col = catch >= 1 and "green" or (catch >= 0.5 and "yellow" or "red")
		if catch >= 1 then bestFull = f end
		local zone = ns.Zones[f.zone or 0]
		rows[#rows + 1] = { key = f.a, text = UI.Colored(col, f.n) .. (zone and zone.n ~= f.n and (GREY .. " (" .. zone.n .. ")|r") or ""),
			right = "skill " .. f.sk .. (catch < 1 and string.format(", %d%%", catch * 100) or ""), onClick = Picker(v, f.a) }
	end
	v.left:SetData(rows, true)
	local sel = v.selected.zones or (r and "train") or (bestFull and bestFull.a)
	v.left:Select(sel)
	if sel == "train" and r then
		v.right:SetData(TrainRows(prof, r, step))
	else
		local detail = {}
		for _, f in ipairs(ns.FishingZones) do
			if f.a == sel then
				detail[#detail + 1] = { text = GOLD .. f.n .. "|r", right = "skill " .. f.sk }
				detail[#detail + 1] = { text = string.format("You catch %d%% of bites here", ns:FishCatchChance(skill, f.sk) * 100) }
				detail[#detail + 1] = { text = GOLD .. "Common catches|r" }
				for _, id in ipairs(f.fish) do
					detail[#detail + 1] = { text = UI.ItemName(id), icon = UI.ItemIcon(id), item = id }
				end
			end
		end
		v.right:SetData(detail)
	end
	local ch = ns:FishSkillUpChance(skill)
	v.summary:SetText(string.format("Skill-up chance per catch: %d%% (about %d catches per skill-up, x%d points).",
		ch * 100, math.ceil(1 / ch), ns:Rate()) .. (bestFull and (" Highest zone with no escapes: " .. bestFull.n .. ".") or "")
		.. "\n" .. GREY .. "Skill-up speed does not depend on the zone; a higher zone only gives better fish. Stock formulas.|r")
end

----------------------------------------------------------------------
-- tracker lines
----------------------------------------------------------------------

ns.TrackerProviders.gather = function(prof, state)
	local title = string.format("%s %d/%d (x%d)", prof.name, state.skill, state.max, ns:Rate())
	local r, step = NextRankRow(prof, state)
	if r then
		local lines = { BLUE .. "Train " .. ns.Ranks[step].name .. "|r" .. (r.lvl and r.lvl > 0 and (" (level " .. r.lvl .. ")") or "") }
		local t = ns:NearestTrainers(prof.key, r.cap, 1)[1]
		if t then lines[2] = t.t.n .. " - " .. t.t.zoneName end
		return title, lines
	end
	local ranked = ns:RankZones(prof.key, state.skill)
	local best = ranked[1]
	if not best then return title, { RED .. "No zone offers skill-ups here.|r" } end
	local lines = { "Go to " .. WHITE .. (ns.Zones[best.zone] and ns.Zones[best.zone].n or "?") .. "|r" }
	if prof.key == "skinning" then
		local names = {}
		for _, mob in ipairs(ns.SkinZones[best.zone] or {}) do
			local col = MobColor(mob, state.skill)
			if col ~= "grey" and col ~= "red" and #names < 3 then names[#names + 1] = UI.Colored(col, mob.n) end
		end
		lines[#lines + 1] = table.concat(names, ", ")
	else
		local names = {}
		for _, e in ipairs(ZoneNodes(prof.key)[best.zone] or {}) do
			local col = ns:GatherColor(e.node.sk, state.skill)
			if col ~= "grey" and col ~= "red" and #names < 3 then names[#names + 1] = UI.Colored(col, e.node.n) end
		end
		lines[#lines + 1] = table.concat(names, ", ")
	end
	local at = ns:MoveOnAt(prof.key, best.zone, state.skill, state.max)
	if at then lines[#lines + 1] = GREY .. "move on at " .. at .. "|r" end
	return title, lines
end

ns.TrackerProviders.fish = function(prof, state)
	local title = string.format("%s %d/%d (x%d)", prof.name, state.skill, state.max, ns:Rate())
	local ch = ns:FishSkillUpChance(state.skill)
	local lines = { string.format("%d%% a catch, about %d catches per skill-up", ch * 100, math.ceil(1 / ch)) }
	local r, step = NextRankRow(prof, state)
	if r then lines[#lines + 1] = BLUE .. "Train " .. ns.Ranks[step].name .. "|r" end
	return title, lines
end

function M:OnLoad() end
