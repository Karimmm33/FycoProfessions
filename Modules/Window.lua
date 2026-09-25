--[[ FycoProfessions - Modules/Window.lua
     The main window and the minimap button that opens it.

     The window is a shell: it owns the frame, the tab row, a line showing the
     guide settings and a Settings button, and nothing else. Features add
     themselves as tabs with ns:AddTab(key, label, order, build, onShow) at
     file load; content is only built the first time a tab is opened.

     Unlike FycoPvE, tabs can come and go: a character has its own
     professions, so ns:ShowTab(key, shown) hides the tabs of professions it
     does not have, and the row is laid out again without gaps.           ]]

local ADDON, ns = ...
local M = ns:Module("window", 5)

local W, H = 700, 540
local TAB_W, TAB_GAP = 104, 4

local tabs = {}          -- { key, label, order, build, onShow, hidden, pane, button }
local win, current

local MakeButton, Layout

--- Tabs are normally added at file load, before the window exists. One added
--- later gets its button at once, so it is never selectable-but-buttonless.
function ns:AddTab(key, label, order, build, onShow)
	local t = { key = key, label = label, order = order, build = build, onShow = onShow }
	tabs[#tabs + 1] = t
	table.sort(tabs, function(a, b) return a.order < b.order end)
	if win then
		MakeButton(t)
		Layout()
	end
end

local function FindTab(key)
	for i = 1, #tabs do
		if tabs[i].key == key then return tabs[i] end
	end
end

----------------------------------------------------------------------
-- window
----------------------------------------------------------------------

local function SavePosition()
	local point, _, relPoint, x, y = win:GetPoint()
	ns:Set("general", "windowPos", { point, relPoint, x, y })
end

local function Restore()
	win:ClearAllPoints()
	local p = ns:Get("general", "windowPos")
	if p then
		win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
	win:SetScale(ns:Get("general", "windowScale") or 1)
end

local function FirstVisible()
	for i = 1, #tabs do
		if not tabs[i].hidden then return tabs[i].key end
	end
end

local function Select(key)
	local t = key and FindTab(key)
	if not t or t.hidden then key = FirstVisible() end
	for i = 1, #tabs do
		t = tabs[i]
		if t.key == key then
			if not t.pane then
				t.pane = CreateFrame("Frame", nil, win.content)
				t.pane:SetAllPoints(win.content)
				t.build(t.pane)
			end
			t.pane:Show()
			t.button:Disable()
			current = key
			if t.onShow then t.onShow(t.pane) end
		else
			if t.pane then t.pane:Hide() end
			t.button:Enable()
		end
	end
end

--- Place the visible tab buttons left to right, with no gaps for hidden ones.
function Layout()
	local n = 0
	for i = 1, #tabs do
		local t = tabs[i]
		if t.hidden then
			t.button:Hide()
		else
			t.button:ClearAllPoints()
			t.button:SetPoint("TOPLEFT", 18 + n * (TAB_W + TAB_GAP), -50)
			t.button:Show()
			n = n + 1
		end
	end
end

local function UpdateStatus()
	if win then win.status:SetText("|cff808080Guide: " .. ns:GuideText() .. "|r") end
end

function MakeButton(t)
	local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	b:SetWidth(TAB_W)
	b:SetHeight(22)
	b:SetText(t.label)
	b:SetScript("OnClick", function() Select(t.key) end)
	t.button = b
end

local function Build()
	win =CreateFrame("Frame", "FycoProfessionsWindow", UIParent)
	win:SetWidth(W)
	win:SetHeight(H)
	win:SetFrameStrata("HIGH")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	-- Escape closes it, like every Blizzard panel
	tinsert(UISpecialFrames, "FycoProfessionsWindow")

	local title = win:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 22, -16)
	title:SetText("FycoProfessions |cff808080v" .. (GetAddOnMetadata(ADDON, "Version") or "?") .. "|r")

	win.status = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	win.status:SetPoint("TOPLEFT", 22, -34)

	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local settings = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	settings:SetWidth(90)
	settings:SetHeight(22)
	settings:SetPoint("TOPRIGHT", -36, -14)
	settings:SetText("Settings")
	settings:SetScript("OnClick", function() ns:OpenOptions() end)

	for i = 1, #tabs do MakeButton(tabs[i]) end
	Layout()

	local line = win:CreateTexture(nil, "ARTWORK")
	line:SetTexture(1, 1, 1, 0.15)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 16, -78)
	line:SetPoint("TOPRIGHT", -16, -78)

	win.content = CreateFrame("Frame", nil, win)
	win.content:SetPoint("TOPLEFT", 18, -86)
	win.content:SetPoint("BOTTOMRIGHT", -18, 16)

	win:SetScript("OnShow", function()
		UpdateStatus()
		local t = current and FindTab(current)
		if t and t.onShow and t.pane then t.onShow(t.pane) end
	end)

	UpdateStatus()
	Restore()
	win:Hide()
end

--- Show or hide a tab. A hidden tab that was selected hands over to the
--- first visible one.
function ns:ShowTab(key, shown)
	local t = FindTab(key)
	if not t then return end
	t.hidden = not shown
	if not win then return end
	Layout()
	if current == key and t.hidden and win:IsShown() then Select(nil) end
end

--- Open the window, optionally on a given tab.
function ns:OpenWindow(key)
	if not win then Build() end
	win:Show()
	Select(key or current)
end

function ns:ToggleWindow()
	if win and win:IsShown() then win:Hide() else ns:OpenWindow() end
end

function ns:WindowShown(key)
	return win and win:IsShown() and (not key or current == key)
end

--- A tab's content frame, once it has been opened (for tests).
function ns:TabPane(key)
	local t = FindTab(key)
	return t and t.pane
end

function ns:TabHidden(key)
	local t = FindTab(key)
	return t == nil or t.hidden == true
end

function ns:ResetWindow()
	ns:Set("general", "windowPos", nil)
	if win then Restore() end
end

----------------------------------------------------------------------
-- minimap button
----------------------------------------------------------------------

local mini

local function PlaceMini()
	local a = math.rad(ns:Get("general", "minimapAngle") or 200)
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
end

local function BuildMini()
	mini = CreateFrame("Button", "FycoProfessionsMinimapButton", Minimap)
	mini:SetWidth(31)
	mini:SetHeight(31)
	mini:SetFrameStrata("MEDIUM")
	mini:SetFrameLevel(8)
	mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = mini:CreateTexture(nil, "BACKGROUND")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetPoint("TOPLEFT", 7, -5)

	local border = mini:CreateTexture(nil, "OVERLAY")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mini:RegisterForDrag("LeftButton")
	mini:SetScript("OnClick", function(_, button)
		if button == "RightButton" then ns:OpenOptions() else ns:ToggleWindow() end
	end)

	-- dragging walks the button round the minimap's edge
	mini:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local s = Minimap:GetEffectiveScale()
			local angle = math.deg(math.atan2(py / s - my, px / s - mx))
			FycoProfessionsDB.general = FycoProfessionsDB.general or {}
			FycoProfessionsDB.general.minimapAngle = angle
			PlaceMini()
		end)
	end)
	mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	mini:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("FycoProfessions")
		GameTooltip:AddLine("Guide: " .. ns:GuideText(), 1, 1, 1)
		GameTooltip:AddLine("|cffffff00Left-click|r open    |cffffff00Right-click|r settings", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("|cffffff00Drag|r to move", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
	PlaceMini()
end

local function UpdateMini()
	if ns:Get("general", "minimap") then mini:Show() else mini:Hide() end
end

function M:OnLoad()
	BuildMini()
	UpdateMini()
	ns:Subscribe("SettingChanged", function(section, key)
		if section == "guide" or (section == "char" and key == "faction") then UpdateStatus() end
		if section ~= "general" then return end
		if key == "minimap" then UpdateMini() end
		if key == "windowScale" and win then win:SetScale(ns:Get("general", "windowScale")) end
	end)
end
