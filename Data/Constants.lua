--[[ FycoProfessions - Data/Constants.lua
     Hand-maintained reference tables (not generated; the generated data
     arrives in later files). Skill line IDs are SkillLine.dbc's own, the same
     in the stock client and in this realm's rebuffed.mpq.

     Rank levels are the stock 3.3.5 trainer requirements. The data build
     (phase 2) reads the real ones from npc_trainer; until then these are what
     the UI shows, labelled as stock.                                        ]]

local _, ns = ...

-- kind: "craft" (recipes and a path), "gather" (zones and nodes), "fish"
-- secondary: a secondary profession (any character can have all three)
ns.Professions = {
	{ id = 171, key = "alchemy",        name = "Alchemy",        kind = "craft",  icon = "Interface\\Icons\\Trade_Alchemy" },
	{ id = 164, key = "blacksmithing",  name = "Blacksmithing",  kind = "craft",  icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = 333, key = "enchanting",     name = "Enchanting",     kind = "craft",  icon = "Interface\\Icons\\Trade_Engraving" },
	{ id = 202, key = "engineering",    name = "Engineering",    kind = "craft",  icon = "Interface\\Icons\\Trade_Engineering" },
	{ id = 773, key = "inscription",    name = "Inscription",    kind = "craft",  icon = "Interface\\Icons\\INV_Inscription_Tradeskill01" },
	{ id = 755, key = "jewelcrafting",  name = "Jewelcrafting",  kind = "craft",  icon = "Interface\\Icons\\INV_Misc_Gem_01" },
	{ id = 165, key = "leatherworking", name = "Leatherworking", kind = "craft",  icon = "Interface\\Icons\\Trade_LeatherWorking" },
	{ id = 197, key = "tailoring",      name = "Tailoring",      kind = "craft",  icon = "Interface\\Icons\\Trade_Tailoring" },
	{ id = 186, key = "mining",         name = "Mining",         kind = "gather", icon = "Interface\\Icons\\Trade_Mining" },
	{ id = 182, key = "herbalism",      name = "Herbalism",      kind = "gather", icon = "Interface\\Icons\\Trade_Herbalism" },
	{ id = 393, key = "skinning",       name = "Skinning",       kind = "gather", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
	{ id = 185, key = "cooking",        name = "Cooking",        kind = "craft",  icon = "Interface\\Icons\\INV_Misc_Food_15",          secondary = true },
	{ id = 129, key = "firstaid",       name = "First Aid",      kind = "craft",  icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", secondary = true },
	{ id = 356, key = "fishing",        name = "Fishing",        kind = "fish",   icon = "Interface\\Icons\\Trade_Fishing",              secondary = true },
}

-- lookups by key, by skill line ID and by the name GetSkillLineInfo returns
ns.ProfessionByKey, ns.ProfessionByID, ns.ProfessionByName = {}, {}, {}
for i = 1, #ns.Professions do
	local p = ns.Professions[i]
	p.order = i
	ns.ProfessionByKey[p.key] = p
	ns.ProfessionByID[p.id] = p
	ns.ProfessionByName[p.name] = p
end

-- trainer ranks: the skill cap each rank gives and the stock level it needs
ns.Ranks = {
	{ name = "Apprentice",   cap = 75,  level = 5 },
	{ name = "Journeyman",   cap = 150, level = 10 },
	{ name = "Expert",       cap = 225, level = 20 },
	{ name = "Artisan",      cap = 300, level = 35 },
	{ name = "Master",       cap = 375, level = 50 },
	{ name = "Grand Master", cap = 450, level = 65 },
}

ns.MAX_SKILL = 450

-- the rate choices offered: points gained per skill-up
ns.Rates = { 1, 2 }
