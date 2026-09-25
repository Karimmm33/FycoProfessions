--[[ FycoProfessions - Modules/Engine.lua
     The crafting path: the cheapest way from your skill to your target.

     MODEL (AzerothCore, the stock 3.3.5 server rules, with this realm's rate)
       - A recipe is orange from its learn skill (o) to yellow (y), yellow to
         green (g), green to grey (gr), then grey. y and gr come from the
         realm's SkillLineAbility.dbc; g = (y + gr) / 2, as the server does.
       - Chance of a skill-up per craft: orange 100%, yellow 75%, green 25%,
         grey 0% (the server's default SkillChance settings).
       - Each skill-up gives ns:Rate() points (x2 on Frostmourne Rebuffed).
       - Expected crafts for one skill-up = 1 / chance.

     SOLVER. Dynamic programming over skill values, one trainer rank at a
     time: best[s] = min over usable recipes of cost / chance + best[s + rate].
     Consecutive skill-ups on the same recipe merge into one step ("Make 12 x
     Bronze Setting, 50 to 74"). Near-ties keep the recipe already in use, so
     the path does not flip between two equally good recipes every point.

     COST. Per material: a vendor price when there is one, your Auction
     House scan when allowed, the cost of crafting it with a profession you
     have, or else an estimate (4 x vendor sell price) -- and the UI marks
     every estimate as one.                                               ]]

local _, ns = ...
local M = ns:Module("engine", 12)

local CHANCE = { orange = 1, yellow = 0.75, green = 0.25, grey = 0, red = 0 }
local ESTIMATE_FACTOR = 4
local UNKNOWN_PRICE = 50000     -- an item with no vendor value at all: 5g, so it is avoided
local STICKY = 1.03             -- keep the current recipe unless another is 3% better

ns.SkillChance = CHANCE

----------------------------------------------------------------------
-- colours and chances
----------------------------------------------------------------------

function ns:RecipeColor(rec, skill)
	if skill < rec.o then return "red" end
	if skill >= rec.gr then return "grey" end
	if skill >= rec.g then return "green" end
	if skill >= rec.y then return "yellow" end
	return "orange"
end

function ns:RecipeChance(rec, skill)
	return CHANCE[ns:RecipeColor(rec, skill)]
end

----------------------------------------------------------------------
-- can this character use this recipe?
----------------------------------------------------------------------

local RACE_ID = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6,
	Gnome = 7, Troll = 8, BloodElf = 10, Draenei = 11 }

local function RaceBit()
	local _, race = UnitRace("player")
	local id = RACE_ID[race or ""]
	return id and 2 ^ (id - 1)
end

local function HasBit(mask, bitv)
	return math.floor(mask / bitv) % 2 == 1
end

local HOW_RANK = { known = 1, auto = 2, trainer = 3, vendor = 4, quest = 5, drop = 6 }

--- ok, how ("known", "auto", "trainer", "vendor", "quest", "drop"), reason
--- when not ok ("race", "spec", "faction", "rep", "drops", "unknown").
function ns:RecipeStatus(profKey, rec)
	if ns:KnowsRecipe(profKey, rec.sp) then return true, "known" end
	if rec.race then
		local b = RaceBit()
		if b and not HasBit(rec.race, b) then return false, nil, "race" end
	end
	if rec.spec and not ns:KnowsSpell(rec.spec) then return false, nil, "spec" end

	local side = ns:Faction() == "Horde" and "H" or "A"
	local drops = ns:Get("guide", "drops")
	local best, reason
	for i = 1, #(rec.src or {}) do
		local s = rec.src[i]
		local how
		if s.t == "auto" then
			how = "auto"
		elseif s.t == "trainer" then
			if s.unspawned then reason = reason or "unknown"
			elseif s.side and s.side ~= side then reason = reason or "faction"
			else how = "trainer" end
		elseif s.t == "vendor" then
			if s.side and s.side ~= "B" and s.side ~= side then
				reason = reason or "faction"
			elseif s.rep and not ns:RepAtLeast(s.rep[1], s.rep[2]) then
				reason = "rep"
			else
				how = "vendor"
			end
		elseif s.t == "quest" then
			if s.side and s.side ~= side then reason = reason or "faction" else how = "quest" end
		elseif s.t == "drop" or s.t == "world" or s.t == "item" then
			if drops then how = "drop" else reason = reason or "drops" end
		end
		if how and (not best or HOW_RANK[how] < HOW_RANK[best]) then best = how end
	end
	if best then return true, best end
	return false, nil, reason or "unknown"
end

ns.StatusText = {
	known = "you know it", auto = "learned with the profession", trainer = "from a trainer",
	vendor = "from a vendor", quest = "from a quest", drop = "drop or Auction House",
	race = "not for your race", spec = "needs a specialisation you do not have",
	faction = "the other faction's", rep = "needs reputation you do not have yet",
	drops = "only from drops (allow them in the settings)",
	unknown = "source unknown (realm-specific)",
}

----------------------------------------------------------------------
-- material costs
----------------------------------------------------------------------

local version = 0        -- bumped whenever anything a path depends on changes
local memo, memoVersion = {}, -1
local creators           -- prof -> item -> { recipes that make it }

local function Creators(profKey)
	if not creators then
		creators = {}
		for key, list in pairs(ns.Recipes) do
			local idx = {}
			for i = 1, #list do
				local it = list[i].it
				if it then
					idx[it] = idx[it] or {}
					idx[it][#idx[it] + 1] = list[i]
				end
			end
			creators[key] = idx
		end
	end
	return creators[profKey] or {}
end

local ItemCost

local function CraftCost(id, depth)
	local it = ns.Items[id]
	if not it or not it.c or depth >= 2 then return nil end
	local best
	for i = 1, #it.c do
		local prof = it.c[i]
		local state = ns:ProfessionState(prof)
		if state then
			local recs = Creators(prof)[id] or {}
			for j = 1, #recs do
				local rec = recs[j]
				if state.skill >= rec.o and ns:RecipeStatus(prof, rec) then
					local sum, ok = 0, true
					for k = 1, #rec.r, 2 do
						local c = ItemCost(rec.r[k], depth + 1)
						if not c then ok = false break end
						sum = sum + c * rec.r[k + 1]
					end
					if ok then
						sum = sum / (rec.qty or 1)
						if not best or sum < best then best = sum end
					end
				end
			end
		end
	end
	return best
end

--- copper, kind ("vendor", "ah", "crafted", "gather", "estimate") -- or nil
--- when "gathered materials only" rules the item out.
function ItemCost(id, depth)
	depth = depth or 0
	if memoVersion ~= version then memo, memoVersion = {}, version end
	local m = memo[id]
	if m then return m[1], m[2] end

	local it = ns.Items[id]
	local gathered = ns:Materials() == "gathered"
	local best, kind
	if it and it.v then best, kind = it.v, "vendor" end
	if not gathered then
		local ah = ns:AHPrice(id)
		if ah and (not best or ah < best) then best, kind = ah, "ah" end
	end
	local craft = CraftCost(id, depth)
	if craft and (not best or craft < best) then best, kind = craft, "crafted" end
	if not best then
		local est = (it and it.s and it.s > 0) and it.s * ESTIMATE_FACTOR or UNKNOWN_PRICE
		if gathered then
			if it and it.g then best, kind = est, "gather" end
		else
			best, kind = est, "estimate"
		end
	end
	if depth == 0 then memo[id] = { best, kind } end
	return best, kind
end

function ns:ItemCost(id)
	return ItemCost(id, 0)
end

--- Cost of one craft of a recipe, and whether any part of it is an estimate.
function ns:RecipeCost(rec)
	local sum, estimated = 0, false
	for k = 1, #rec.r, 2 do
		local c, kind = ItemCost(rec.r[k], 0)
		if not c then return nil end
		if kind == "estimate" or kind == "gather" then estimated = true end
		sum = sum + c * rec.r[k + 1]
	end
	return math.max(sum, 1), estimated
end

----------------------------------------------------------------------
-- the path
----------------------------------------------------------------------

local function Candidates(profKey)
	local out = {}
	local list = ns.Recipes[profKey] or {}
	for i = 1, #list do
		local rec = list[i]
		if rec.gr > 1 and ns:RecipeStatus(profKey, rec) then
			local cost, est = ns:RecipeCost(rec)
			if cost then out[#out + 1] = { rec = rec, cost = cost, est = est } end
		end
	end
	return out
end

local function Usable(c, s)
	return s >= c.rec.o and s < c.rec.gr
end

--- Solve one stretch [from, to] inside a trainer rank. Returns the steps,
--- and the skill where it got stuck (no usable recipe gives skill-ups
--- there) or nil.
local function Segment(cands, from, to, rate)
	-- the first skill with nothing to craft cuts the stretch short
	local stuck
	for s = from, to - 1 do
		local any = false
		for i = 1, #cands do
			if Usable(cands[i], s) then any = true break end
		end
		if not any then stuck = s break end
	end
	local stop = stuck or to

	local best, choice = {}, {}
	best[stop] = 0
	for s = stop - 1, from, -1 do
		local nxt = math.min(s + rate, stop)
		local bn = best[nxt]
		if bn then
			local bestV, bestC
			for i = 1, #cands do
				local c = cands[i]
				if Usable(c, s) then
					local v = c.cost / CHANCE[ns:RecipeColor(c.rec, s)] + bn
					if not bestV or v < bestV then bestV, bestC = v, c end
				end
			end
			local prev = choice[nxt]
			if prev and prev ~= bestC and Usable(prev, s) then
				local pv = prev.cost / CHANCE[ns:RecipeColor(prev.rec, s)] + bn
				if pv <= bestV * STICKY then bestV, bestC = pv, prev end
			end
			best[s], choice[s] = bestV, bestC
		end
	end

	local steps = {}
	local s, cur = from, nil
	while s < stop and choice[s] do
		local c = choice[s]
		local nxt = math.min(s + rate, stop)
		local crafts = 1 / CHANCE[ns:RecipeColor(c.rec, s)]
		if cur and cur.cand == c then
			cur.crafts = cur.crafts + crafts
			cur.to = nxt
		else
			cur = { kind = "craft", cand = c, rec = c.rec, from = s, to = nxt, crafts = crafts,
			        unit = c.cost, est = c.est, color = ns:RecipeColor(c.rec, s) }
			steps[#steps + 1] = cur
		end
		s = nxt
	end
	for i = 1, #steps do
		local st = steps[i]
		st.count = math.ceil(st.crafts - 1e-6)
		st.total = st.count * st.unit
	end
	return steps, stuck
end

--- The rank you train next once your max skill is `cap`.
local function NextRank(profKey, cap)
	local ranks = ns.RankInfo[profKey] or {}
	for step = 1, 6 do
		local r = ranks[step]
		if r and r.cap > cap then return step, r end
	end
end

--- Build a path. state = { skill, max }. Returns
---   { prof, from, to, steps = { craft / train / stuck }, crafts, cost, estimated }
function ns:BuildPath(profKey, state)
	local rate = ns:Rate()
	local skill = math.max(state.skill or 0, 0)
	local cap = math.max(state.max or 0, skill)
	local target = ns:Target()
	if target == "rank" then target = cap end
	target = math.min(target, ns.MAX_SKILL)
	if target < skill then target = skill end

	local path = { prof = profKey, from = skill, to = target, steps = {}, crafts = 0, cost = 0,
	               estimated = false, rate = rate }
	local cands = Candidates(profKey)
	path.recipes = #cands
	local s = skill
	while s < target do
		if s >= cap then
			local step, r = NextRank(profKey, cap)
			if not step then
				path.steps[#path.steps + 1] = { kind = "stuck", from = s, why = "norank" }
				break
			end
			path.steps[#path.steps + 1] = { kind = "train", from = s, rank = step, cap = r.cap,
			                                lvl = r.lvl, skill = r.skill, cost = r.cost }
			cap = r.cap
		end
		local segEnd = math.min(target, cap)
		local steps, stuck = Segment(cands, s, segEnd, rate)
		for i = 1, #steps do
			local st = steps[i]
			path.steps[#path.steps + 1] = st
			path.crafts = path.crafts + st.count
			path.cost = path.cost + st.total
			if st.est then path.estimated = true end
		end
		if stuck then
			path.steps[#path.steps + 1] = { kind = "stuck", from = stuck, why = "norecipe" }
			break
		end
		s = segEnd
	end
	path.shopping = ns:ShoppingFor(path)
	return path
end

--- Every material the path needs, in total: { {id, need, have, missing}, ... }
function ns:ShoppingFor(path)
	local need = {}
	for i = 1, #path.steps do
		local st = path.steps[i]
		if st.kind == "craft" then
			for k = 1, #st.rec.r, 2 do
				local id = st.rec.r[k]
				need[id] = (need[id] or 0) + st.rec.r[k + 1] * st.count
			end
		end
	end
	local out = {}
	for id, n in pairs(need) do
		out[#out + 1] = { id = id, need = n }
	end
	table.sort(out, function(a, b)
		local na = ns.Items[a.id] and ns.Items[a.id].n or ""
		local nb = ns.Items[b.id] and ns.Items[b.id].n or ""
		return na < nb
	end)
	return out
end

--- Fill in have / missing for a shopping list (bags change often; the path
--- itself does not need recomputing for that).
function ns:CountShopping(list)
	local missingCost = 0
	for i = 1, #list do
		local e = list[i]
		e.have = ns:ItemHave(e.id)
		e.missing = math.max(0, e.need - e.have)
		local c = ItemCost(e.id, 0)
		e.cost = c and c * e.missing or nil
		missingCost = missingCost + (e.cost or 0)
	end
	return missingCost
end

----------------------------------------------------------------------
-- cache
----------------------------------------------------------------------

local cache = {}

--- The path for a profession you have (state from the game), or for any
--- profession at a given state (the browser's preview).
function ns:GetPath(profKey, state)
	state = state or ns:ProfessionState(profKey)
	if not state then return nil end
	local key = profKey .. ":" .. state.skill .. ":" .. state.max
	local c = cache[key]
	if c and c.version == version then return c end
	local path = ns:BuildPath(profKey, state)
	path.version = version
	cache[key] = path
	return path
end

--- Recipes usable at a skill, cheapest per skill point first: the
--- alternatives to a step.
function ns:Alternatives(profKey, skill, limit)
	local out = {}
	local cands = Candidates(profKey)
	for i = 1, #cands do
		local c = cands[i]
		if Usable(c, skill) then
			local ch = CHANCE[ns:RecipeColor(c.rec, skill)]
			out[#out + 1] = { rec = c.rec, perPoint = c.cost / ch / ns:Rate(), color = ns:RecipeColor(c.rec, skill), est = c.est }
		end
	end
	table.sort(out, function(a, b) return a.perPoint < b.perPoint end)
	while limit and #out > limit do table.remove(out) end
	return out
end

function ns:InvalidatePaths()
	version = version + 1
	cache = {}
	ns:Fire("GuideChanged")
end

function M:OnLoad()
	ns:Subscribe("ProfessionsChanged", function() ns:InvalidatePaths() end)
	ns:Subscribe("PricesChanged", function() ns:InvalidatePaths() end)
	ns:Subscribe("SettingChanged", function(section, key)
		if section == "guide" or (section == "char" and key == "faction") then ns:InvalidatePaths() end
	end)
end
