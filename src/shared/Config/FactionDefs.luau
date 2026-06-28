--!strict
-- ModuleScript: ReplicatedStorage.Config.FactionDefs

export type FactionDef = {
	ranks:       { string },
	permissions: { [string]: boolean },
	spawnTag:    string,
	startingMon: number,
	description: string,
}

local FactionDefs = {}

FactionDefs.Defs = {
	Samurai = {
		ranks        = { "Ashigaru", "Samurai", "Hatamoto" },
		permissions  = {
			canCarrySwords  = true,
			canEnforceLaw   = true,
			canDuelAnywhere = true,
			canKirisute     = true,
		},
		spawnTag    = "SamuraiSpawn",
		startingMon = 200,
		description = "The warrior class. Bound by Bushido, empowered by the sword.",
	},
	Merchant = {
		ranks        = { "Peddler", "Shopkeeper", "GuildMember", "RiceBroker" },
		permissions  = {
			canOwnStall      = true,
			canHireBodyguard = true,
			canSpeculate     = true,
		},
		spawnTag    = "MerchantSpawn",
		startingMon = 300,
		description = "Masters of trade. Wealth is their blade.",
	},
	Civilian = {
		ranks        = { "Laborer", "Artisan", "MasterCraftsman", "VillageHead" },
		permissions  = {
			canCraft       = true,
			canGather      = true,
			canOwnWorkshop = true,
		},
		spawnTag    = "CivilianSpawn",
		startingMon = 150,
		description = "The backbone of the land. Humble but essential.",
	},
	Priest = {
		ranks        = { "Novice", "Kannushi", "Guji" },
		permissions  = {
			canPurify      = true,
			canRunFestival = true,
			canSellOmamori = true,
			canRingBell    = true,
		},
		spawnTag    = "PriestSpawn",
		startingMon = 100,
		description = "Servants of the kami. They alone can cleanse kegare.",
	},
} :: { [string]: FactionDef }

-- Ordered canonical faction-name list. SINGLE SOURCE for the RequestFactionSelect
-- validator and any UI that must enumerate factions (no hardcoded name lists elsewhere).
FactionDefs.Names = { "Samurai", "Merchant", "Civilian", "Priest" } :: { string }

function FactionDefs.isValid(name: string): boolean
	return FactionDefs.Defs[name] ~= nil
end

function FactionDefs.get(name: string): FactionDef?
	return FactionDefs.Defs[name]
end

return FactionDefs
