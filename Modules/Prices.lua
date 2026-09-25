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

--- Lowest unit buyout from your scans, and how old it is -- or nil.
function ns:AHPrice(id)
	if not FycoProfessionsDB then return nil end
	local p = Store()[id]
	if not p or time() - p[2] > STALE then return nil end
	return p[1], Age(p[2])
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

local function Record(found, i)
	local link = GetAuctionItemLink("list", i)
	local id = link and tonumber(link:match("item:(%d+)"))
	if not id or not ns.Items[id] then return end
	local _, _, count, _, _, _, _, _, buyout = GetAuctionItemInfo("list", i)
	if not buyout or buyout <= 0 then return end
	local unit = buyout / math.max(1, count or 1)
	if not found[id] or unit < found[id] then found[id] = unit end
end

local function Finish()
	local store, now, n = Store(), time(), 0
	for id, unit in pairs(scan.found) do
		store[id] = { math.floor(unit + 0.5), now }
		n = n + 1
	end
	ns:Print("Auction House scan done: " .. n .. " prices saved.")
	scan = nil
	ns:Fire("PricesChanged")
end

----------------------------------------------------------------------
-- starting scans
----------------------------------------------------------------------

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
	QueryAuctionItems("", nil, nil, 0, 0, 0, 0, 0, 0, true)
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
	scan = { mode = "list", found = {}, queue = queue, pos = 0 }
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
		for i = 1, (GetNumAuctionItems("list") or 0) do Record(scan.found, i) end
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
		if last >= scan.total then Finish() end
	else
		if scan.pending or not CanSendAuctionQuery() then return end
		scan.pos = scan.pos + 1
		local q = scan.queue[scan.pos]
		if not q then
			Finish()
			return
		end
		scan.pending = true
		QueryAuctionItems(q.name, nil, nil, 0, 0, 0, 0, 0, 0, false)
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
	local status = R:Note("")
	status:SetWidth(230)
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
