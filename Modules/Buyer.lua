--[[ FycoProfessions - Modules/Buyer.lua
     Buy a quantity of one item at the Auction House under a price limit,
     cheapest first, without searching and scrolling by hand:

       "60 x Shadow Crystal, at most 80s each" -> Search -> Buy next, Buy next...

     A panel beside the Auction House window takes the item (typed, or
     picked from what your paths still need), the amount and the most you
     will pay per item. Search reads the results page by page; "Buy next"
     buys the cheapest listing under the limit on the page shown, then the
     next, and the status line always says exactly what the next click does.

     ONE PURCHASE PER CLICK. The game normally lets an addon buy only in
     response to a click or key press, so "Buy next" (or its key binding,
     under Key Bindings -> FycoProfessions) buys one listing per press.
     "Buy automatically" tries to go on by itself; if the game blocks it
     (ADDON_ACTION_BLOCKED), it is switched off and the addon says so.

     Never bought: your own listings, bid-only listings, anything over the
     limit, anything you cannot afford.                                   ]]

local ADDON, ns = ...
local M = ns:Module("buyer", 50)
local UI = ns.UI

local PAGE = 50              -- listings per Auction House page
local MAX_PAGES = 20
local WAIT_TIMEOUT = 3       -- seconds to wait for the list after a purchase
local AUTO_EVERY = 0.4

local panel
local job                    -- the current buying job, see ns:BuyStart

----------------------------------------------------------------------
-- prices typed by people: "1g20s", "85s", "85" (silver), "1.5g"
----------------------------------------------------------------------

function ns:ParseMoney(text)
	text = (text or ""):lower():gsub("%s", "")
	if text == "" then return nil end
	if text:match("^%d+%.?%d*$") then return math.floor(tonumber(text) * 100 + 0.5) end
	local total, any = 0, false
	for num, unit in text:gmatch("(%d+%.?%d*)([gsc])") do
		local mult = unit == "g" and 10000 or (unit == "s" and 100 or 1)
		total = total + tonumber(num) * mult
		any = true
	end
	if not any or text:gsub("%d+%.?%d*[gsc]", "") ~= "" then return nil end
	return math.floor(total + 0.5)
end

----------------------------------------------------------------------
-- the job
----------------------------------------------------------------------

local function Status(text)
	if job then job.status = text end
	if panel and panel:IsShown() then panel.status:SetText(text) end
end

local function Me()
	return UnitName("player")
end

--- A listing on the shown page that qualifies: this item, a buyout, not
--- ours, at or under the limit. Returns index, count, buyout, unit.
local function Qualifies(i)
	local name, _, count, _, _, _, _, _, buyout, _, _, owner = GetAuctionItemInfo("list", i)
	if not name or name:lower() ~= job.name:lower() then return nil end
	if not buyout or buyout <= 0 or owner == Me() then return nil end
	count = math.max(1, count or 1)
	local unit = buyout / count
	if unit > job.max then return nil end
	return i, count, buyout, unit
end

--- The cheapest qualifying listing on the page shown.
local function BestOnPage()
	local best
	local shown = GetNumAuctionItems("list") or 0
	for i = 1, shown do
		local idx, count, buyout, unit = Qualifies(i)
		if idx and (not best or unit < best.unit or (unit == best.unit and count < best.count)) then
			best = { index = idx, count = count, buyout = buyout, unit = unit }
		end
	end
	return best
end

local function Query(page)
	job.page = page
	job.state = "searching"
	job.queried = false
	Status("Searching page " .. (page + 1) .. "...")
end

local function Describe()
	if not job then return "" end
	local head = string.format("Bought %d of %d x %s (at most %s each).", job.bought, job.want, job.name,
		UI.Money(job.max))
	if job.bought >= job.want then return head .. "\n|cff60ff60Done.|r" end
	if job.state == "searching" then return head .. "\nSearching..." end
	if job.state == "waiting" then return head .. "\nWaiting for the Auction House..." end
	local best = BestOnPage()
	if best then
		local extra = best.count > job.want - job.bought and
			string.format(" |cffff8040(%d more than you need)|r", best.count - (job.want - job.bought)) or ""
		return head .. string.format("\nNext click: buy %d at %s each = %s%s", best.count, UI.Money(best.unit),
			UI.Money(best.buyout), extra)
	end
	if job.page + 1 < job.pages then return head .. "\nNext click: look at page " .. (job.page + 2) .. "." end
	return head .. "\n|cffff8040No more listings under your limit.|r"
end

--- Start buying: name, quantity, most per item (copper).
function ns:BuyStart(name, want, max)
	if not (AuctionFrame and AuctionFrame:IsShown()) then
		ns:Print("open the Auction House first.")
		return false
	end
	if not name or name == "" or not want or want < 1 or not max or max < 1 then
		ns:Print("the buyer needs an item name, how many, and the most you pay per item.")
		return false
	end
	job = { name = name, want = math.floor(want), max = max, bought = 0, spent = 0, page = 0, pages = 1,
	        passEmpty = true }
	Query(0)
	return true
end

function ns:BuyStop()
	if job then ns:Print(string.format("buyer stopped: bought %d x %s for %s.", job.bought, job.name, UI.Money(job.spent))) end
	job = nil
	Status("")
end

function ns:BuyJob()
	return job
end

--- One step: buy the cheapest qualifying listing, or move to the next page.
--- Must run from a click or key press (see the header).
function ns:BuyNext()
	if not job then
		ns:Print("nothing to buy: start with Search in the buyer panel.")
		return false
	end
	if job.bought >= job.want then
		Status(Describe())
		return false
	end
	if job.state ~= "ready" then return false end
	local best = BestOnPage()
	if best then
		if GetMoney() < best.buyout then
			Status(Describe() .. "\n|cffff6060Not enough gold for it.|r")
			return false
		end
		job.state, job.waitStart = "waiting", GetTime()
		job.passEmpty = false
		job.bought = job.bought + best.count
		job.spent = job.spent + best.buyout
		PlaceAuctionBid("list", best.index, best.buyout)
		Status(Describe())
		return true
	end
	-- nothing left here: the next page, or start over from the first page
	-- (buying shifts listings forward) unless a whole pass found nothing
	if job.page + 1 < job.pages then
		Query(job.page + 1)
	elseif not job.passEmpty then
		job.passEmpty = true
		Query(0)
	else
		Status(Describe())
		return false
	end
	return true
end

-- the global the key binding calls (Bindings.xml)
function FycoProfessions_BuyNext()
	ns:BuyNext()
end

----------------------------------------------------------------------
-- events and the ticker
----------------------------------------------------------------------

local function OnListUpdate()
	if not job then return end
	if job.state == "searching" and job.queried then
		local _, total = GetNumAuctionItems("list")
		job.pages = math.min(MAX_PAGES, math.max(1, math.ceil((total or 0) / PAGE)))
		job.state = "ready"
		Status(Describe())
	elseif job.state == "waiting" then
		-- the purchase went through: read the page again so the next buy
		-- never aims at a listing that is already gone
		if job.bought >= job.want then
			ns:Print(string.format("bought %d x %s for %s.", job.bought, job.name, UI.Money(job.spent)))
		end
		Query(job.page)
	end
end

local lastAuto = 0

local function Tick(now)
	if not job then return end
	if not (AuctionFrame and AuctionFrame:IsShown()) then
		ns:BuyStop()
		return
	end
	if job.state == "searching" and not job.queried and CanSendAuctionQuery() then
		job.queried = true
		QueryAuctionItems(job.name, nil, nil, 0, 0, 0, job.page, 0, 0, false)
	elseif job.state == "waiting" and now - job.waitStart > WAIT_TIMEOUT then
		Query(job.page)              -- no list update came: read the page again
	elseif job.state == "ready" and ns:Get("buyer", "auto") and job.bought < job.want and now - lastAuto >= AUTO_EVERY then
		lastAuto = now
		ns:BuyNext()
	end
end

----------------------------------------------------------------------
-- the panel beside the Auction House
----------------------------------------------------------------------

local function EditBox(parent, name, width, numeric)
	local e = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
	e:SetWidth(width)
	e:SetHeight(20)
	e:SetAutoFocus(false)
	if numeric then e:SetNumeric(true) end
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return e
end

local function Label(parent, text, anchor, x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", anchor or parent, anchor and "BOTTOMLEFT" or "TOPLEFT", x or 0, y or 0)
	fs:SetText(text)
	return fs
end

--- What your paths still need from the Auction House, for the dropdown.
local function NeededItems()
	local out = {}
	for _, e in ipairs(ns:PlayerProfessions()) do
		local path = e.prof.kind == "craft" and ns:GetPath(e.key)
		if path then
			ns:CountShopping(path.shopping)
			for _, s in ipairs(path.shopping) do
				local it = ns.Items[s.id]
				if it and s.missing > 0 and not it.v then
					out[#out + 1] = { value = s.id, text = it.n .. " x" .. s.missing, missing = s.missing }
				end
			end
		end
	end
	if #out == 0 then out[1] = { value = 0, text = "(your paths need nothing)" } end
	return out
end

local function Build()
	panel = CreateFrame("Frame", "FycoProfessionsBuyer", AuctionFrame)
	panel:SetWidth(230)
	panel:SetHeight(300)
	panel:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", -2, -12)
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:EnableMouse(true)

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("FycoProf buyer")

	local need = Label(panel, "What your paths still need:", nil, 12, -30)
	panel.need = UI.Dropdown(panel, "FycoProfessionsBuyerNeed", 170, {
		items = NeededItems,
		get = function() return panel.pick or 0 end,
		set = function(v)
			if v == 0 then return end
			panel.pick = v
			for _, e in ipairs(NeededItems()) do
				if e.value == v then
					panel.item:SetText(ns.Items[v].n)
					panel.qty:SetText(tostring(e.missing))
				end
			end
			local p = ns:AHPrice(v, 1)
			if p and panel.max:GetText() == "" then panel.max:SetText((UI.Money(p * 1.2):gsub(" ", ""))) end
		end,
	})
	panel.need:SetPoint("TOPLEFT", need, "BOTTOMLEFT", -18, -2)

	local l1 = Label(panel, "Item name", nil, 12, -82)
	panel.item = EditBox(panel, "FycoProfessionsBuyerItem", 196)
	panel.item:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 4, -2)
	local l2 = Label(panel, "How many", nil, 12, -122)
	panel.qty = EditBox(panel, "FycoProfessionsBuyerQty", 60, true)
	panel.qty:SetPoint("TOPLEFT", l2, "BOTTOMLEFT", 4, -2)
	local l3 = Label(panel, "Most per item (1g20s, 85s)", nil, 90, -122)
	panel.max = EditBox(panel, "FycoProfessionsBuyerMax", 110)
	panel.max:SetPoint("TOPLEFT", l3, "BOTTOMLEFT", 4, -2)

	local search = CreateFrame("Button", "FycoProfessionsBuyerSearch", panel, "UIPanelButtonTemplate")
	search:SetWidth(100)
	search:SetHeight(22)
	search:SetPoint("TOPLEFT", 12, -166)
	search:SetText("Search")
	search:SetScript("OnClick", function()
		local max = ns:ParseMoney(panel.max:GetText())
		if not max then
			ns:Print("the most per item reads like 1g20s, 85s or 85 (silver).")
			return
		end
		ns:BuyStart(panel.item:GetText(), tonumber(panel.qty:GetText()), max)
	end)

	local stop = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	stop:SetWidth(100)
	stop:SetHeight(22)
	stop:SetPoint("LEFT", search, "RIGHT", 6, 0)
	stop:SetText("Stop")
	stop:SetScript("OnClick", function() ns:BuyStop() end)

	panel.buy = CreateFrame("Button", "FycoProfessionsBuyerBuy", panel, "UIPanelButtonTemplate")
	panel.buy:SetWidth(206)
	panel.buy:SetHeight(30)
	panel.buy:SetPoint("TOPLEFT", 12, -194)
	panel.buy:SetText("Buy next")
	panel.buy:SetScript("OnClick", function() ns:BuyNext() end)

	panel.status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	panel.status:SetPoint("TOPLEFT", 12, -230)
	panel.status:SetWidth(206)
	panel.status:SetJustifyH("LEFT")
	panel.status:SetJustifyV("TOP")
	panel.status:SetText("Pick or type an item, how many, and the most per item, then Search.")

	panel:SetScript("OnShow", function() if job then Status(Describe()) end end)
end

----------------------------------------------------------------------
-- settings and commands
----------------------------------------------------------------------

--- "/fprof buy 60 80s shadow crystal"
function ns:BuyCommand(rest)
	local qty, price, name = (rest or ""):match("^(%d+)%s+(%S+)%s+(.+)$")
	if not qty then
		ns:Print("usage: |cffffff00/fprof buy <how many> <most per item> <item>|r, e.g. "
			.. "|cffffff00/fprof buy 60 80s shadow crystal|r -- or use the panel beside the Auction House.")
		return
	end
	local max = ns:ParseMoney(price)
	if not max then
		ns:Print("the most per item reads like 1g20s, 85s or 85 (silver).")
		return
	end
	-- match the name the Auction House uses, with its capitals
	for _, it in pairs(ns.Items) do
		if it.n:lower() == name:lower() then name = it.n break end
	end
	if ns:BuyStart(name, tonumber(qty), max) and panel then
		panel.item:SetText(name)
		panel.qty:SetText(qty)
		panel.max:SetText(price)
	end
end

ns:RegisterOptions("Buyer", "Auction buyer", 35, function(L, R)
	L:Title("Auction buyer")
	L:Note("A panel beside the Auction House window: an item, how many, and "
	    .. "the most per item. Search, then Buy next buys the cheapest listing "
	    .. "under your limit, one per click.")
	L:Check("Buy automatically", "Experimental: the game may only allow buying from a click",
		function() return ns:Get("buyer", "auto") end,
		function(v) ns:Set("buyer", "auto", v) end)
	L:Note("Automatic buying goes on without clicks. If the game blocks it, "
	    .. "it is switched off and you are told; then use the button or a key.")

	R:Title("Key binding")
	R:Note("Esc -> Key Bindings -> FycoProfessions -> 'Buy next auction'. "
	    .. "Press that key instead of clicking the button.")
	R:Note("Never bought: your own listings, bid-only listings, anything over "
	    .. "your limit or more than you can afford.")
end)

----------------------------------------------------------------------

function M:OnLoad()
	ns:On("AUCTION_HOUSE_SHOW", function()
		if not ns:Enabled("buyer") then return end
		if not panel and AuctionFrame then Build() end
		if panel then panel:Show() end
	end)
	ns:On("AUCTION_HOUSE_CLOSED", function() if job then ns:BuyStop() end end)
	ns:On("AUCTION_ITEM_LIST_UPDATE", OnListUpdate)
	-- the game refusing an automatic purchase: stop trying, say why
	ns:On("ADDON_ACTION_BLOCKED", function(_, addon, fn)
		if addon == ADDON and ns:Get("buyer", "auto") then
			ns:Set("buyer", "auto", false)
			ns:Print("the game only allows buying from a click here (" .. tostring(fn)
				.. " was blocked). Automatic buying is off; use Buy next or its key.")
		end
	end)
	ns:Subscribe("SettingChanged", function(section, key, v)
		if section == "enabled" and key == "buyer" and panel then
			if v then panel:Show() else panel:Hide() end
		end
	end)
	ns:OnTick(Tick)
end
