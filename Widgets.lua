--[[ FycoProfessions - Widgets.lua
     Small UI building blocks the window tabs, the tracker and the options
     panels share: dropdowns, item buttons and item link/colour helpers. Built
     from stock 3.3.5a templates only, so the addon has zero dependencies.   ]]

local _, ns = ...

local UI = {}
ns.UI = UI

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

--- "|cffa335ee" for a quality number, falling back to white.
function UI.QualityHex(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	return (c and c.hex) or "|cffffffff"
end

local function OurItem(id)
	return ns.Items and ns.Items[id]
end

--- A clickable item link. Uses the client's own link when the item is in its
--- cache; otherwise builds one from our data, which renders and links the same.
function UI.ItemLink(id)
	local _, link = GetItemInfo(id)
	if link then return link end
	local it = OurItem(id)
	local name = it and it.n or ("item " .. id)
	return UI.QualityHex(it and it.q) .. "|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
end

function UI.ItemName(id)
	local it = OurItem(id)
	local name = (it and it.n) or GetItemInfo(id) or ("item " .. id)
	return UI.QualityHex(it and it.q) .. name .. "|r"
end

--- Icon path. GetItemIcon answers even for items the client has not cached;
--- GetItemInfo only answers once it has, so it is the fallback, not the rule.
function UI.ItemIcon(id)
	if not id then return nil end
	local tex = GetItemIcon and GetItemIcon(id)
	if not tex then tex = select(10, GetItemInfo(id)) end
	return tex or QUESTION
end

--- Which side a tooltip should open on so it does not run off the screen.
function UI.AnchorFor(frame)
	local x = frame:GetCenter()
	local w = UIParent:GetWidth()
	if not x or not w then return "ANCHOR_RIGHT" end
	return (x > w / 2) and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

----------------------------------------------------------------------
-- item button: icon, item tooltip on hover, shift-click links it
----------------------------------------------------------------------

function UI.ItemButton(parent, size, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(size)
	b:SetHeight(size)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints(b)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	function b:SetItem(id, link)
		self.itemID, self.link = id, link
		if id then
			self.icon:SetTexture(UI.ItemIcon(id))
			self.icon:SetVertexColor(1, 1, 1)
			self:Show()
		else
			self.icon:SetTexture(QUESTION)
			self.icon:SetVertexColor(0.3, 0.3, 0.3)
		end
	end

	b:SetScript("OnEnter", function(self)
		if not self.itemID then return end
		GameTooltip:SetOwner(self, UI.AnchorFor(self))
		GameTooltip:SetHyperlink(self.link or ("item:" .. self.itemID .. ":0:0:0:0:0:0:0:0"))
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self, button)
		if not self.itemID then return end
		-- shift links it into chat, ctrl opens the dressing room; returns
		-- false when no modifier is held
		if HandleModifiedItemClick(self.link or UI.ItemLink(self.itemID)) then return end
		if onClick then onClick(self, button) end
	end)
	return b
end

----------------------------------------------------------------------
-- money and colours
----------------------------------------------------------------------

--- "12g 50s 3c" in plain text: safe in chat, in tooltips and in rows.
function UI.Money(copper)
	copper = math.floor((copper or 0) + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return string.format("%dg %02ds", g, s) end
	if s > 0 then return string.format("%ds %02dc", s, c) end
	return c .. "c"
end

-- recipe and node difficulty colours, as the trade skill window shows them
UI.ColorHex = {
	red = "|cffff2020", orange = "|cffff8040", yellow = "|cffffff00",
	green = "|cff40c040", grey = "|cff808080",
}

function UI.Colored(color, text)
	return (UI.ColorHex[color] or "|cffffffff") .. text .. "|r"
end

----------------------------------------------------------------------
-- row list: a scrolling list of clickable rows, the one list widget
-- every guide view is built from
----------------------------------------------------------------------

--- rows: { text, right, icon, item (id), tip (lines), onClick, key }.
--- name must be unique (the faux scroll template needs a global name).
function UI.RowList(parent, name, width, height, rowH)
	rowH = rowH or 18
	local list = CreateFrame("Frame", name, parent)
	list:SetWidth(width)
	list:SetHeight(height)
	list.data, list.rows, list.selected = {}, {}, nil

	local scroll = CreateFrame("ScrollFrame", name .. "Scroll", list, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -24, 0)

	local visible = math.max(1, math.floor(height / rowH))

	local function Update()
		local offset = FauxScrollFrame_GetOffset(scroll)
		for i = 1, visible do
			local row, d = list.rows[i], list.data[i + offset]
			if d then
				row.data = d
				row.text:SetText(d.text or "")
				row.right:SetText(d.right or "")
				if d.icon then
					row.icon:SetTexture(d.icon)
					row.icon:Show()
					row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
				else
					row.icon:Hide()
					row.text:SetPoint("LEFT", row, "LEFT", 4 + (d.indent or 0), 0)
				end
				if list.selected ~= nil and d.key == list.selected then row:LockHighlight() else row:UnlockHighlight() end
				row:Show()
			else
				row.data = nil
				row:Hide()
			end
		end
		FauxScrollFrame_Update(scroll, #list.data, visible, rowH)
	end

	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, rowH, Update)
	end)

	for i = 1, visible do
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(rowH)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
		row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetWidth(rowH - 2)
		row.icon:SetHeight(rowH - 2)
		row.icon:SetPoint("LEFT", 2, 0)

		row.right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.right:SetPoint("RIGHT", -4, 0)
		row.right:SetJustifyH("RIGHT")

		row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 4, 0)
		row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
		row.text:SetJustifyH("LEFT")

		row:SetScript("OnClick", function(self, button)
			local d = self.data
			if not d then return end
			if d.item and HandleModifiedItemClick(UI.ItemLink(d.item)) then return end
			if d.onClick then d.onClick(d, button) end
		end)
		row:SetScript("OnEnter", function(self)
			local d = self.data
			if not d or not (d.item or d.tip) then return end
			GameTooltip:SetOwner(self, UI.AnchorFor(self))
			if d.item then
				GameTooltip:SetHyperlink("item:" .. d.item .. ":0:0:0:0:0:0:0:0")
			end
			for j = 1, #(d.tip or {}) do
				GameTooltip:AddLine(d.tip[j], 1, 1, 1, true)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		list.rows[i] = row
	end

	function list:SetData(data, keepScroll)
		self.data = data or {}
		if not keepScroll then
			FauxScrollFrame_SetOffset(scroll, 0)
			local bar = _G[scroll:GetName() .. "ScrollBar"]
			if bar then bar:SetValue(0) end
		end
		Update()
	end

	function list:Select(key)
		self.selected = key
		Update()
	end

	function list:Count()
		return #self.data
	end

	return list
end

----------------------------------------------------------------------
-- dropdown
----------------------------------------------------------------------

--- A stock dropdown driven by three functions, so the same widget serves the
--- window header and the options panels and both always show the live value:
---   opts.items() -> { { value = v, text = "label" }, ... }
---   opts.get()   -> the selected value
---   opts.set(v)
--- The template needs a global name; `name` must be unique.
function UI.Dropdown(parent, name, width, opts)
	local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
	UIDropDownMenu_SetWidth(dd, width)

	-- Re-run by the client every time the menu opens, so the ticks are always
	-- current. Arguments are ignored on purpose: 3.3.5a passes them in a
	-- different order than later clients, and these menus have one level.
	local function init()
		local list, cur = opts.items(), opts.get()
		for i = 1, #list do
			local e = list[i]
			local info = UIDropDownMenu_CreateInfo()
			info.text = e.text
			info.value = e.value
			info.checked = (e.value == cur)
			info.func = function(btn)
				opts.set(btn.value)
				dd.Refresh()
			end
			UIDropDownMenu_AddButton(info)
		end
	end

	-- Initialise once. Doing it again on every refresh would close whatever
	-- dropdown menu the player has open at that moment.
	UIDropDownMenu_Initialize(dd, init)

	function dd.Refresh()
		local list, cur = opts.items(), opts.get()
		local text = ""
		for i = 1, #list do
			if list[i].value == cur then text = list[i].text end
		end
		UIDropDownMenu_SetText(dd, text)
	end

	return dd
end

----------------------------------------------------------------------
-- dropdown contents shared by the window and the options
----------------------------------------------------------------------

UI.Rate = {
	items = function()
		local out = {}
		for i = 1, #ns.Rates do
			local r = ns.Rates[i]
			out[#out + 1] = { value = r, text = "x" .. r .. (r == 1 and " (stock)" or "") }
		end
		return out
	end,
	get = function() return ns:Rate() end,
	set = function(v) ns:SetRate(v) end,
}

UI.Target = {
	items = function()
		local out = { { value = "rank", text = "Your rank's cap" } }
		for i = 1, #ns.Ranks do
			local r = ns.Ranks[i]
			out[#out + 1] = { value = r.cap, text = r.cap .. " (" .. r.name .. ")" }
		end
		return out
	end,
	get = function() return ns:Target() end,
	set = function(v) ns:SetTarget(v) end,
}

UI.Faction = {
	items = function()
		return {
			{ value = "auto", text = "Auto (" .. (UnitFactionGroup("player") or "?") .. ")" },
			{ value = "Alliance", text = "Alliance" },
			{ value = "Horde", text = "Horde" },
		}
	end,
	get = function() return ns:FactionIsAuto() and "auto" or ns:Faction() end,
	set = function(v) ns:SetFaction(v) end,
}

UI.Materials = {
	items = function()
		return {
			{ value = "ah", text = ns.MaterialsText.ah },
			{ value = "gathered", text = ns.MaterialsText.gathered },
		}
	end,
	get = function() return ns:Materials() end,
	set = function(v) ns:Set("guide", "materials", v) end,
}
