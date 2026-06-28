--!strict
-- ModuleScript: ReplicatedStorage.Config.MoralityConfig
-- Gi/Shura axis: -100 (full Shura/demon) to +100 (full Gi/honourable).
--
-- DESIGN NOTE: damageBonus at T3+ is INTENTIONAL.
-- Shura is a TEMPTATION: power now (damage up) is paid for with corruption
-- (visual/audio horror + accuracy loss at T4+). This risk/reward tension is
-- the game's core hook. Do NOT 'balance it away.'

export type Tier = {
	name:            string,
	min:             number,
	max:             number,
	saturation:      number,
	vignette:        number,
	damageBonus:     number,
	accuracyPenalty: number,
	handShake:       boolean,
	phantoms:        boolean,
}

export type Standing = "Honored" | "Neutral" | "Feared" | "Shunned"

local MoralityConfig = {}

-- Ordered from highest (T0) to lowest (T5). getTierForScore iterates in order.
MoralityConfig.Tiers = {
	{ name="Clean",     min=0,    max=100, saturation=1.0, vignette=0.0, damageBonus=0,    accuracyPenalty=0,     handShake=false, phantoms=false },
	{ name="Stained",   min=-20,  max=-1,  saturation=0.9, vignette=0.0, damageBonus=0,    accuracyPenalty=0,     handShake=false, phantoms=false },
	{ name="Troubled",  min=-40,  max=-21, saturation=0.7, vignette=0.1, damageBonus=0,    accuracyPenalty=0,     handShake=false, phantoms=false },
	{ name="Corrupted", min=-60,  max=-41, saturation=0.5, vignette=0.3, damageBonus=0.10, accuracyPenalty=0,     handShake=false, phantoms=false },
	{ name="Consumed",  min=-80,  max=-61, saturation=0.3, vignette=0.6, damageBonus=0.20, accuracyPenalty=-0.10, handShake=true,  phantoms=true  },
	{ name="Shura",     min=-100, max=-81, saturation=0.1, vignette=0.8, damageBonus=0.30, accuracyPenalty=-0.15, handShake=true,  phantoms=true  },
} :: { Tier }

MoralityConfig.GiGains = {
	honorableDuelWin = 3,
	spareDowned      = 5,
	factionDuty      = 2,
	helpCommoner     = 1,
} :: { [string]: number }

MoralityConfig.ShuraGains = {
	killHelpless    = -5,
	killFleeing     = -4,
	killUnprovoked  = -3,
	killInTown      = -1,
} :: { [string]: number }

MoralityConfig.MEDITATION_RECOVERY = 8   -- gi_shura points per completed meditation
MoralityConfig.MEDITATION_DURATION = 30  -- seconds; validated server-side, never trust client

-- Social standing derived from gi_shura. Clean score 0 remains Neutral so new
-- players get normal barks/prices; Honored is earned through positive Gi.
MoralityConfig.StandingThresholds = {
	HONORED_MIN = 20,
	FEARED_MAX = -41,
	SHUNNED_MAX = -61, -- Consumed/Shura (T4+) are socially Shunned.
}

-- World/NPC/vendor reactions. Keep social prices and barks here so NPCService
-- reads one morality-owned config instead of scattering morality numbers.
MoralityConfig.WorldReaction = {
	NPC_REACTION_RADIUS = 28,
	RETREAT_DISTANCE = 6,
	RETREAT_COOLDOWN = 24,
	HONORED_BUY_DISCOUNT = 0.10,
	HONORED_SELL_BONUS = 0.10,
	FEARED_PRICE_PENALTY = 0.15,
	SHUNNED_PRICE_PENALTY = 0.35,
	SHUNNED_REFUSED_SELL_ITEM_IDS = {
		ore = true,
	},
	RETREAT_CLASSES = {
		Townsfolk = true,
		Shopkeeper = true,
		Vendor = true,
	},
	NPCBarks = {
		Honored = {
			Default = { "A good name walks before you.", "Suzu is safer with souls like yours." },
			SamuraiPatrol = { "Your conduct honors the town.", "Walk proudly, citizen." },
			Vendor = { "For you, a fairer price.", "An honorable customer is always welcome." },
		},
		Feared = {
			Default = { "Keep your distance...", "Something cold follows that one." },
			Townsfolk = { "Do not meet their eyes.", "Please, pass us by." },
			Shopkeeper = { "Buy quickly and be gone.", "I want no trouble here." },
			Vendor = { "Your coin spends, but your shadow chills.", "No sudden moves." },
			SamuraiPatrol = { "I have my eye on you.", "Blood clings to your steps." },
		},
		Shunned = {
			Default = { "Shura... stay away!", "The air fouls around them!" },
			Townsfolk = { "Run inside. Do not speak to them.", "The dead follow that one." },
			Shopkeeper = { "Take your cursed coin elsewhere.", "I will not be stained by your business." },
			Vendor = { "No. Not everything is for sale to you.", "Your money smells of blood." },
			SamuraiPatrol = { "Draw no blade here, Shura.", "One wrong step and I strike." },
		},
	},
}

-- Returns the tier matching the given gi_shura score.
-- Score is always an integer in practice; tiers cover [-100,100] fully.
function MoralityConfig.getTierForScore(score: number): Tier
	for _, tier in MoralityConfig.Tiers do
		if score >= tier.min and score <= tier.max then
			return tier
		end
	end
	-- Clamp fallback (score outside [-100,100])
	return if score > 0 then MoralityConfig.Tiers[1] else MoralityConfig.Tiers[#MoralityConfig.Tiers]
end

function MoralityConfig.getStandingForScore(score: number): Standing
	local thresholds = MoralityConfig.StandingThresholds
	if score <= thresholds.SHUNNED_MAX then
		return "Shunned"
	elseif score <= thresholds.FEARED_MAX then
		return "Feared"
	elseif score >= thresholds.HONORED_MIN then
		return "Honored"
	end
	return "Neutral"
end

return MoralityConfig
