--[[ FycoProfessions - Modules/Tooltip.lua
     One line on the tooltip of every material your paths need:
       "Needed for your Jewelcrafting path: 14 (you have 3)"
     for each crafting profession you have. Works on bags, bank, loot,
     links, vendors and the Auction House -- anything that shows an item
     tooltip.

     OnTooltipSetItem can fire more than once for one item, so a flag set on
     the tooltip (cleared in OnTooltipCleared) stops the line doubling.   ]]

local _, ns = ...
local M = ns:Module("tooltip", 40)

local function Needs(id)
	local out = {}
	for _, e in ipairs(ns:PlayerProfessions()) do
		if e.prof.kind == "craft" then
			local path = ns:GetPath(e.key)
			for _, s in ipairs(path and path.shopping or {}) do
				if s.id == id then
					out[#out + 1] = { prof = e.prof, need = s.need }
					break
				end
			end
		end
	end
	return out
end

--- The lines this addon adds for an item (also used by tests).
function ns:TooltipLines(id)
	local lines = {}
	if not ns:Enabled("tooltip") then return lines end
	local needs = Needs(id)
	if #needs == 0 then return lines end
	local have = ns:ItemHave(id)
	for i = 1, #needs do
		local n = needs[i]
		lines[#lines + 1] = string.format("|cff66ccffNeeded for your %s path: %d|r |cffa0a0a0(you have %d)|r",
			n.prof.name, n.need, have)
	end
	return lines
end

local function OnSetItem(tip)
	if tip.fycoProfDone then return end
	local _, link = tip:GetItem()
	local id = link and tonumber(link:match("item:(%d+)"))
	if not id then return end
	tip.fycoProfDone = true
	local lines = ns:TooltipLines(id)
	for i = 1, #lines do tip:AddLine(lines[i]) end
	if #lines > 0 then tip:Show() end
end

local function Hook(tip)
	if not tip then return end
	tip:HookScript("OnTooltipSetItem", OnSetItem)
	tip:HookScript("OnTooltipCleared", function(t) t.fycoProfDone = nil end)
end

function M:OnLoad()
	Hook(GameTooltip)
	Hook(ItemRefTooltip)
end
