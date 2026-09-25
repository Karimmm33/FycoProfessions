--[[ FycoProfessions - Modules/Browser.lua
     The "All professions" tab: every profession in the game, whether this
     character has it or not, so you can look one up before learning it.

     Left, the list. Right, what is known about the selected one. Later
     phases fill the right side with the same guide a profession tab shows.  ]]

local _, ns = ...
local M = ns:Module("browser", 20)

local ROW_H = 26
local LIST_W = 200

local KIND_TEXT = {
	craft = "Crafting - a step-by-step recipe path",
	gather = "Gathering - the best zones and nodes for your skill",
	fish = "Fishing - zones by required skill",
}

local pane, rows, detail
local selected = "jewelcrafting"

local function RankLines()
	local lines = { "|cffffd200Trainer ranks|r |cff808080(stock 3.3.5 levels; this realm may differ)|r" }
	local lo = 1
	for i = 1, #ns.Ranks do
		local r = ns.Ranks[i]
		lines[#lines + 1] = string.format("  %s: %d to %d, needs level %d", r.name, lo, r.cap, r.level)
		lo = r.cap
	end
	return lines
end

local function Refresh()
	if not pane then return end
	for i = 1, #rows do
		local p = ns.Professions[i]
		if p.key == selected then rows[i]:LockHighlight() else rows[i]:UnlockHighlight() end
	end

	local p = ns.ProfessionByKey[selected]
	local lines = {
		"|cffffffff" .. p.name .. "|r" .. (p.secondary and "  |cff808080(secondary)|r" or ""),
		KIND_TEXT[p.kind],
		"",
	}
	local ranks = RankLines()
	for i = 1, #ranks do lines[#lines + 1] = ranks[i] end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "|cff808080The step-by-step guide for this profession is not built yet.|r"
	detail:SetText(table.concat(lines, "\n"))
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

		local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		fs:SetPoint("LEFT", icon, "RIGHT", 6, 0)
		fs:SetText(prof.name)

		b:SetScript("OnClick", function()
			selected = prof.key
			Refresh()
		end)
		rows[i] = b
	end

	detail = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	detail:SetPoint("TOPLEFT", LIST_W + 20, 0)
	detail:SetPoint("RIGHT", p, "RIGHT", 0, 0)
	detail:SetJustifyH("LEFT")
	detail:SetJustifyV("TOP")
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

ns:AddTab("all", "All professions", 100, BuildPane, Refresh)

function M:OnLoad() end
