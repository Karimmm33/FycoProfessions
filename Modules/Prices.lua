--[[ FycoProfessions - Modules/Prices.lua
     Auction House prices, from your own scans. Nothing is guessed from the
     internet: a price is what the lowest buyout was when you last looked.

       - Full scan: one getAll query (the client allows it once every 15
         minutes), read in chunks from the ticker so the game does not freeze.
       - Shopping scan: one normal search per material on your paths, one at
         a time as the Auction House allows.

     Prices are kept per realm and faction (each side has its own Auction
     House) and only for items this addon knows. A button on the Auction
     House window, the settings page and /fprof scan all start a scan.     ]]

local _, ns = ...
local M = ns:Module("prices", 14)

local CHUNK = 400            -- auctions read per tick of a full scan
local STALE = 7 * 24 * 3600  -- prices older than a week are not used

local scan                   -- { mode = "all" | "list", ... } while one runs

local function Store()
	FycoProfessionsDB.prices = FycoProfessionsDB.prices or {}
	local key = (GetRealmName() or "?") .. "-" .. ns:Faction()
	FycoProfessionsDB.prices[key] = FycoProfessionsDB.prices[key] or {}
	return FycoProfessionsDB.prices[key]
end

local function Age(t)
	local d = time() - t
	if d < 3600 then return math.max(1, math.floor(d / 60)) .. " min ago" end
	if d < 86400 then return math.floor(d / 3600) .. " h ago" end
	return math.floor(d / 86400) .. " days ago"
end

-- How many of an item a path step typically buys. Prices are what buying
-- this many costs, not the single cheapest listing: in game, one cheap gem
-- listed next to twenty dear ones made the path plan on the cheap price,
-- pick the wrong recipe, and cost far more than it said.
ns.PRICE_QTY = 20
local SCARCE = 1.25          -- more than is listed: the rest at 25% over the dearest
local LADDER_STEPS = 12      -- price levels kept per item

--- Average unit buyout for buying `qty` (default ns.PRICE_QTY) from what
--- your last scan saw; then how old that is, how many were listed, and the
--- single cheapest unit price. nil when never scanned or older than a week.
function ns:AHPrice(id, qty)
	if not FycoProfessionsDB then return nil end
	local p = Store()[id]
	if not p or time() - p[2] > STALE then return nil end
	local ladder = p[3]
	if not ladder then return p[1], Age(p[2]), nil, p[1] end   -- a scan from before 0.11
	qty = math.max(1, qty or ns.PRICE_QTY)
	local left, spent, supply, last = qty, 0, 0, p[1]
	for i = 1, #ladder, 2 do
		local unit, n = ladder[i], ladder[i + 1]
		supply = supply + n
		last = unit
		if left > 0 then
			local take = math.min(left, n)
			spent = spent + take * unit
			left = left - take
		end
	end
	if left > 0 then spent = spent + left * last * SCARCE end
	return spent / qty, Age(p[2]), supply, p[1]
end

--- "/fprof price <item>": exactly what the last scan saw for one item.
function ns:PriceReport(text)
	text = (text or ""):lower()
	if text == "" then
		ns:Print("usage: |cffffff00/fprof price <item name>|r")
		return
	end
	local id, prefix
	for iid, it in pairs(ns.Items) do
		local n = it.n:lower()
		if n == text then id = iid break end
		if not prefix and n:find(text, 1, true) == 1 then prefix = iid end
	end
	id = id or prefix
	if not id then
		ns:Print("no material called " .. text .. " in FycoProfessions' data.")
		return
	end
	local name = ns.Items[id].n
	local p = FycoProfessionsDB and Store()[id]
	if not p then
		ns:Print(name .. ": not seen on the Auction House in your scans.")
		return
	end
	local avg, age, supply = ns:AHPrice(id)
	if not avg then
		ns:Print(name .. ": the last price is over a week old; scan again.")
		return
	end
	ns:Print(string.format("%s, scanned %s:", name, age))
	local ladder = p[3] or { p[1], 0 }
	local parts = {}
	for i = 1, #ladder, 2 do
		parts[#parts + 1] = (ladder[i + 1] > 0 and (ladder[i + 1] .. " at ") or "") .. ns.UI.Money(ladder[i])
	end
	ns:Print("  cheapest listings: " .. table.concat(parts, ", "))
	ns:Print(string.format("  buying %d costs about %s each%s", ns.PRICE_QTY, ns.UI.Money(avg),
		(supply and supply < ns.PRICE_QTY) and (" (only " .. supply .. " listed)") or ""))
end

function ns:PriceCount()
	local n, newest = 0, nil
	for _, p in pairs(Store()) do
		n = n + 1
		if not newest or p[2] > newest then newest = p[2] end
	end
	return n, newest and Age(newest)
end

function ns:ForgetPrices()
	local key = (GetRealmName() or "?") .. "-" .. ns:Faction()
	FycoProfessionsDB.prices[key] = nil
	ns:Fire("PricesChanged")
end

----------------------------------------------------------------------
-- reading results
----------------------------------------------------------------------

--- One listing: its unit buyout and how many it holds. Blizzard's own
--- AuctionUI in this client reads the same positions: count 3rd, buyout
--- 9th (the 7th is the minimum bid, never used here). Bid-only auctions
--- have no buyout and are skipped.
local function Record(found, i)
	local link = GetAuctionItemLink("list", i)
	local id = link and tonumber(link:match("item:(%d+)"))
	if not id or not ns.Items[id] then return end
	local _, _, count, _, _, _, _, _, buyout = GetAuctionItemInfo("list", i)
	if not buyout or buyout <= 0 then return end
	count = math.max(1, count or 1)
	local list = found[id] or {}
	found[id] = list
	list[#list + 1] = { buyout / count, count }
end

--- Listings -> { unit, qty, unit, qty, ... }, cheapest first, equal prices
--- merged, at most LADDER_STEPS levels (the dear end is not needed).
local function Ladder(listings)
	table.sort(listings, function(a, b) return a[1] < b[1] end)
	local out = {}
	for _, l in ipairs(listings) do
		local unit = math.floor(l[1] + 0.5)
		local n = #out
		if n >= 2 and out[n - 1] == unit then
			out[n] = out[n] + l[2]
		elseif n < LADDER_STEPS * 2 then
			out[n + 1], out[n + 2] = unit, l[2]
		end
	end
	return out
end

local function Finish()
	local store, now, n = Store(), time(), 0
	for id, listings in pairs(scan.found) do
		local ladder = Ladder(listings)
		store[id] = { ladder[1], now, ladder }
		n = n + 1
	end
	-- a full scan also knows what is NOT listed any more
	if scan.mode == "all" and scan.complete then
		for id in pairs(store) do
			if not scan.found[id] then store[id] = nil end
		end
	end
	ns:Print("Auction House scan done: " .. n .. " prices saved.")
	scan = nil
	ns:Fire("PricesChanged")
end

----------------------------------------------------------------------
-- starting scans
----------------------------------------------------------------------

--- A name search, page `page`, with no other filter -- passed exactly as
--- Blizzard's own AuctionUI in this client passes "no filter": nil. The
--- first version passed 0s: 0 is true in Lua, so "usable items only" was
--- on and category 0 matched nothing, and every search came back empty.
function ns:AuctionSearch(name, page)
	QueryAuctionItems(name, nil, nil, nil, nil, nil, page or 0, nil, nil, false)
end

local function AHOpen()
	return AuctionFrame ~= nil and AuctionFrame:IsShown() and true or false
end

function ns:AuctionOpen()
	return AHOpen()
end

function ns:ScanAll()
	if not AHOpen() then
		ns:Print("open the Auction House first.")
		return false
	end
	if scan then
		ns:Print("a scan is already running.")
		return false
	end
	local _, canAll = CanSendAuctionQuery()
	if not canAll then
		ns:Print("a full scan is allowed once every 15 minutes, and not yet.")
		return false
	end
	scan = { mode = "all", found = {}, waiting = true }
	QueryAuctionItems("", nil, nil, nil, nil, nil, 0, nil, nil, true)
	ns:Print("full Auction House scan started...")
	return true
end

--- Every material on every path of every profession you have.
local function ShoppingNames()
	local names, seen = {}, {}
	local profs = ns:PlayerProfessions()
	for i = 1, #profs do
		local path = profs[i].prof.kind == "craft" and ns:GetPath(profs[i].key)
		for j = 1, #(path and path.shopping or {}) do
			local id = path.shopping[j].id
			local it = ns.Items[id]
			if it and not it.v and not seen[id] then
				seen[id] = true
				names[#names + 1] = { id = id, name = it.n }
			end
		end
	end
	return names
end

function ns:ScanShopping()
	if not AHOpen() then
		ns:Print("open the Auction House first.")
		return false
	end
	if scan then
		ns:Print("a scan is already running.")
		return false
	end
	local queue = ShoppingNames()
	if #queue == 0 then
		ns:Print("nothing to scan: your paths need only vendor materials.")
		return false
	end
	scan = { mode = "list", found = {}, queue = queue, pos = 0, page = nil }
	ns:Print("scanning " .. #queue .. " materials...")
	return true
end

function ns:ScanRunning()
	return scan ~= nil, scan and scan.mode
end

----------------------------------------------------------------------

local function OnListUpdate()
	if not scan then return end
	if scan.mode == "all" and scan.waiting then
		scan.waiting = false
		scan.total = GetNumAuctionItems("list") or 0
		scan.i = 0
	elseif scan.mode == "list" and scan.pending then
		scan.pending = false
		local shown, total = GetNumAuctionItems("list")
		for i = 1, (shown or 0) do Record(scan.found, i) end
		-- a search returns 50 per page: read them all (up to 10 pages),
		-- or the cheap listings on later pages are never seen
		total = total or shown or 0
		if (scan.page + 1) * 50 < total and scan.page < 9 then
			scan.page = scan.page + 1
		else
			scan.page = nil
		end
	end
end

local function Tick()
	if not scan then return end
	if not AHOpen() then
		ns:Print("Auction House closed; the scan stopped. Prices read so far are kept.")
		Finish()
		return
	end
	if scan.mode == "all" then
		if scan.waiting then return end
		local last = math.min(scan.total, scan.i + CHUNK)
		for i = scan.i + 1, last do Record(scan.found, i) end
		scan.i = last
		if last >= scan.total then
			scan.complete = true
			Finish()
		end
	else
		if scan.pending or not CanSendAuctionQuery() then return end
		if not scan.page then
			scan.pos = scan.pos + 1
			scan.page = 0
		end
		local q = scan.queue[scan.pos]
		if not q then
			Finish()
			return
		end
		scan.pending = true
		ns:AuctionSearch(q.name, scan.page)
	end
end

----------------------------------------------------------------------
-- a button on the Auction House window
----------------------------------------------------------------------

local ahButton

local function AddAHButton()
	if ahButton or not AuctionFrame then return end
	ahButton = CreateFrame("Button", "FycoProfessionsAHScan", AuctionFrame, "UIPanelButtonTemplate")
	ahButton:SetWidth(130)
	ahButton:SetHeight(22)
	ahButton:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -40, -14)
	ahButton:SetText("FycoProf: prices")
	ahButton:SetScript("OnClick", function()
		if not ns:ScanAll() and AHOpen() then ns:ScanShopping() end
	end)
	ahButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("FycoProfessions prices")
		GameTooltip:AddLine("Full scan when the Auction House allows one (every 15 minutes); "
			.. "otherwise scans only the materials on your paths.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	ahButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

ns:RegisterOptions("Prices", "Auction House", 30, function(L, R)
	L:Title("Auction House prices")
	L:Note("Paths are priced with vendor prices, your own Auction House "
	    .. "scans, and the cost of crafting a material yourself. Anything "
	    .. "else is an estimate (4 x its vendor sell price) and is marked as one.")
	L:Note("Scans need the Auction House open. A full scan is allowed once "
	    .. "every 15 minutes; a shopping scan searches only your path's materials.")
	L:Buttons("Full scan", function() ns:ScanAll() end,
	          "Shopping scan", function() ns:ScanShopping() end)
	L:Button("Forget saved prices", function() ns:ForgetPrices() end)

	R:Title("Status")
	-- the note is sized to the column by Column:Note; room for two lines
	local status = R:Note("No prices saved yet for this realm and faction.")
	local col = R
	col.panel.widgets[#col.panel.widgets + 1] = { Refresh = function()
		local n, age = ns:PriceCount()
		status:SetText(n > 0 and (n .. " prices saved for this realm and faction, newest " .. age .. ".")
			or "No prices saved yet for this realm and faction.")
	end }
	R:Note("Prices older than a week are ignored. The setting 'Materials: "
	    .. "Gathered only' ignores Auction House prices altogether.")
end)

function M:OnLoad()
	ns:On("AUCTION_ITEM_LIST_UPDATE", OnListUpdate)
	ns:On("AUCTION_HOUSE_SHOW", AddAHButton)
	ns:OnTick(Tick)
end
