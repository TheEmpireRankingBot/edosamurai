--!strict
-- ModuleScript: ReplicatedStorage.Config.VendorDefs
-- Per-vendor stock. buyPrice = player buys FROM vendor; sellPrice = player sells TO
-- vendor (always < buyPrice). The spread is a passive mon sink and the solo-play
-- liquidity floor. Items reference ReplicatedStorage.Config.ItemDefs.

local ItemDefs = require(script.Parent.ItemDefs)

export type StockEntry = { itemId: string, buyPrice: number, sellPrice: number, dailyStock: number }
export type VendorDef  = { id: string, name: string, stock: { StockEntry } }

local VendorDefs = {}

VendorDefs.INTERACTION_RANGE = 14

VendorDefs.Defs = {
	rice_merchant = {
		id = "rice_merchant",
		name = "Rice Merchant",
		stock = {
			{ itemId = "rice", buyPrice = 12, sellPrice = 5, dailyStock = 50 },
			{ itemId = "fish", buyPrice = 20, sellPrice = 8, dailyStock = 30 },
		},
	},
	tool_smith = {
		id = "tool_smith",
		name = "Tool Smith",
		stock = {
			{ itemId = "hoe",         buyPrice = 80,     sellPrice = 30, dailyStock = 10 },
			{ itemId = "fishing_rod", buyPrice = 100,    sellPrice = 40, dailyStock = 10 },
			{ itemId = "ore",         buyPrice = 999999, sellPrice = 15, dailyStock = 0 }, -- sell-only sink
		},
	},
} :: { [string]: VendorDef }

function VendorDefs.get(id: string): VendorDef?
	return VendorDefs.Defs[id]
end

-- Dev guard: every referenced item must exist in ItemDefs.
for _, def in VendorDefs.Defs do
	for _, s in def.stock do
		assert(ItemDefs.get(s.itemId) ~= nil, "VendorDefs: unknown item " .. s.itemId)
	end
end

return VendorDefs
