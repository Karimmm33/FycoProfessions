--[[ FycoProfessions - Modules/Browser.lua
     The "All professions" tab: every profession in the game, whether this
     character has it or not, so you can look one up before learning it.

     Left, the list. Right, the same guide a profession tab shows: from your
     own skill for a profession you have, and as a preview from skill 1 for
     one you do not.                                                        ]]

local _, ns = ...
local M = ns:Module("browser", 25)

local ROW_H = 26
local LIST_W = 150
local VIEW_W, VIEW_H = 664 - LIST_W - 10, 438

local pane, rows
local views = {}
local selected = "jewelcrafting"

local function State()
	return ns:ProfessionState(selected) or { skill = 1, max = 75, preview = true }
end

local function Refresh()
	if not pane then return end
	for i = 1, #rows do
		local p = ns.Professions[i]
		if p.key == selected then rows[i]:LockHighlight() else rows[i]:UnlockHighlight() end
		rows[i].label:SetText(p.name .. (ns:HasProfession(p.key) and " |cff60ff60*|r" or ""))
	end
	local p = ns.ProfessionByKey[selected]
	for kind, v in pairs(views) do
		if kind ~= p.kind then v:Hide() end
	end
	local v = views[p.kind]
	if not v then
		v = ns:CreateView(pane, p.kind, VIEW_W, VIEW_H, function() return selected end, State)
		v:ClearAllPoints()
		v:SetPoint("TOPLEFT", LIST_W + 10, 0)
		views[p.kind] = v
	end
	v:Show()
	v:Refresh()
end

local function BuildPane(p)
	pane = p
	rows = {}
	for i = 1, #ns.Professions do
		local prof = ns.Professions[i]
		local b = CreateFrame("Button", nil, p)
		b:SetWidth(LIST_W)
		b:SetHeight(ROW_H - 2)
		b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetWidth(20)
		icon:SetHeight(20)
		icon:SetPoint("LEFT", 2, 0)
		icon:SetTexture(prof.icon)

		b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		b.label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
		b.label:SetText(prof.name)

		b:SetScript("OnClick", function()
			selected = prof.key
			Refresh()
		end)
		rows[i] = b
	end
	local note = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 4, -(#ns.Professions * ROW_H + 6))
	note:SetWidth(LIST_W)
	note:SetJustifyH("LEFT")
	note:SetText("|cff60ff60*|r = you have it")
end

--- Select a profession in the browser (used by tests and other tabs).
function ns:BrowseProfession(key)
	if not ns.ProfessionByKey[key] then return false end
	selected = key
	ns:OpenWindow("all")
	Refresh()
	return true
end

function ns:BrowserSelected()
	return selected
end

--- The view the browser is showing (for tests).
function ns:BrowserView()
	return views[ns.ProfessionByKey[selected].kind]
end

ns:AddTab("all", "All professions", 100, BuildPane, Refresh)

function M:OnLoad()
	ns:Subscribe("ProfessionsChanged", function() if pane and pane:IsVisible() then Refresh() end end)
end
