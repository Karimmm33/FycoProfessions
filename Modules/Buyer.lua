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
-- prices typed by people: "1g20s", "85s", "65" (gold), "1.5g"
----------------------------------------------------------------------

function ns:ParseMoney(text)
	text = (text or ""):lower():gsub("%s", "")
	if text == "" then return nil end
	-- a bare number is GOLD: at the Auction House "65" means 65g (it was
	-- read as silver once, and 65s bought nothing where 64g was listed)
	if text:match("^%d+%.?%d*$") then return math.floor(tonumber(text) * 10000 + 0.5) end
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

--[[ HOW A JOB RUNS
     1. Search reads EVERY result page (up to MAX_PAGES) and collects each
        listing under the limit: page, count, buyout, seller. The first
        version looked at one page at a time and reported only that page,
        so a cheap listing elsewhere looked like "over your limit".
     2. Buy next buys the cheapest collected listing. Its page is opened
        first if another is shown; the listing is found again on it by
        count, buyout and seller (positions shift as things sell).
     3. After every purchase the search runs again: listings move up
        between pages as others sell, and the next buy must not aim at
        one that is gone.                                                 ]]

local function Load(page)
	job.page = page
	job.state = "loading"
	job.queried = false
end

local function Rescan()
	job.found = {}
	job.seen = { listed = 0, mine = 0, bidOnly = 0 }
	job.scanning = true
	Load(0)
end

--- Read the page shown: every listing of this item, into job.found (under
--- the limit, not ours, with a buyout) and job.seen (what was there).
local function ReadPage()
	local s = job.seen
	for i = 1, (GetNumAuctionItems("list") or 0) do
		local name, _, count, _, _, _, minBid, _, buyout, bidAmount, _, owner = GetAuctionItemInfo("list", i)
		if name and name:lower() == job.name:lower() then
			count = math.max(1, count or 1)
			s.listed = s.listed + 1
			-- the bid shown in the Auction House's price column, per item
			local bid = (((bidAmount or 0) > 0) and bidAmount or (minBid or 0)) / count
			if bid > 0 and (not s.bid or bid < s.bid) then s.bid = bid end
			if owner == Me() then
				s.mine = s.mine + 1
			elseif not buyout or buyout <= 0 then
				s.bidOnly = s.bidOnly + 1
			else
				local unit = buyout / count
				if not s.cheapest or unit < s.cheapest then s.cheapest = unit end
				if unit <= job.max then
					table.insert(job.found, { page = job.page, name = name, count = count, buyout = buyout,
					                          unit = unit, owner = owner })
				end
			end
		end
	end
end

local Describe

--- A requested page has arrived (or only empty answers came in time).
local function PageArrived()
	local shown, total = GetNumAuctionItems("list")
	if job.scanning then
		if job.page == 0 then
			job.pages = math.min(MAX_PAGES, math.max(1, math.ceil((total or shown or 0) / PAGE)))
		end
		ReadPage()
		if job.page + 1 < job.pages then
			Load(job.page + 1)
			Status(Describe())
			return
		end
		job.scanning = false
		table.sort(job.found, function(a, b)
			if a.unit ~= b.unit then return a.unit < b.unit end
			return a.count < b.count
		end)
	end
	-- open the page that holds the next listing to buy
	local t = job.found[1]
	if t and t.page ~= job.page and job.bought < job.want then
		Load(t.page)
		Status(Describe())
		return
	end
	job.state = "ready"
	Status(Describe())
end

--- The index of the next listing to buy on the page shown, or nil.
local function FindTarget()
	local t = job.found[1]
	if not t then return nil end
	for i = 1, (GetNumAuctionItems("list") or 0) do
		local name, _, count, _, _, _, _, _, buyout, _, _, owner = GetAuctionItemInfo("list", i)
		if name == t.name and math.max(1, count or 1) == t.count and buyout == t.buyout and owner == t.owner then
			return i
		end
	end
end

function Describe()
	if not job then return "" end
	local head = string.format("Bought %d of %d x %s (at most %s each).", job.bought, job.want, job.name,
		UI.Money(job.max))
	if job.bought >= job.want then return head .. "\n|cff60ff60Done.|r" end
	if job.state == "waiting" then return head .. "\nWaiting for the Auction House..." end
	if job.state == "loading" then
		if job.scanning then
			return head .. string.format("\nSearching page %d%s...", job.page + 1,
				job.pages and job.page > 0 and (" of " .. job.pages) or "")
		end
		return head .. "\nOpening page " .. (job.page + 1) .. "..."
	end
	local t = job.found[1]
	if t then
		local need = job.want - job.bought
		local extra = t.count > need and string.format(" |cffff8040(%d more than you need)|r", t.count - need) or ""
		return head .. string.format("\nFound %d under your limit on %d page%s.\nNext click: buy %d at %s each = %s%s",
			#job.found, job.pages, job.pages == 1 and "" or "s", t.count, UI.Money(t.unit), UI.Money(t.buyout), extra)
	end
	-- nothing to buy: say WHY, from everything the search saw
	local s = job.seen
	if s.listed == 0 then
		return head .. "\n|cffff8040The Auction House has no " .. job.name
			.. " right now.|r Check the name: it must be the item's full name."
	end
	local why = string.format("\n|cffff8040%d %s listed", s.listed, job.name)
	if s.cheapest then why = why .. ", cheapest buyout " .. UI.Money(s.cheapest) .. " each: over your limit" end
	if s.mine > 0 then why = why .. ", " .. s.mine .. " yours" end
	if s.bidOnly > 0 then why = why .. ", " .. s.bidOnly .. " without buyout" end
	why = why .. ".|r"
	if s.bid and s.bid <= job.max then
		why = why .. "\nBids start at " .. UI.Money(s.bid) .. " (the big price in the Auction House list), "
			.. "but the buyer only buys out."
	end
	return head .. why
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
	job = { name = name, want = math.floor(want), max = max, bought = 0, spent = 0, page = 0, pages = 1 }
	Rescan()
	Status(Describe())
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

--- Buy the cheapest listing under the limit. Must run from a click or key
--- press (see the header).
function ns:BuyNext()
	if not job then
		ns:Print("nothing to buy: start with Search in the buyer panel.")
		return false
	end
	if job.bought >= job.want or job.state ~= "ready" then
		Status(Describe())
		return false
	end
	local t = job.found[1]
	if not t then
		Status(Describe())
		return false
	end
	local index = FindTarget()
	if not index then
		Rescan()                     -- it sold or moved: look again
		Status(Describe())
		return true
	end
	if GetMoney() < t.buyout then
		Status(Describe() .. "\n|cffff6060Not enough gold for it.|r")
		return false
	end
	table.remove(job.found, 1)
	job.state, job.waitStart = "waiting", GetTime()
	job.bought = job.bought + t.count
	job.spent = job.spent + t.buyout
	PlaceAuctionBid("list", index, t.buyout)
	Status(Describe())
	return true
end

-- the global the key binding calls (Bindings.xml)
function FycoProfessions_BuyNext()
	ns:BuyNext()
end

----------------------------------------------------------------------
-- events and the ticker
----------------------------------------------------------------------

local EMPTY_GRACE = 3        -- seconds an empty answer is distrusted after a search

--- After a purchase: done, or search again for the next one.
local function AfterPurchase()
	if job.bought >= job.want then
		ns:Print(string.format("bought %d x %s for %s.", job.bought, job.name, UI.Money(job.spent)))
		job.state = "ready"
		Status(Describe())
	else
		Rescan()
		Status(Describe())
	end
end

local function OnListUpdate()
	if not job then return end
	if job.state == "loading" and job.queried then
		-- an update can arrive with the list still empty before the results
		-- do; an empty answer is only believed after EMPTY_GRACE seconds
		local shown = GetNumAuctionItems("list")
		if (shown or 0) == 0 and GetTime() - job.queriedAt < EMPTY_GRACE then return end
		PageArrived()
	elseif job.state == "waiting" then
		AfterPurchase()
	end
end

local lastAuto = 0

local function Tick(now)
	if not job then return end
	if not (AuctionFrame and AuctionFrame:IsShown()) then
		ns:BuyStop()
		return
	end
	if job.state == "loading" and not job.queried and CanSendAuctionQuery() then
		job.queried, job.queriedAt = true, now
		ns:AuctionSearch(job.name, job.page)
	elseif job.state == "loading" and job.queried and now - job.queriedAt > EMPTY_GRACE then
		PageArrived()                -- only empty answers came: the page really is empty
	elseif job.state == "waiting" and now - job.waitStart > WAIT_TIMEOUT then
		AfterPurchase()              -- no list update came: carry on
	elseif job.state == "ready" and ns:Get("buyer", "auto") and job.bought < job.want and job.found[1]
		and now - lastAuto >= AUTO_EVERY then
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
	panel:SetHeight(330)
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
	local l3 = Label(panel, "Most each (65, 1g20s, 85s)", nil, 90, -122)
	panel.max = EditBox(panel, "FycoProfessionsBuyerMax", 110)
	panel.max:SetPoint("TOPLEFT", l3, "BOTTOMLEFT", 4, -2)
	-- how the price is being read, live, so "65" vs "65s" is never a surprise
	panel.maxRead = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	panel.maxRead:SetPoint("TOPLEFT", panel.max, "BOTTOMLEFT", -4, -1)
	panel.max:SetScript("OnTextChanged", function(self)
		local v = ns:ParseMoney(self:GetText())
		if self:GetText() == "" then
			panel.maxRead:SetText("")
		elseif v then
			panel.maxRead:SetText("|cff60ff60= " .. UI.Money(v) .. " each|r")
		else
			panel.maxRead:SetText("|cffff6060not a price|r")
		end
	end)

	local search = CreateFrame("Button", "FycoProfessionsBuyerSearch", panel, "UIPanelButtonTemplate")
	search:SetWidth(100)
	search:SetHeight(22)
	search:SetPoint("TOPLEFT", 12, -176)
	search:SetText("Search")
	search:SetScript("OnClick", function()
		-- every problem goes on the panel itself: a message only in chat
		-- made a typed search look like a button that did nothing
		local name = (panel.item:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then
			Status("|cffff6060Type an item name first|r (or shift-click an item link into the box).")
			return
		end
		local max = ns:ParseMoney(panel.max:GetText())
		if not max then
			Status("|cffff6060Most per item is missing or unreadable.|r Write it like 65 (gold), 1g20s or 85s.")
			return
		end
		local qty = tonumber(panel.qty:GetText()) or 1
		for _, it in pairs(ns.Items) do            -- the Auction House's capitals, when we know the item
			if it.n:lower() == name:lower() then name = it.n break end
		end
		panel.item:SetText(name)
		panel.qty:SetText(tostring(qty))
		if ns:BuyStart(name, qty, max) then Status(Describe()) end
	end)

	-- the item selected in the normal Auction House list
	local sel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	sel:SetWidth(70)
	sel:SetHeight(16)
	sel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -76)
	sel:SetText("Selected")
	sel:SetScript("OnClick", function()
		local i = GetSelectedAuctionItem and GetSelectedAuctionItem("list")
		local name = i and i > 0 and GetAuctionItemInfo("list", i)
		if name then
			panel.item:SetText(name)
		else
			Status("Click an item in the Auction House list first, then Selected.")
		end
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
	panel.buy:SetPoint("TOPLEFT", 12, -204)
	panel.buy:SetText("Buy next")
	panel.buy:SetScript("OnClick", function() ns:BuyNext() end)

	panel.status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	panel.status:SetPoint("TOPLEFT", 12, -240)
	panel.status:SetWidth(206)
	panel.status:SetJustifyH("LEFT")
	panel.status:SetJustifyV("TOP")
	panel.status:SetText("Pick or type an item, how many, and the most per item, then Search.")

	panel:SetScript("OnShow", function() if job then Status(Describe()) end end)

	-- shift-clicking an item while the name box has focus puts its name there
	if hooksecurefunc and ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", function(link)
			if panel.item:HasFocus() and link then
				local name = link:match("%[(.-)%]")
				if name then panel.item:SetText(name) end
			end
		end)
	end
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
		ns:Print("the most per item reads like 65 (gold), 1g20s or 85s.")
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
