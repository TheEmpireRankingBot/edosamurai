--!strict
-- ModuleScript: ReplicatedStorage.Config.PriestConfig
-- Layer 5 — Shinto priest systems. All priest/disaster tunables in one place.
--
-- LORE: the town sits on a thin place. Blood and death create kegare (pollution);
-- the rites hold the seal. Purity is SURVIVAL, not fussiness. The priest is the
-- non-combat faction whose loop is power + status + server-wide impact: only priests
-- purify others' corruption and only priests quell the disasters that threaten everyone.

local PriestConfig = {}

-- ── Zone tags (CollectionService; placeholder parts per spec) ────────────────────
PriestConfig.TAG_MISOGI      = "MisogiZone"      -- cold-water purification pavilion
PriestConfig.TAG_SHRINE_TEND = "ShrineTendZone" -- tending here regens energy faster
PriestConfig.TAG_SAISEN      = "SaisenBox"       -- offering box (currency sink)
PriestConfig.TAG_BLOOD       = "BloodZone"       -- pollutes priests on contact
PriestConfig.TAG_PLAGUE      = "PlagueZone"      -- disease pollution (future)
PriestConfig.TAG_SHRINE_GROUND = "ShrineGround"  -- where the quelling ritual is performed

-- ── Kegare (pollution) ───────────────────────────────────────────────
PriestConfig.KEGARE_MAX            = 100
PriestConfig.KEGARE_BAR_THRESHOLD  = 50   -- at/above this the priest is BARRED from rites + inner shrine

-- The three great pollutions (kegare gains)
PriestConfig.KegareGains = {
	nearDeath      = 15,  -- near a kill / corpse
	enterBloodZone = 10,  -- per contact (cooldown-gated)
	witnessCombat  = 5,   -- saw someone downed up close
} :: { [string]: number }

PriestConfig.NEAR_DEATH_RADIUS      = 28   -- studs; kills within this pollute a priest
PriestConfig.WITNESS_RADIUS         = 28   -- studs; downs within this pollute a priest
PriestConfig.BLOOD_CONTACT_COOLDOWN = 8    -- s between BloodZone pollution ticks
PriestConfig.WITNESS_COOLDOWN       = 4    -- s between witness pollution ticks

-- ── Misogi (cold-water purification) ────────────────────────────────────
PriestConfig.MISOGI_DURATION = 20  -- s standing in MisogiZone -> kegare to 0 (server-timed)

-- ── Spiritual energy (rite resource) ───────────────────────────────────
PriestConfig.MAX_ENERGY            = 100
PriestConfig.ENERGY_REGEN_PER_MIN  = 5     -- baseline regen
PriestConfig.SHRINE_TEND_MULT      = 6     -- regen multiplier while standing in ShrineTendZone

-- ── Harae (purifying another player's Shura) ───────────────────────────────
PriestConfig.HARAE_GI_RESTORE = 12  -- gi_shura restored to the cleansed target
PriestConfig.HARAE_ENERGY_COST = 10
PriestConfig.HARAE_RANGE       = 8   -- studs
PriestConfig.HARAE_CONSENT_TIMEOUT = 12  -- s a consent request stays open

-- ── Omamori (craftable performance buffs sold to other factions) ─────────────────
-- effectType is read by other systems via PriestService.getBuff(player, effectType):
--   staminaRegen  -> CombatService multiplies stamina regen by (1 + magnitude)
--   accuracyOffset-> CombatService subtracts magnitude from the Shura miss chance
--   sellPrice     -> NPCService multiplies vendor sell price by (1 + magnitude)
--   damageResist  -> CombatService reduces incoming damage by magnitude
export type Omamori = {
	id:         string,   -- ItemDefs id
	name:       string,
	effectType: string,
	magnitude:  number,
	duration:   number,   -- seconds the buff lasts once applied
	monCost:    number,   -- suggested sale price (buyer -> priest)
	energyCost: number,   -- spent by the priest to craft
	materials:  { [string]: number },  -- item costs to craft
}

PriestConfig.Omamori = {
	omamori_vigor = {
		id = "omamori_vigor", name = "Omamori of Vigor", effectType = "staminaRegen",
		magnitude = 0.5, duration = 180, monCost = 120, energyCost = 15, materials = {},
	},
	omamori_steady = {
		id = "omamori_steady", name = "Omamori of the Steady Hand", effectType = "accuracyOffset",
		magnitude = 0.10, duration = 180, monCost = 160, energyCost = 20, materials = { talisman_paper = 1 },
	},
	omamori_fortune = {
		id = "omamori_fortune", name = "Omamori of Fortune", effectType = "sellPrice",
		magnitude = 0.20, duration = 240, monCost = 140, energyCost = 15, materials = { talisman_paper = 1 },
	},
	omamori_warding = {
		id = "omamori_warding", name = "Omamori of Warding", effectType = "damageResist",
		magnitude = 0.15, duration = 180, monCost = 180, energyCost = 25, materials = { talisman_paper = 2 },
	},
} :: { [string]: Omamori }

-- ── Offering box (saisen) ────────────────────────────────────────────
PriestConfig.SHRINE_FAVOR_START = 100
PriestConfig.SHRINE_FAVOR_MAX   = 1000
PriestConfig.OFFERING_MIN       = 1
PriestConfig.OFFERING_MAX       = 100000     -- anti-overflow guard
PriestConfig.OFFERING_TO_FAVOR  = 1.0        -- favor gained per mon offered
PriestConfig.OFFERING_PER_RENOWN = 50        -- mon offered per +1 renown (standing)

-- ── Disasters (live-op threats only a priest can quell) ────────────────────────
export type DisasterDef = {
	kind:        string,
	name:        string,
	description: string,
	-- gather modifier applied to GatherService while active
	gatherTimeMult: number,
	yieldChance:    number,             -- chance a gather yields its item (drought < 1)
	disabledItems:  { [string]: boolean }, -- item ids whose nodes are disabled (blight)
}

PriestConfig.Disasters = {
	drought = {
		kind = "drought", name = "The Long Drought",
		description = "The rains have failed. The fields yield slowly and sparingly.",
		gatherTimeMult = 1.6, yieldChance = 0.55, disabledItems = {},
	},
	blight = {
		kind = "blight", name = "The Rice Blight",
		description = "A rot spreads through the paddies. The rice will not come.",
		gatherTimeMult = 1.0, yieldChance = 1.0, disabledItems = { rice = true },
	},
} :: { [string]: DisasterDef }

PriestConfig.DISASTER_INTERVAL_DAYS = 2    -- try to spawn a disaster every N game-days
PriestConfig.SHRINE_FAVOR_LOW       = 60   -- low favor also invites disaster

-- ── Quelling ritual (server-validated rhythm/QTE) ───────────────────────────
PriestConfig.RITUAL_STEPS          = 5
PriestConfig.RITUAL_STEP_INTERVAL  = 1.5   -- s between expected beats
PriestConfig.RITUAL_TOLERANCE      = 0.6   -- s window around each expected beat
PriestConfig.RITUAL_REQUIRED_HITS  = 4     -- hits needed (of RITUAL_STEPS) to succeed
PriestConfig.RITUAL_LEAD_IN        = 1.0   -- s before the first beat
PriestConfig.RITUAL_TIMEOUT        = 14    -- s hard cap on a ritual session
PriestConfig.RITUAL_SHRINE_RANGE   = 16    -- studs from a ShrineGround part
PriestConfig.OFFERING_PER_CREDIT   = 100   -- mon offered (this disaster) per missed-beat credit
PriestConfig.RITUAL_MAX_OFFER_CREDITS = 2  -- offerings can cover at most this many missed beats

-- ── Quell rewards ─────────────────────────────────────────────────
PriestConfig.QUELL_REWARD_MON    = 300
PriestConfig.QUELL_REWARD_RENOWN = 10
PriestConfig.QUELL_FAVOR_GAIN    = 60

return PriestConfig
