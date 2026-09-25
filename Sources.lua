--[[ FycoProfessions - Sources.lua
     Turns the generated source records into readable text: how to learn a
     recipe ("Vendor: Kalaen - Hellfire Peninsula: 2g; needs Thrallmar -
     Honored") and where a material comes from ("Mining, Prospecting",
     "Vendor: 20c each - 14 vendors, e.g. ..."). One place, so the path, the
     shopping list and the tooltips agree.

     Trainers, vendors, drops and quests come from a database of the stock
     3.3.5 game, not from this server, and the UI says so.                 ]]

local _, ns = ...

local WHITE, GREY, GOLD, RED = "|cffffffff", "|cffa0a0a0", "|cffffd200", "|cffff6060"

local SIDE = { A = "Alliance", H = "Horde" }

local GATHER_TEXT = {
	m = "Mining", h = "Herbalism", s = "Skinning", f = "Fishing",
	p = "Prospecting", l = "Milling", d = "Disenchanting", x = "dropped by mobs",
}
local GATHER_ORDER = { "m", "h", "s", "f", "p", "l", "d", "x" }

local function ItemName(id)
	local it = ns.Items[id]
	return (it and it.n) or ("item " .. id)
end

--- "2g 00s + 3 Dalaran Jewelcrafter's Token" from a vendor cost record.
function ns:FormatCost(c)
	if not c then return nil end
	local parts = {}
	local items = c.items or {}
	for i = 1, #items, 2 do
		parts[#parts + 1] = items[i + 1] .. " " .. ItemName(items[i])
	end
	if c.gold then parts[#parts + 1] = ns.UI.Money(c.gold) end
	local text = table.concat(parts, " + ")
	return text ~= "" and text or nil
end

local function Zone(s)
	return s.zone and (" - " .. s.zone) or ""
end

local function SideText(side)
	return SIDE[side] and (GREY .. " (" .. SIDE[side] .. " only)|r") or ""
end

--- One line for one recipe source record.
function ns:FormatRecipeSource(s)
	if s.t == "auto" then
		return GOLD .. "Learned|r with the profession"
	elseif s.t == "trainer" then
		local t = GOLD .. "Trainer:|r " .. WHITE .. ns.UI.Money(s.cost or 0) .. "|r"
		if s.skill and s.skill > 0 then t = t .. ", at skill " .. s.skill end
		if s.lvl then t = t .. ", level " .. s.lvl end
		if s.unspawned then t = t .. GREY .. " (no trainer with it is spawned in the stock database)|r" end
		return t .. SideText(s.side)
	elseif s.t == "vendor" then
		local t = GOLD .. "Vendor:|r " .. WHITE .. s.who .. "|r" .. Zone(s)
		local cost = ns:FormatCost(s.cost)
		if cost then t = t .. ": " .. cost end
		if s.rep then t = t .. "|cffff8040; needs " .. s.rep[1] .. " - " .. s.rep[2] .. "|r" end
		if s.lim then t = t .. GREY .. " (limited supply)|r" end
		return t .. SideText(s.side)
	elseif s.t == "world" then
		return GOLD .. "World drop|r from " .. s.n .. " kinds of creature - try the Auction House"
	elseif s.t == "drop" then
		return GOLD .. "Drop:|r " .. WHITE .. s.who .. "|r" .. Zone(s)
	elseif s.t == "quest" then
		return GOLD .. "Quest:|r " .. WHITE .. s.who .. "|r" .. Zone(s) .. SideText(s.side)
	elseif s.t == "item" then
		return GOLD .. "Recipe:|r " .. ItemName(s.item) .. GREY
			.. " - not sold or dropped in the stock database; try the Auction House|r"
	end
	return GREY .. "unknown source|r"
end

--- Every line about how to learn a recipe, specialisation included.
function ns:RecipeSourceLines(rec)
	local lines = {}
	for i = 1, #(rec.src or {}) do
		lines[#lines + 1] = ns:FormatRecipeSource(rec.src[i])
	end
	if #lines == 0 then
		lines[1] = RED .. "Source unknown|r " .. GREY .. "(realm-specific: not in the stock database)|r"
	end
	if rec.spec then
		lines[#lines + 1] = "|cffff8040Needs the specialisation " .. (GetSpellInfo(rec.spec) or ("spell " .. rec.spec)) .. "|r"
	end
	return lines
end

--- "Mining, Prospecting" -- how a material can be gathered, or nil.
function ns:GatherText(id)
	local it = ns.Items[id]
	if not it or not it.g then return nil end
	local parts = {}
	for i = 1, #GATHER_ORDER do
		local tag = GATHER_ORDER[i]
		if it.g:find(tag, 1, true) then parts[#parts + 1] = GATHER_TEXT[tag] end
	end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

--- Every line about where a material comes from, for detail panes.
function ns:ItemSourceLines(id)
	local it = ns.Items[id]
	local lines = {}
	if not it then
		lines[1] = GREY .. "No data for this item.|r"
		return lines
	end
	if it.v then
		lines[#lines + 1] = GOLD .. "Vendor:|r " .. ns.UI.Money(it.v) .. " each" .. (it.vw and (" - " .. it.vw) or "")
	end
	local g = ns:GatherText(id)
	if g then lines[#lines + 1] = GOLD .. "Gathered:|r " .. g end
	if it.c then
		local names = {}
		for i = 1, #it.c do
			local p = ns.ProfessionByKey[it.c[i]]
			names[#names + 1] = p and p.name or it.c[i]
		end
		lines[#lines + 1] = GOLD .. "Crafted:|r " .. table.concat(names, ", ")
	end
	local price, age = ns:AHPrice(id)
	if price then
		lines[#lines + 1] = GOLD .. "Auction House:|r " .. ns.UI.Money(price) .. " each " .. GREY .. "(" .. age .. ")|r"
	end
	if #lines == 0 then lines[1] = GREY .. "No known source in the stock database.|r" end
	return lines
end
