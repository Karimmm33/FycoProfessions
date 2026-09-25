--[[ FycoProfessions - Modules/Views.lua
     The content of a profession tab, and of the browser's right side.

     ns:CreateView(parent, kind, width, height, getProf, getState) builds
     one view: a title, a summary, mode buttons, and two row lists (left:
     steps / materials / zones, right: detail of the selected row). kind is
     the profession's kind; "craft" is built here, "gather" and "fish" by
     Modules/Gather.lua through ns.ViewBuilders.

     Crafting modes: Path (the steps), Shopping list (every material the
     path needs, against bags and bank), Extras (prospecting, the Dalaran
     dailies, milling, disenchanting, smelting) where a profession has them. ]]

local _, ns = ...
local M = ns:Module("views", 20)
local UI = ns.UI

local HEADER_H = 50
local GREY, WHITE, GOLD, RED, GREEN, BLUE = "|cffa0a0a0", "|cffffffff", "|cffffd200", "|cffff6060", "|cff60ff60", "|cff66ccff"

ns.ViewBuilders = {}
ns.TrackerProviders = {}
local views = {}
local viewN = 0

local function RankName(step)
	local r = ns.Ranks[step]
	return r and r.name or ("rank " .. step)
end

local function RankOf(max)
	for i = 1, #ns.Ranks do
		if ns.Ranks[i].cap >= max then return ns.Ranks[i].name end
	end
	return ""
end

function ns:StateTitle(prof, state)
	if not state then return prof.name end
	local t = string.format("%s  %d / %d", prof.name, state.skill, state.max)
	if state.preview then
		t = t .. GREY .. "  (not learned: a preview from skill " .. state.skill .. ")|r"
	elseif state.max > 0 then
		t = t .. GREY .. "  " .. RankOf(state.max) .. "|r"
	end
	return t
end

local function Row(text, extra)
	local r = extra or {}
	r.text = text
	return r
end

local function Heading(text)
	return { text = GOLD .. text .. "|r" }
end

----------------------------------------------------------------------
-- the view frame shared by every kind
----------------------------------------------------------------------

function ns:CreateView(parent, kind, width, height, getProf, getState)
	viewN = viewN + 1
	local name = "FycoProfessionsView" .. viewN
	local v = CreateFrame("Frame", name, parent)
	v:SetWidth(width)
	v:SetHeight(height)
	v:SetPoint("TOPLEFT", 0, 0)
	v.kind, v.getProf, v.getState = kind, getProf, getState
	v.selected = {}

	v.title = v:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	v.title:SetPoint("TOPLEFT", 0, 0)
	v.title:SetPoint("RIGHT", v, "RIGHT", -250, 0)
	v.title:SetJustifyH("LEFT")

	v.summary = v:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	v.summary:SetPoint("TOPLEFT", 0, -18)
	v.summary:SetPoint("RIGHT", v, "RIGHT", 0, 0)
	v.summary:SetJustifyH("LEFT")
	v.summary:SetJustifyV("TOP")
	v.summary:SetHeight(28)

	local leftW = math.floor(width * 0.52)
	v.left = UI.RowList(v, name .. "Left", leftW, height - HEADER_H)
	v.left:SetPoint("TOPLEFT", 0, -HEADER_H)
	v.right = UI.RowList(v, name .. "Right", width - leftW - 8, height - HEADER_H)
	v.right:SetPoint("TOPLEFT", leftW + 8, -HEADER_H)

	v.buttons = {}
	function v:SetModes(modes)
		for i = 1, #self.buttons do self.buttons[i]:Hide() end
		local x = 0
		for i = #modes, 1, -1 do
			local m = modes[i]
			local b = self.buttons[i]
			if not b then
				b = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
				b:SetHeight(20)
				self.buttons[i] = b
			end
			b:SetWidth(m.w or 80)
			b:ClearAllPoints()
			b:SetPoint("TOPRIGHT", self, "TOPRIGHT", -x, 2)
			x = x + (m.w or 80) + 4
			b:SetText(m.label)
			b.mode = m.key
			b:SetScript("OnClick", function()
				self.mode = m.key
				self:Refresh()
			end)
			if self.mode == m.key then b:Disable() else b:Enable() end
			b:Show()
		end
	end

	local builder = ns.ViewBuilders[kind]
	function v:Refresh()
		if not self:IsVisible() and not self.forceRefresh then return end
		local prof = ns.ProfessionByKey[self.getProf()]
		if not prof then return end
		if self.prof ~= prof.key then
			self.prof, self.mode, self.selected = prof.key, nil, {}
		end
		builder(self, prof, self.getState())
	end

	views[#views + 1] = v
	return v
end

local function RefreshAll()
	for i = 1, #views do views[i]:Refresh() end
end

--- Select a left row and redraw the view (rows call this on click).
local function Picker(v, key)
	return function()
		v.selected[v.mode] = key
		v:Refresh()
	end
end

----------------------------------------------------------------------
-- trainers
----------------------------------------------------------------------

local function Distance(t, zoneName)
	if t.zoneName ~= zoneName then return nil end
	local px, py = GetPlayerMapPosition("player")
	if not px or (px == 0 and py == 0) then return 0 end
	local dx, dy = px * 100 - t.x, py * 100 - t.y
	return math.sqrt(dx * dx + dy * dy)
end

--- Trainers for a profession that teach up to at least `cap`, usable by your
--- faction, nearest first: your zone, then your continent, then the rest.
function ns:NearestTrainers(profKey, cap, limit)
	local list = ns.Trainers[profKey] or {}
	local side = ns:Faction() == "Horde" and "H" or "A"
	local here = GetRealZoneText() or ""
	local myContinent
	for _, z in pairs(ns.Zones) do
		if z.n == here then myContinent = z.c break end
	end
	local out = {}
	for i = 1, #list do
		local t = list[i]
		if t.max >= cap and (t.side == "B" or t.side == side) then
			local z = ns.Zones[t.z]
			t.zoneName = z and z.n or "?"
			local d = Distance(t, here)
			local rank = d and 0 or ((z and z.c == myContinent) and 1 or 2)
			out[#out + 1] = { t = t, rank = rank, d = d or 0 }
		end
	end
	table.sort(out, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.d ~= b.d then return a.d < b.d end
		return a.t.max < b.t.max
	end)
	local res = {}
	for i = 1, math.min(limit or 4, #out) do
		local e = out[i]
		res[i] = { t = e.t, where = e.rank == 0 and "in your zone" or (e.rank == 1 and "on this continent" or nil) }
	end
	return res
end

function ns:TrainerText(e)
	local t = e.t
	local s = WHITE .. t.n .. "|r" .. (t.t and (GREY .. " <" .. t.t .. ">|r") or "")
		.. " - " .. t.zoneName .. string.format(" (%.0f, %.0f)", t.x, t.y)
	if e.where then s = s .. GREEN .. " " .. e.where .. "|r" end
	return s
end

----------------------------------------------------------------------
-- crafting: path mode
----------------------------------------------------------------------

local function ItemIconOr(id, fallback)
	return id and UI.ItemIcon(id) or fallback
end

local function StepRow(v, i, st, prof)
	if st.kind == "craft" then
		local name = st.rec.n
		return {
			key = i, icon = ItemIconOr(st.rec.it, prof.icon),
			text = UI.Colored(st.color, "Make " .. st.count .. " x " .. name),
			right = st.from .. " - " .. st.to, onClick = Picker(v, i),
		}
	elseif st.kind == "train" then
		local lvlBad = st.lvl and st.lvl > (UnitLevel("player") or 80)
		return {
			key = i, icon = "Interface\\Icons\\INV_Misc_Book_11",
			text = BLUE .. "Train " .. RankName(st.rank) .. "|r" .. (st.lvl and st.lvl > 0 and
				((lvlBad and RED or GREY) .. " (level " .. st.lvl .. ")|r") or ""),
			right = "at " .. st.from, onClick = Picker(v, i),
		}
	else
		return {
			key = i, icon = "Interface\\Icons\\INV_Misc_QuestionMark",
			text = RED .. (st.why == "norank" and "No higher rank known" or "No usable recipe from here") .. "|r",
			right = "at " .. st.from, onClick = Picker(v, i),
		}
	end
end

local function ThresholdText(rec)
	return UI.Colored("orange", rec.o) .. "  " .. UI.Colored("yellow", rec.y) .. "  "
		.. UI.Colored("green", rec.g) .. "  " .. UI.Colored("grey", rec.gr)
end

local function CraftDetail(v, prof, st, path)
	local rows = {}
	local rec = st.rec
	rows[#rows + 1] = Row(UI.Colored(st.color, rec.n), { item = rec.it, icon = ItemIconOr(rec.it, prof.icon) })
	rows[#rows + 1] = Row(GREY .. "Orange, yellow, green, grey from:|r " .. ThresholdText(rec))
	rows[#rows + 1] = Row(string.format("Make %d, skill %d to %d %s(x%d per skill-up)|r", st.count, st.from, st.to,
		GREY, path.rate))
	rows[#rows + 1] = Row("About " .. UI.Money(st.unit) .. " a craft, " .. UI.Money(st.total) .. " in all"
		.. (st.est and (GREY .. " (includes estimates)|r") or ""))
	rows[#rows + 1] = Heading("Materials for this step")
	for k = 1, #rec.r, 2 do
		local id, n = rec.r[k], rec.r[k + 1]
		local total = n * st.count
		local haveN = ns:ItemHave(id)
		local col = haveN >= total and GREEN or RED
		local _, kind = ns:ItemCost(id)
		rows[#rows + 1] = Row(UI.ItemName(id) .. GREY .. " x" .. n .. "|r", {
			icon = UI.ItemIcon(id), item = id, right = col .. haveN .. " / " .. total .. "|r",
			tip = ns:ItemSourceLines(id),
		})
		if kind == "estimate" then rows[#rows].text = rows[#rows].text .. GREY .. " (price estimated)|r" end
	end
	if rec.tl then rows[#rows + 1] = Row(GREY .. "Needs:|r " .. table.concat(rec.tl, ", ")) end
	rows[#rows + 1] = Heading("How to learn it")
	local ok, how = ns:RecipeStatus(prof.key, rec)
	rows[#rows + 1] = Row((ok and GREEN or RED) .. (ns.StatusText[how] or "") .. "|r")
	local lines = ns:RecipeSourceLines(rec)
	for i = 1, #lines do rows[#rows + 1] = Row(lines[i], { tip = { lines[i] } }) end
	local alts = ns:Alternatives(prof.key, st.from, 4)
	if #alts > 1 then
		rows[#rows + 1] = Heading("Other recipes at " .. st.from)
		for i = 1, #alts do
			local a = alts[i]
			if a.rec ~= rec then
				rows[#rows + 1] = Row(UI.Colored(a.color, a.rec.n), {
					icon = ItemIconOr(a.rec.it, prof.icon), item = a.rec.it,
					right = UI.Money(a.perPoint) .. "/pt" .. (a.est and "*" or ""),
				})
			end
		end
	end
	return rows
end

local function TrainDetail(prof, st)
	local rows = {}
	local lvl = UnitLevel("player") or 80
	rows[#rows + 1] = Heading("Train " .. RankName(st.rank) .. " (skill cap " .. st.cap .. ")")
	if st.lvl and st.lvl > 0 then
		rows[#rows + 1] = Row("Needs level " .. st.lvl .. ((st.lvl > lvl) and (RED .. " - you are " .. lvl .. "|r") or ""))
	end
	if st.skill and st.skill > 0 then rows[#rows + 1] = Row("Needs skill " .. st.skill) end
	if st.cost then rows[#rows + 1] = Row("Costs " .. UI.Money(st.cost)) end
	rows[#rows + 1] = Row(GREY .. "Levels and costs are the stock game's; this realm may differ.|r")
	rows[#rows + 1] = Heading("Nearest trainers for " .. ns:Faction())
	local list = ns:NearestTrainers(prof.key, st.cap, 5)
	for i = 1, #list do rows[#rows + 1] = Row(ns:TrainerText(list[i])) end
	if #list == 0 then rows[#rows + 1] = Row(RED .. "No trainer for this rank in the stock database.|r") end
	return rows
end

local function StuckDetail(st)
	local rows = { Heading("Stuck at " .. st.from) }
	if st.why == "norank" then
		rows[#rows + 1] = Row("There is no higher trainer rank for this profession in the data.")
	else
		rows[#rows + 1] = Row("No recipe you have or can get gives skill-ups at " .. st.from .. ".")
		rows[#rows + 1] = Row(GREY .. "- Open your profession window once: recipes you already know are read from it.|r")
		rows[#rows + 1] = Row(GREY .. "- Allow recipes from drops in the settings, if you can buy them.|r")
		rows[#rows + 1] = Row(GREY .. "- Recipes that need reputation count once your standing is high enough.|r")
	end
	return rows
end

local function PathMode(v, prof, state)
	local path = ns:GetPath(prof.key, state)
	local rows = {}
	for i = 1, #path.steps do rows[i] = StepRow(v, i, path.steps[i], prof) end
	if #rows == 0 then
		rows[1] = Row(GREEN .. "At your target (" .. path.to .. ").|r "
			.. GREY .. "Raise the target in the settings, or train the next rank.|r")
	end
	v.left:SetData(rows, true)
	local sel = v.selected.path or (path.steps[1] and 1)
	if sel and not path.steps[sel] then sel = 1 end
	v.left:Select(sel)

	local st = sel and path.steps[sel]
	local detail
	if not st then
		detail = { Row(GREY .. "Nothing to do for this target.|r") }
	elseif st.kind == "craft" then
		detail = CraftDetail(v, prof, st, path)
	elseif st.kind == "train" then
		detail = TrainDetail(prof, st)
	else
		detail = StuckDetail(st)
	end
	v.right:SetData(detail)

	local s = string.format("To %d at x%d: about %d crafts, %s%s", path.to, path.rate, path.crafts,
		UI.Money(path.cost), path.estimated and (GREY .. " (some prices estimated)|r") or "")
	s = s .. "\n" .. GREY .. path.recipes .. " recipes usable"
	if not state.preview and ns:KnownCount(prof.key) == 0 then
		s = s .. " - open your " .. prof.name .. " window once so FycoProfessions sees what you know"
	end
	v.summary:SetText(s .. "|r")
end

----------------------------------------------------------------------
-- crafting: shopping mode
----------------------------------------------------------------------

local function ShoppingMode(v, prof, state)
	local path = ns:GetPath(prof.key, state)
	local list = path.shopping
	local missingCost = ns:CountShopping(list)
	local rows, still = {}, 0
	for i = 1, #list do
		local e = list[i]
		if e.missing > 0 then still = still + 1 end
		rows[i] = {
			key = e.id, icon = UI.ItemIcon(e.id), item = e.id,
			text = UI.ItemName(e.id),
			right = (e.missing > 0 and RED or GREEN) .. e.have .. " / " .. e.need .. "|r",
			onClick = Picker(v, e.id),
		}
	end
	if #rows == 0 then rows[1] = Row(GREY .. "This path needs no materials.|r") end
	v.left:SetData(rows, true)
	local sel = v.selected.shopping or (list[1] and list[1].id)
	v.left:Select(sel)

	local detail = {}
	if sel then
		detail[#detail + 1] = Row(UI.ItemName(sel), { icon = UI.ItemIcon(sel), item = sel })
		local lines = ns:ItemSourceLines(sel)
		for i = 1, #lines do detail[#detail + 1] = Row(lines[i]) end
		detail[#detail + 1] = Heading("Used in these steps")
		for i = 1, #path.steps do
			local st = path.steps[i]
			if st.kind == "craft" then
				for k = 1, #st.rec.r, 2 do
					if st.rec.r[k] == sel then
						detail[#detail + 1] = Row(UI.Colored(st.color, st.rec.n), { right = st.rec.r[k + 1] * st.count .. "" })
					end
				end
			end
		end
	end
	v.right:SetData(detail)
	v.summary:SetText(string.format("%d materials, %d still to get, about %s more.", #list, still, UI.Money(missingCost))
		.. "\n" .. GREY .. (ns:BankKnown() and "Counts your bags and your bank as of your last visit."
			or "Counts your bags. Visit your bank once so its contents count too.") .. "|r")
end

----------------------------------------------------------------------
-- extras
----------------------------------------------------------------------

local function ConversionRows(v, tbl, heading)
	local rows = { Heading(heading) }
	local keys = {}
	for id in pairs(tbl) do keys[#keys + 1] = id end
	table.sort(keys, function(a, b)
		return (ns.Items[a] and ns.Items[a].n or "") < (ns.Items[b] and ns.Items[b].n or "")
	end)
	for i = 1, #keys do
		rows[#rows + 1] = { key = keys[i], icon = UI.ItemIcon(keys[i]), item = keys[i],
			text = UI.ItemName(keys[i]), onClick = Picker(v, keys[i]) }
	end
	return rows
end

local function ConversionDetail(tbl, id, verb)
	local rows = { Row(UI.ItemName(id), { icon = UI.ItemIcon(id), item = id }),
		Row(GREY .. verb .. " 5 at a time. Chance per attempt:|r") }
	for _, g in ipairs(tbl[id] or {}) do
		local amount = g[3] == g[4] and g[3] or (g[3] .. "-" .. g[4])
		rows[#rows + 1] = Row(UI.ItemName(g[1]) .. GREY .. " x" .. amount .. "|r",
			{ icon = UI.ItemIcon(g[1]), item = g[1], right = (g[2] > 0 and (g[2] .. "%") or "group") })
	end
	return rows
end

local function DisenchantDetail(id)
	local rows = { Row(UI.ItemName(id), { icon = UI.ItemIcon(id), item = id }),
		Row(GREY .. "Disenchant items of this quality and item level:|r") }
	local QUALITY = { [2] = "green", [3] = "blue", [4] = "purple" }
	for _, d in ipairs(ns.Disenchant[id] or {}) do
		rows[#rows + 1] = Row(string.format("%s items, level %d-%d", QUALITY[d.q] or ("quality " .. d.q), d.lo, d.hi),
			{ right = (d.ch > 0 and (d.ch .. "%") or "") .. (d.sk > 0 and ("  skill " .. d.sk) or "") })
	end
	return rows
end

local function DailyDetail()
	local d = ns.JCDaily
	local rows = { Heading("Dalaran jewelcrafting dailies"),
		Row(GREY .. "One daily a day from the jewelcrafting quest giver in Dalaran; each rewards|r"),
		Row(UI.ItemName(d.token), { icon = UI.ItemIcon(d.token), item = d.token }) }
	rows[#rows + 1] = Heading("Quests")
	for i = 1, #d.quests do rows[#rows + 1] = Row(d.quests[i]) end
	rows[#rows + 1] = Heading("What the tokens buy")
	for i = 1, #d.rewards do
		local r = d.rewards[i]
		rows[#rows + 1] = Row(UI.ItemName(r.item), { icon = UI.ItemIcon(r.item), item = r.item,
			right = r.cost .. " tokens" })
	end
	return rows
end

local function SmeltingRows(v, state)
	local rows = { Heading("Smelting also gives Mining skill") }
	for _, rec in ipairs(ns.Recipes.mining or {}) do
		local color = ns:RecipeColor(rec, state.skill)
		rows[#rows + 1] = { key = rec.sp, icon = ItemIconOr(rec.it, nil), item = rec.it,
			text = UI.Colored(color, rec.n), right = rec.o .. "/" .. rec.gr, onClick = Picker(v, rec.sp) }
	end
	return rows
end

local EXTRAS = {
	jewelcrafting = function(v, state)
		local rows = { { key = "daily", icon = UI.ItemIcon(ns.JCDaily.token), text = "Dalaran dailies", onClick = Picker(v, "daily") } }
		local conv = ConversionRows(v, ns.Prospect, "Prospecting (ore to gems)")
		for i = 1, #conv do rows[#rows + 1] = conv[i] end
		local sel = v.selected.extras or "daily"
		return rows, sel, sel == "daily" and DailyDetail() or ConversionDetail(ns.Prospect, sel, "Prospect")
	end,
	inscription = function(v)
		local rows = ConversionRows(v, ns.Mill, "Milling (herbs to pigments)")
		local sel = v.selected.extras or (rows[2] and rows[2].key)
		return rows, sel, sel and ConversionDetail(ns.Mill, sel, "Mill") or {}
	end,
	enchanting = function(v)
		local rows = ConversionRows(v, ns.Disenchant, "Disenchanting (where materials come from)")
		local sel = v.selected.extras or (rows[2] and rows[2].key)
		return rows, sel, sel and DisenchantDetail(sel) or {}
	end,
	mining = function(v, state)
		local rows = SmeltingRows(v, state)
		local sel = v.selected.extras
		local detail = {}
		for _, rec in ipairs(ns.Recipes.mining or {}) do
			if rec.sp == sel then
				detail = { Row(rec.n), Row(GREY .. "Orange, yellow, green, grey from:|r " .. ThresholdText(rec)) }
				for k = 1, #rec.r, 2 do
					detail[#detail + 1] = Row(UI.ItemName(rec.r[k]) .. " x" .. rec.r[k + 1],
						{ icon = UI.ItemIcon(rec.r[k]), item = rec.r[k] })
				end
				local lines = ns:RecipeSourceLines(rec)
				for i = 1, #lines do detail[#detail + 1] = Row(lines[i]) end
			end
		end
		return rows, sel, detail
	end,
}
ns.Extras = EXTRAS

local function ExtrasMode(v, prof, state)
	local rows, sel, detail = EXTRAS[prof.key](v, state)
	v.left:SetData(rows, true)
	v.left:Select(sel)
	v.right:SetData(detail)
	v.summary:SetText(GREY .. "From the stock 3.3.5 database; drop rates on this realm may differ.|r")
end

----------------------------------------------------------------------
-- the craft view
----------------------------------------------------------------------

ns.ViewBuilders.craft = function(v, prof, state)
	state = state or { skill = 1, max = 75, preview = true }
	local modes = { { key = "path", label = "Path", w = 60 }, { key = "shopping", label = "Shopping list", w = 100 } }
	if EXTRAS[prof.key] then modes[#modes + 1] = { key = "extras", label = "Extras", w = 60 } end
	v.mode = v.mode or "path"
	v:SetModes(modes)
	v.title:SetText(ns:StateTitle(prof, state))
	if v.mode == "shopping" then
		ShoppingMode(v, prof, state)
	elseif v.mode == "extras" and EXTRAS[prof.key] then
		ExtrasMode(v, prof, state)
	else
		PathMode(v, prof, state)
	end
end

--- The tracker's lines for a crafting profession.
ns.TrackerProviders.craft = function(prof, state)
	local path = ns:GetPath(prof.key, state)
	local title = string.format("%s %d/%d (x%d)", prof.name, state.skill, state.max, path.rate)
	local st = path.steps[1]
	if not st then return title, { GREEN .. "At your target (" .. path.to .. ").|r" } end
	if st.kind == "train" then
		local lines = { BLUE .. "Train " .. RankName(st.rank) .. "|r" .. (st.lvl and st.lvl > 0 and (" (level " .. st.lvl .. ")") or "") }
		local t = ns:NearestTrainers(prof.key, st.cap, 1)[1]
		if t then lines[2] = t.t.n .. " - " .. t.t.zoneName end
		return title, lines
	elseif st.kind == "stuck" then
		return title, { RED .. "No usable recipe at " .. st.from .. "; open the window.|r" }
	end
	local lines = { UI.Colored(st.color, "Make " .. st.count .. " x " .. st.rec.n), GREY .. "until " .. st.to .. "|r" }
	for k = 1, #st.rec.r, 2 do
		local id = st.rec.r[k]
		local need = st.rec.r[k + 1] * st.count
		local haveN = ns:ItemHave(id)
		local it = ns.Items[id]
		lines[#lines + 1] = (haveN >= need and GREEN or RED) .. haveN .. "/" .. need .. "|r " .. (it and it.n or id)
	end
	return title, lines
end

--- "/fprof path [profession]": the next steps of a path, in chat. Plain
--- words only -- no textures or links, so it is safe to read anywhere.
function ns:PathToChat(text)
	text = (text or ""):lower()
	local key
	for _, e in ipairs(ns:PlayerProfessions()) do
		if text ~= "" and e.prof.name:lower():find(text, 1, true) == 1 then key = e.key end
	end
	key = key or (text == "" and ns:TrackedProfession())
	local p = key and ns.ProfessionByKey[key]
	if not p then
		ns:Print(text == "" and "you have no profession to show." or ("you do not have a profession called " .. text .. "."))
		return
	end
	local state = ns:ProfessionState(key)
	if p.kind ~= "craft" then
		local title, lines = ns.TrackerProviders[p.kind](p, state)
		ns:Print(title)
		for i = 1, #lines do ns:Print("  " .. lines[i]) end
		return
	end
	local path = ns:GetPath(key)
	ns:Print(string.format("%s %d/%d, to %d at x%d: about %d crafts, %s", p.name, state.skill, state.max,
		path.to, path.rate, path.crafts, UI.Money(path.cost)))
	for i = 1, math.min(#path.steps, 8) do
		local st = path.steps[i]
		if st.kind == "craft" then
			ns:Print(string.format("  %d. %s (%d to %d)", i, UI.Colored(st.color, "Make " .. st.count .. " x " .. st.rec.n), st.from, st.to))
		elseif st.kind == "train" then
			ns:Print(string.format("  %d. Train %s at %d", i, RankName(st.rank), st.from))
		else
			ns:Print(string.format("  %d. stuck at %d - see the window", i, st.from))
		end
	end
	if #path.steps == 0 then ns:Print("  at your target already.") end
end

function M:OnLoad()
	ns:Subscribe("GuideChanged", RefreshAll)
	ns:Subscribe("BagsChanged", RefreshAll)
end
