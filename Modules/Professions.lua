--[[ FycoProfessions - Modules/Professions.lua
     What the character has, read from the game:
       - professions, skill and max skill (GetSkillLineInfo), rescanned on
         every skill change, with collapsed headers expanded and put back
       - the recipes it already knows, read whenever a trade skill window
         opens (the only place 3.3.5a lists them)
       - reputation standings, for vendor recipes that need one
       - what is in the bank, remembered from the last visit, because the
         bank cannot be read from anywhere else

     It also registers one window tab per profession, shown only for the
     professions this character has. ProfessionsChanged fires when any of
     it changes.                                                          ]]

local _, ns = ...
local M = ns:Module("professions", 10)

local have = {}          -- key -> { key, prof, skill, max }
local haveList = {}

----------------------------------------------------------------------
-- skill lines
----------------------------------------------------------------------

--- Read every skill line. Collapsed headers hide their lines, so expand
--- them, read, and collapse them again so the character sheet looks the
--- same as before.
local skillQuietUntil = 0      -- see ns:ScanProfessions

local function ReadSkills()
	local expanded = {}
	local i = 1
	while i <= (GetNumSkillLines() or 0) do
		local name, isHeader, isExpanded = GetSkillLineInfo(i)
		if isHeader and not isExpanded then
			-- the event this fires can arrive at once, inside this call
			skillQuietUntil = GetTime() + 0.5
			ExpandSkillHeader(i)
			expanded[#expanded + 1] = name
		end
		i = i + 1
	end

	local found = {}
	for j = 1, (GetNumSkillLines() or 0) do
		local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(j)
		local prof = not isHeader and ns.ProfessionByName[name]
		if prof then
			found[prof.key] = { key = prof.key, prof = prof, skill = rank or 0, max = maxRank or 0 }
		end
	end

	-- collapse what we opened, by name, last first (indices shift as we go)
	for k = #expanded, 1, -1 do
		for j = 1, (GetNumSkillLines() or 0) do
			local name, isHeader = GetSkillLineInfo(j)
			if isHeader and name == expanded[k] then
				CollapseSkillHeader(j)
				break
			end
		end
	end
	return found, #expanded > 0
end

local function Signature(t)
	local keys = {}
	for k, v in pairs(t) do keys[#keys + 1] = k .. "=" .. v.skill .. "/" .. v.max end
	table.sort(keys)
	return table.concat(keys, ",")
end

local lastSig

-- Expanding a collapsed header makes the game fire SKILL_LINES_CHANGED.
-- Reacting to that would expand again, and loop every frame; so for half a
-- second after a read THAT EXPANDED SOMETHING, the event is ours and is
-- ignored. Only then: an unconditional quiet period also swallowed the
-- SKILL_LINES_CHANGED that brings the skills in just after login, and every
-- profession read as unlearned (1/75) until the next skill-up.
local lastScan = 0
local scanning = false

function ns:ScanProfessions()
	if scanning then return end   -- an event fired from inside our own read
	scanning = true
	local ok, found, expanded = pcall(ReadSkills)
	scanning = false
	if not ok then error(found) end
	lastScan = GetTime()
	if expanded then skillQuietUntil = GetTime() + 0.5 end
	-- a read that found nothing while professions were known is the client
	-- not having its skill list yet (loading screens), not you unlearning
	-- everything: keep what we had until a read says otherwise
	if next(found) == nil and next(have) ~= nil then return end
	have = found
	haveList = {}
	for i = 1, #ns.Professions do
		local p = ns.Professions[i]
		if found[p.key] then haveList[#haveList + 1] = found[p.key] end
		ns:ShowTab(p.key, found[p.key] ~= nil)
	end
	local sig = Signature(found)
	if sig ~= lastSig then
		lastSig = sig
		ns:Fire("ProfessionsChanged")
	end
end

--- The professions this character has, in ns.Professions order.
function ns:PlayerProfessions()
	return haveList
end

function ns:HasProfession(key)
	return have[key] ~= nil
end

--- { skill, max } for a profession you have, or nil.
function ns:ProfessionState(key)
	return have[key]
end

----------------------------------------------------------------------
-- known recipes, from the trade skill window
----------------------------------------------------------------------

local function Known()
	FycoProfessionsCharDB.known = FycoProfessionsCharDB.known or {}
	return FycoProfessionsCharDB.known
end

local function ReadTradeSkill()
	local name = GetTradeSkillLine and GetTradeSkillLine()
	local prof = name and ns.ProfessionByName[name]
	if not prof then return end
	-- a linked trade skill (someone else's) must not count as yours
	if IsTradeSkillLinked and IsTradeSkillLinked() then return end
	-- the window states your skill too: if it disagrees with what we have,
	-- the skill list has changed under us -- read it again
	local _, rank = GetTradeSkillLine()
	local mine = have[prof.key]
	if not mine or (rank and rank ~= mine.skill) then ns:ScanProfessions() end
	local known = {}
	local n = 0
	for i = 1, (GetNumTradeSkills() or 0) do
		local _, kind = GetTradeSkillInfo(i)
		if kind ~= "header" then
			local link = GetTradeSkillRecipeLink(i)
			local id = link and tonumber(link:match("enchant:(%d+)"))
			if id then
				known[id] = true
				n = n + 1
			end
		end
	end
	if n == 0 then return end
	-- the window may be filtered; add to what we knew rather than replace
	local all = Known()
	all[prof.key] = all[prof.key] or {}
	local changed = false
	for id in pairs(known) do
		if not all[prof.key][id] then
			all[prof.key][id] = true
			changed = true
		end
	end
	if changed then ns:Fire("ProfessionsChanged") end
end

function ns:KnowsRecipe(profKey, spell)
	local k = FycoProfessionsCharDB and FycoProfessionsCharDB.known
	return k and k[profKey] and k[profKey][spell] or false
end

function ns:KnownCount(profKey)
	local k = FycoProfessionsCharDB and FycoProfessionsCharDB.known
	local n = 0
	for _ in pairs(k and k[profKey] or {}) do n = n + 1 end
	return n
end

----------------------------------------------------------------------
-- spells (specialisations) and reputation
----------------------------------------------------------------------

--- 3.3.5a: GetSpellInfo(name) only answers for spells in your spellbook.
function ns:KnowsSpell(id)
	local name = GetSpellInfo(id)
	return name ~= nil and GetSpellInfo(name) ~= nil
end

local STANDING = { Hated = 1, Hostile = 2, Unfriendly = 3, Neutral = 4, Friendly = 5, Honored = 6, Revered = 7, Exalted = 8 }
local standings
local repQuietUntil = 0   -- same loop guard as for skills: our expanding fires UPDATE_FACTION

local function ReadReputations()
	repQuietUntil = GetTime() + 1
	standings = {}
	local expanded = {}
	local i = 1
	while i <= (GetNumFactions() or 0) do
		local name, _, standing, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i)
		if isHeader and isCollapsed then
			ExpandFactionHeader(i)
			expanded[#expanded + 1] = name
		elseif name and not isHeader then
			standings[name] = standing
		end
		i = i + 1
	end
	for k = #expanded, 1, -1 do
		for j = 1, (GetNumFactions() or 0) do
			local name, _, _, _, _, _, _, _, isHeader = GetFactionInfo(j)
			if isHeader and name == expanded[k] then
				CollapseFactionHeader(j)
				break
			end
		end
	end
end

--- Is your standing with `faction` at least `rank` ("Honored")? nil when
--- the faction is not in your reputation list at all.
function ns:RepAtLeast(faction, rank)
	if not standings then ReadReputations() end
	local have = standings[faction]
	if not have then return nil end
	return have >= (STANDING[rank] or 9)
end

----------------------------------------------------------------------
-- bags and bank
----------------------------------------------------------------------

local BANK_BAGS = { -1, 5, 6, 7, 8, 9, 10, 11 }
local bankOpen = false

local function ReadBank()
	local counts = {}
	for i = 1, #BANK_BAGS do
		local bag = BANK_BAGS[i]
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local link = GetContainerItemLink(bag, slot)
			local id = link and tonumber(link:match("item:(%d+)"))
			if id then
				local _, count = GetContainerItemInfo(bag, slot)
				counts[id] = (counts[id] or 0) + (count or 1)
			end
		end
	end
	FycoProfessionsCharDB.bank = counts
	FycoProfessionsCharDB.bankTime = time()
	ns:Fire("BagsChanged")
end

--- Bags now, plus the bank as it was on your last visit.
function ns:ItemHave(id)
	local bags = GetItemCount(id) or 0
	local bank = FycoProfessionsCharDB and FycoProfessionsCharDB.bank
	return bags + (bank and bank[id] or 0), bags
end

function ns:BankKnown()
	return FycoProfessionsCharDB and FycoProfessionsCharDB.bankTime ~= nil
end

----------------------------------------------------------------------
-- window tabs, one per profession
----------------------------------------------------------------------

for i = 1, #ns.Professions do
	local p = ns.Professions[i]
	ns:AddTab(p.key, p.name, 10 + i, function(pane)
		pane.view = ns:CreateView(pane, p.kind, 664, 438, function() return p.key end,
			function() return ns:ProfessionState(p.key) end)
	end, function(pane)
		ns:SetChar("tracked", p.key)
		if pane.view then pane.view:Refresh() end
	end)
	ns:ShowTab(p.key, false)
end

--- The profession the tracker follows: the last profession tab you opened,
--- or your first profession.
function ns:TrackedProfession()
	local t = ns:GetChar("tracked")
	if t and have[t] then return t end
	return haveList[1] and haveList[1].key
end

----------------------------------------------------------------------

local bagDirty = false

function M:OnLoad()
	ns:ScanProfessions()
	ns:On("SKILL_LINES_CHANGED", function()
		if GetTime() >= skillQuietUntil then ns:ScanProfessions() end
	end)
	ns:On("CHAT_MSG_SKILL", function() ns:ScanProfessions() end)
	ns:On("PLAYER_ENTERING_WORLD", function() ns:ScanProfessions() end)
	ns:On("TRADE_SKILL_SHOW", ReadTradeSkill)
	ns:On("TRADE_SKILL_UPDATE", ReadTradeSkill)
	-- rep ticks up with every kill while grinding; recompute paths only when
	-- a standing actually changes tier
	ns:On("UPDATE_FACTION", function()
		if GetTime() < repQuietUntil then return end
		local old = standings
		ReadReputations()
		local changed = old == nil
		for name, st in pairs(standings) do
			if not changed and old[name] ~= st then changed = true end
		end
		if changed then ns:Fire("ProfessionsChanged") end
	end)
	ns:On("BANKFRAME_OPENED", function()
		bankOpen = true
		ReadBank()
	end)
	ns:On("BANKFRAME_CLOSED", function() bankOpen = false end)
	ns:On("PLAYERBANKSLOTS_CHANGED", function() if bankOpen then ReadBank() end end)
	ns:On("BAG_UPDATE", function() bagDirty = true end)
	-- bag events come in bursts; tell everyone at most twice a second
	local last = 0
	local loginAt = GetTime()
	ns:OnTick(function(now)
		if bagDirty and now - last >= 0.5 then
			bagDirty, last = false, now
			if bankOpen then ReadBank() else ns:Fire("BagsChanged") end
		end
		-- no professions found yet: the skill list may simply not have
		-- arrived. Look again every 3 s for the first minute after login,
		-- then every 30 s (a character with no professions costs nothing much)
		if next(have) == nil then
			local every = (now - loginAt < 60) and 3 or 30
			if now - lastScan >= every then ns:ScanProfessions() end
		end
	end)
end

--- "/fprof professions": what the skill list says, and what was detected.
function ns:ProfessionsReport()
	ns:ScanProfessions()
	ns:Print("skill lines the game lists: " .. (GetNumSkillLines() or 0))
	if #haveList == 0 then
		ns:Print("  no profession detected. If you have some, open your character "
			.. "sheet's Skills tab once, then try again, and tell me what it lists.")
	end
	for _, e in ipairs(haveList) do
		ns:Print(string.format("  %s: %d / %d", e.prof.name, e.skill, e.max))
	end
end
