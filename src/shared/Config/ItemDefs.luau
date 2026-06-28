--!strict
-- ModuleScript: ReplicatedStorage.Config.ItemDefs
-- Minimal Layer-1 item catalog. (No ItemDefs existed in the place when Layer 3
-- was built, so this canonical catalog was created to back inventory/vendors/gathering.)

export type ItemDef = {
	id:        string,
	name:      string,
	category:  string,   -- "raw" | "tool" | ...
	baseValue: number,   -- reference value in mon
}

local ItemDefs = {}

ItemDefs.Defs = {
	rice        = { id = "rice",        name = "Rice",        category = "raw",  baseValue = 8 },
	ore         = { id = "ore",         name = "Iron Ore",    category = "raw",  baseValue = 12 },
	fish        = { id = "fish",        name = "Fish",        category = "raw",  baseValue = 10 },
	hoe         = { id = "hoe",         name = "Farming Hoe", category = "tool", baseValue = 80 },
	fishing_rod = { id = "fishing_rod", name = "Fishing Rod", category = "tool", baseValue = 100 },

	-- Layer 5: priest crafting material + omamori charms (catalog records only;
	-- the buff data lives in PriestConfig.Omamori).
	talisman_paper   = { id = "talisman_paper",   name = "Gofu Paper",            category = "material", baseValue = 15 },
	omamori_vigor    = { id = "omamori_vigor",    name = "Omamori of Vigor",       category = "charm",    baseValue = 120 },
	omamori_steady   = { id = "omamori_steady",   name = "Omamori of the Steady Hand", category = "charm", baseValue = 160 },
	omamori_fortune  = { id = "omamori_fortune",  name = "Omamori of Fortune",     category = "charm",    baseValue = 140 },
	omamori_warding  = { id = "omamori_warding",  name = "Omamori of Warding",     category = "charm",    baseValue = 180 },
} :: { [string]: ItemDef }

function ItemDefs.get(id: string): ItemDef?
	return ItemDefs.Defs[id]
end

return ItemDefs
