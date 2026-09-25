--[[ FycoProfessions - Modules/Tracker.lua
     A small movable frame showing the current guide step and what is still
     needed for it. Guide modules push their lines with
     ns:SetTrackerLines(title, lines); the tracker only draws them.

     Settings: shown, locked (no dragging), scale, and its saved position. ]]

local _, ns = ...
local M = ns:Module("tracker", 30)

local WIDTH, PAD, LINE_H, MAX_LINES = 240, 8, 13, 12

local f, titleFS
local lineFS = {}
local content = { title = "FycoProfessions", lines = { "|cff808080No step to track yet.|r" } }

local function SavePosition()
	local point, _, relPoint, x, y = f:GetPoint()
	ns:Set("tracker", "pos", { point, relPoint, x, y })
end

local function Place()
	f:ClearAllPoints()
	local p = ns:Get("tracker", "pos")
	if p then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
	end
	f:SetScale(ns:Get("tracker", "scale") or 1)
end

local function Render()
	if not f then return end
	titleFS:SetText(content.title)
	local n = math.min(#content.lines, MAX_LINES)
	for i = 1, MAX_LINES do
		if i <= n then
			lineFS[i]:SetText(content.lines[i])
			lineFS[i]:Show()
		else
			lineFS[i]:Hide()
		end
	end
	f:SetHeight(PAD * 2 + 16 + n * LINE_H)
end

local function UpdateShown()
	if not f then return end
	if ns:Enabled("tracker") and ns:Get("tracker", "shown") then f:Show() else f:Hide() end
end

local function Build()
	f = CreateFrame("Frame", "FycoProfessionsTracker", UIParent)
	f:SetWidth(WIDTH)
	f:SetHeight(60)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0, 0, 0, 0.7)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		if not ns:Get("tracker", "locked") then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then ns:OpenWindow() end
	end)

	titleFS = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	titleFS:SetPoint("TOPLEFT", PAD, -PAD)
	titleFS:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	titleFS:SetJustifyH("LEFT")

	for i = 1, MAX_LINES do
		local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", PAD, -(PAD + 16 + (i - 1) * LINE_H))
		fs:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
		fs:SetJustifyH("LEFT")
		lineFS[i] = fs
	end

	Place()
	Render()
	UpdateShown()
end

--- What the tracker shows. `lines` is a list of already-coloured strings.
function ns:SetTrackerLines(title, lines)
	content.title = title or "FycoProfessions"
	content.lines = lines or {}
	Render()
end

function ns:TrackerLines()
	return content.title, content.lines
end

function ns:TrackerShown()
	return f and f:IsShown() or false
end

function ns:ResetTracker()
	ns:Set("tracker", "pos", nil)
	if f then Place() end
end

local Y = "|cffffff00"

function ns:TrackerCommand(sub)
	if sub == "show" then
		ns:Set("tracker", "shown", true)
	elseif sub == "hide" then
		ns:Set("tracker", "shown", false)
	elseif sub == "lock" then
		ns:Set("tracker", "locked", true)
	elseif sub == "unlock" then
		ns:Set("tracker", "locked", false)
	elseif sub == "reset" then
		ns:ResetTracker()
	elseif sub == "" then
		ns:Set("tracker", "shown", not ns:Get("tracker", "shown"))
	else
		ns:Print("usage: " .. Y .. "/fprof tracker show, hide, lock, unlock|r or " .. Y .. "reset|r")
		return
	end
	ns:Print("tracker " .. (ns:Get("tracker", "shown") and "shown" or "hidden")
		.. (ns:Get("tracker", "locked") and ", locked" or ", movable"))
end

ns:RegisterOptions("Tracker", "Tracker", 20, function(L, R)
	L:Title("Step tracker")
	L:Note("A small frame with the current guide step and the materials it "
	    .. "still needs. Drag it to move it; right-click it to open the window.")
	L:Check("Show the tracker", nil,
		function() return ns:Get("tracker", "shown") end,
		function(v) ns:Set("tracker", "shown", v) end)
	L:Check("Lock it in place", "Stops it being dragged by accident",
		function() return ns:Get("tracker", "locked") end,
		function(v) ns:Set("tracker", "locked", v) end)
	L:Slider("Tracker scale", 0.6, 1.6, 0.05,
		function() return ns:Get("tracker", "scale") end,
		function(v) ns:Set("tracker", "scale", v) end)
	L:Button("Reset position", function() ns:ResetTracker() end)

	R:Title("Commands")
	R:Note("/fprof tracker show, hide, lock, unlock or reset. Plain "
	    .. "/fprof tracker toggles it.")
end)

function M:OnLoad()
	Build()
	ns:Subscribe("SettingChanged", function(section, key)
		if section == "enabled" and key == "tracker" then UpdateShown() end
		if section ~= "tracker" then return end
		if key == "shown" then UpdateShown() end
		if key == "scale" and f then f:SetScale(ns:Get("tracker", "scale")) end
	end)
end
