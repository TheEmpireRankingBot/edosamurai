--!strict
-- ModuleScript: ReplicatedStorage.Data.DataSchema
-- Canonical player profile template and type definitions.
-- Add keys here before DataService.set() will accept them.

export type Currency     = { mon: number, silver: number, ryo: number }
export type Equipped     = { weapon: string?, armor: string?, tool: string? }
export type Reputation   = { renown: number, notoriety: number }
export type Lineage      = { ancestorName: string?, inheritedMon: number, generationCount: number }
export type Stats        = { totalKills: number, honorableKills: number, duelsWon: number, duelsLost: number }
export type InventoryItem = { itemId: string, quantity: number }

export type PlayerData = {
	currency:   Currency,
	faction:    string?,        -- "Samurai"|"Merchant"|"Civilian"|"Priest"
	rank:       number,
	gi_shura:   number,        -- -100..100 morality axis
	shura_kills: { any },      -- phantom system log
	kegare:     number,        -- priest pollution 0..100
	spiritualEnergy: number,   -- priest rite resource 0..100
	inventory:  { InventoryItem },
	equipped:   Equipped,
	reputation: Reputation,
	lineage:    Lineage,
	jiseiPoem:  string,        -- last death poem
	stats:      Stats,
	createdAt:  number,
	version:    number,        -- migration hook
}

-- Explicit key whitelist. Used by DataService.set() as the guard.
-- nil-defaulted fields (faction) must still appear here.
local VALID_KEYS: { [string]: true } = {
	currency    = true,
	faction     = true,
	rank        = true,
	gi_shura    = true,
	shura_kills = true,
	kegare      = true,
	spiritualEnergy = true,
	inventory   = true,
	equipped    = true,
	reputation  = true,
	lineage     = true,
	jiseiPoem   = true,
	stats       = true,
	createdAt   = true,
	version     = true,
}

local DataSchema = {}

DataSchema.ValidKeys = VALID_KEYS

DataSchema.ProfileTemplate = {
	currency    = { mon = 0, silver = 0, ryo = 0 },
	faction     = nil :: string?,
	rank        = 1,
	gi_shura    = 0,
	shura_kills = {} :: { any },
	kegare      = 0,
	spiritualEnergy = 100,   -- starts full; PriestConfig.MAX_ENERGY
	inventory   = {} :: { InventoryItem },
	equipped    = { weapon = nil :: string?, armor = nil :: string?, tool = nil :: string? },
	reputation  = { renown = 0, notoriety = 0 },
	lineage     = { ancestorName = nil :: string?, inheritedMon = 0, generationCount = 0 },
	jiseiPoem   = "",
	stats       = { totalKills = 0, honorableKills = 0, duelsWon = 0, duelsLost = 0 },
	createdAt   = 0,
	version     = 1,
}

-- Migrations keyed by version number.
-- Each fn upgrades data from that version to version+1.
DataSchema.Migrations = {} :: { [number]: (data: { [string]: any }) -> () }

function DataSchema.migrate(data: { [string]: any })
	local version = (data.version :: number?) or 0
	while DataSchema.Migrations[version] do
		DataSchema.Migrations[version](data)
		version += 1
		data.version = version
	end
end

return DataSchema
