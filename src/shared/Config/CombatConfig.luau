--!strict
-- ModuleScript: ReplicatedStorage.Config.CombatConfig
-- All combat tunables. No magic numbers in CombatService / DuelService.
--
-- DESIGN NOTE: combat is LETHAL but CONTEXTUAL. The Shura damageBonus / accuracyPenalty
-- (read from MoralityConfig via MoralityService.getCombatModifiers) is a TEMPTATION layered
-- on top of these base numbers — power now, corruption later. Do NOT balance it away here.

export type WeaponClass = {
	damage:        number,
	range:         number,   -- studs
	swingCooldown: number,   -- seconds between swings
	staminaCost:   number,
	ignoresArmor:  boolean,
	tag:           string,   -- CollectionService tag of the equipped weapon tool (future use)
}

local CombatConfig = {}

CombatConfig.MAX_HEALTH = 100

-- Weapon classes. equipped.weapon (DataService) stores the KEY (e.g. "Katana").
CombatConfig.Weapons = {
	-- precise: 2 clean hits kill an unarmored target (55+55 >= 100)
	Katana   = { damage = 55, range = 7,  swingCooldown = 0.7, staminaCost = 12, ignoresArmor = false, tag = "Weapon_Katana"   },
	-- reach: sweeps from distance
	Naginata = { damage = 45, range = 11, swingCooldown = 0.9, staminaCost = 15, ignoresArmor = false, tag = "Weapon_Naginata" },
	-- bludgeon: slow, ignores armor entirely
	Kanabo   = { damage = 70, range = 6,  swingCooldown = 1.2, staminaCost = 20, ignoresArmor = true,  tag = "Weapon_Kanabo"   },
	-- fists: the fallback when nothing is equipped
	Unarmed  = { damage = 15, range = 4,  swingCooldown = 0.5, staminaCost = 5,  ignoresArmor = false, tag = "Weapon_Unarmed"  },
} :: { [string]: WeaponClass }

-- Ordered whitelist of valid weapon names — used for Validate.literal on remotes.
CombatConfig.WeaponNames = { "Katana", "Naginata", "Kanabo", "Unarmed" } :: { string }

-- ── Armor ────────────────────────────────────────────────────────────────────
-- Edo-era armour CLASSES. The reduction applies ONLY to a normal hit. Two things
-- bypass it for FULL damage (unchanged): a GapZone hit (the skilled neck/armpit
-- strike — historically where a swordsman aimed, since the plate was near-immune)
-- and weapon.ignoresArmor (the Kanabo bludgeon crushing through plate).
--   Light  — tatami-gusoku (folding kikkō/karuta plates on cloth) / kusari katabira
--            (mail): travelers, ashigaru, low rank. Fragile — heavier foes overwhelm.
--   Medium — dō-maru / munition okegawa-dō: retainers. Survivable; clean kills need
--            tactical gap hits, not brute chip damage.
--   Heavy  — tōsei-gusoku (full samurai harness): high rank. Near-immune to normal
--            blows; only a gap hit, a kanabo, or downing+executing breaks it.
export type ArmorClass = { reduction: number, edoName: string }
CombatConfig.ArmorClasses = {
	light  = { reduction = 0.15, edoName = "Tatami-gusoku" },
	medium = { reduction = 0.60, edoName = "Dō-maru"       },
	heavy  = { reduction = 0.93, edoName = "Tōsei-gusoku"  },
} :: { [string]: ArmorClass }

-- Ordered whitelist of armour-class keys (for Validate.literal / tooling).
CombatConfig.ArmorClassNames = { "light", "medium", "heavy" } :: { string }

-- Fallback reduction for an equipped.armor value that is SET but is not a known
-- class key (e.g. older "test_armor" data). Keeps legacy profiles from breaking.
CombatConfig.ARMOR_DAMAGE_REDUCTION = 0.40

CombatConfig.GAP_RADIUS             = 1.5    -- studs; hit within this of a GapZone = full damage
CombatConfig.GAP_ATTACHMENT_NAME    = "GapZone"  -- Attachment name marking an armor gap

-- ── Stamina ──────────────────────────────────────────────────────────────────
CombatConfig.MAX_STAMINA         = 100
CombatConfig.STAMINA_REGEN       = 15    -- points / second
CombatConfig.STAMINA_REGEN_DELAY = 1.5   -- seconds of no action before regen resumes

-- ── Block ────────────────────────────────────────────────────────────────────
CombatConfig.BLOCK_DAMAGE_REDUCTION = 0.60  -- 60% off incoming damage while held
CombatConfig.BLOCK_STAMINA_PER_HIT  = 25    -- stamina drained per blocked hit
CombatConfig.STAGGER_DURATION       = 1.2   -- s stunned when stamina breaks while blocking

-- ── Parry / riposte ──────────────────────────────────────────────────────────
CombatConfig.PARRY_WINDOW           = 0.25  -- block toggled within this many s of impact = full negate
CombatConfig.PARRY_STAGGER_DURATION = 0.8   -- attacker stagger on a parry (riposte window)

-- ── Dodge ────────────────────────────────────────────────────────────────────
CombatConfig.DODGE_IFRAMES  = 0.4   -- invulnerability window
CombatConfig.DODGE_STAMINA  = 30
CombatConfig.DODGE_COOLDOWN = 1.0

-- ── Downed / death / respawn ─────────────────────────────────────────────────
CombatConfig.DOWNED_DURATION       = 10  -- s window for the attacker to execute-or-spare
CombatConfig.SPARE_RECOVERY_HEALTH = 20  -- HP a spared player recovers to
CombatConfig.CRAWL_SPEED           = 4   -- WalkSpeed while downed
CombatConfig.RESPAWN_DELAY         = 8   -- s before respawn at faction spawn

-- ── Anti-exploit ─────────────────────────────────────────────────────────────
CombatConfig.RANGE_SLACK = 2  -- server allows hits up to weapon.range + this many studs

-- ── Jisei (death poem) ───────────────────────────────────────────────────────
CombatConfig.JISEI_RADIUS    = 30   -- studs; poem broadcast radius
CombatConfig.JISEI_MAX_CHARS = 120
CombatConfig.DEFAULT_JISEI   = "The dew of morning\nvanishes without a trace —\nso fades this life."

-- Resolve an equipped.armor value to a damage-reduction fraction in [0,1).
--   nil / "" / "none"      -> 0      (unarmoured: full damage)
--   a known ArmorClasses key -> that class's reduction
--   any other non-empty string (legacy data) -> ARMOR_DAMAGE_REDUCTION fallback
function CombatConfig.getArmorReduction(armorValue: string?): number
	if armorValue == nil or armorValue == "" or armorValue == "none" then
		return 0
	end
	local class = CombatConfig.ArmorClasses[armorValue]
	if class ~= nil then
		return class.reduction
	end
	return CombatConfig.ARMOR_DAMAGE_REDUCTION
end

return CombatConfig
