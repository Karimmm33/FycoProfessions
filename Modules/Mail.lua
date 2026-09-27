--[[ FycoProfessions - Modules/Mail.lua
     "Take all" for the mailbox: every item and all the gold from every mail,
     one at a time, instead of clicking each.

       - A button on the inbox, /fprof mail, or (if you switch it on)
         automatically when the mailbox opens.
       - One take every few tenths of a second, so the server keeps up.
       - Cash-on-delivery mail is never touched (taking it would pay).
       - Stops when your bags are full (gold still comes), and when you
         close the mailbox.
       - The inbox shows at most 50 mails; when more wait on the server,
         it says so -- the server refreshes the list about once a minute.

     Taking mail is not restricted like buying: it runs by itself.        ]]

local _, ns = ...
local M = ns:Module("mail", 55)
local UI = ns.UI

local EVERY = 0.35           -- seconds between takes
local ATTACHMENTS = 12       -- ATTACHMENTS_MAX_RECEIVE in 3.3.5a

local run                    -- { items, money, mails, last } while taking
local button

local function FreeSlots()
	local free = 0
	for bag = 0, 4 do
		free = free + (GetContainerNumFreeSlots(bag) or 0)
	end
	return free
end

--- The next thing to take: index, "money" or attachment number -- or nil.
--- Scans from the last mail so taking one never shifts the ones still to go.
local function NextTake(bagsFull)
	for i = (GetInboxNumItems() or 0), 1, -1 do
		local _, _, _, _, money, cod, _, hasItem = GetInboxHeaderInfo(i)
		if (cod or 0) == 0 then
			if (money or 0) > 0 then return i, "money", money end
			if hasItem and not bagsFull then
				for a = 1, ATTACHMENTS do
					if GetInboxItem(i, a) then return i, a end
				end
			end
		end
	end
end

local function Finish(reason)
	if not run then return end
	local parts = {}
	if run.items > 0 then parts[#parts + 1] = run.items .. " items" end
	if run.money > 0 then parts[#parts + 1] = UI.Money(run.money) end
	ns:Print("mail: took " .. (#parts > 0 and table.concat(parts, " and ") or "nothing")
		.. (reason and (" - " .. reason) or "") .. ".")
	local shown, total = GetInboxNumItems()
	if total and shown and total > shown then
		ns:Print("mail: " .. (total - shown) .. " more mails wait on the server; they arrive in the inbox "
			.. "within about a minute -- then take all again.")
	end
	run = nil
	if button then button:Enable() end
end

function ns:MailTakeAll()
	if not ns.mailOpen then          -- set by MAIL_SHOW, cleared by MAIL_CLOSED
		ns:Print("open your mailbox first.")
		return false
	end
	if run then return false end
	run = { items = 0, money = 0, last = 0 }
	if button then button:Disable() end
	return true
end

function ns:MailRunning()
	return run ~= nil
end

local CONFIRM_TIMEOUT = 2    -- seconds to wait for the inbox to confirm a take

local function Tick(now)
	if not run or now - run.last < EVERY then return end
	-- wait for the inbox to confirm the last take (MAIL_INBOX_UPDATE); until
	-- then the mail still shows its gold or item and would be taken twice
	if run.waiting and now - run.last < CONFIRM_TIMEOUT then return end
	run.waiting = true
	run.last = now
	local full = FreeSlots() == 0
	local i, what, money = NextTake(full)
	if not i then
		local left = NextTake(false)
		Finish(full and left and "your bags are full" or nil)
		return
	end
	if what == "money" then
		run.money = run.money + money
		TakeInboxMoney(i)
	else
		run.items = run.items + 1
		TakeInboxItem(i, what)
	end
end

local function AddButton()
	if button or not InboxFrame then return end
	button = CreateFrame("Button", "FycoProfessionsMailTakeAll", InboxFrame, "UIPanelButtonTemplate")
	button:SetWidth(90)
	button:SetHeight(22)
	button:SetPoint("TOPRIGHT", InboxFrame, "TOPRIGHT", -60, -40)
	button:SetText("Take all")
	button:SetScript("OnClick", function() ns:MailTakeAll() end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("FycoProfessions: take all")
		GameTooltip:AddLine("Every item and all the gold, one at a time. Cash-on-delivery "
			.. "mail is left alone.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

ns:RegisterOptions("Mail", "Mail", 40, function(L, R)
	L:Title("Mail")
	L:Note("A Take all button on your inbox: every item and all the gold from "
	    .. "every mail. Cash-on-delivery mail is never touched.")
	L:Check("Take all when the mailbox opens", nil,
		function() return ns:Get("mail", "auto") end,
		function(v) ns:Set("mail", "auto", v) end)
	R:Title("Command")
	R:Note("/fprof mail takes everything, with the mailbox open.")
end)

function M:OnLoad()
	ns:On("MAIL_SHOW", function()
		ns.mailOpen = true
		if not ns:Enabled("mail") then return end
		AddButton()
		if button then button:Show() end
		if ns:Get("mail", "auto") then ns:MailTakeAll() end
	end)
	ns:On("MAIL_INBOX_UPDATE", function() if run then run.waiting = false end end)
	ns:On("MAIL_CLOSED", function()
		ns.mailOpen = false
		if run then Finish("mailbox closed") end
	end)
	ns:Subscribe("SettingChanged", function(section, key, v)
		if section == "enabled" and key == "mail" and button then
			if v then button:Show() else button:Hide() end
		end
	end)
	ns:OnTick(Tick)
end
