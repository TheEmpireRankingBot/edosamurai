--!strict
-- ModuleScript: ReplicatedStorage.Config.NPCDefs
-- Class-based schedules, REUSED across every NPC of a class (no per-NPC authoring).
-- Each state references a CollectionService anchor tag the NPC walks to.

export type ScheduleEntry = { state: string, fromHour: number, toHour: number, anchorTag: string }
export type ClassDef = {
	tag:       string,
	walkSpeed: number,
	schedule:  { ScheduleEntry },
	chatLines: { [string]: { string } },
}

local NPCDefs = {}

-- NOTE: schedule entries are evaluated in array order; the FIRST match wins, so
-- narrower windows (e.g. midday "eat") are listed before the broad window they sit inside.
NPCDefs.Classes = {
	Shopkeeper = {
		tag = "NPC_Shopkeeper",
		walkSpeed = 9,
		schedule = {
			{ state = "eat",        fromHour = 12, toHour = 13, anchorTag = "Anchor_Inn" },
			{ state = "open_stall", fromHour = 6,  toHour = 18, anchorTag = "Anchor_Market" },
			{ state = "socialize",  fromHour = 18, toHour = 20, anchorTag = "Anchor_Plaza" },
			{ state = "sleep",      fromHour = 20, toHour = 6,  anchorTag = "Anchor_House" },
		},
		chatLines = {
			open_stall = { "Step right up, finest wares in Suzu!", "Silk, salt, and steel — name your need." },
			eat        = { "A bowl of soba does wonders at midday.", "Even a merchant must eat." },
			socialize  = { "Trade was brisk today, thank the kami.", "Have you heard the news from the castle?" },
			sleep      = { "Zzz..." },
		},
	},
	Townsfolk = {
		tag = "NPC_Townsfolk",
		walkSpeed = 8,
		schedule = {
			{ state = "wander",    fromHour = 6,  toHour = 9,  anchorTag = "Anchor_Plaza" },
			{ state = "work",      fromHour = 9,  toHour = 17, anchorTag = "Anchor_Field" },
			{ state = "socialize", fromHour = 17, toHour = 20, anchorTag = "Anchor_Plaza" },
			{ state = "sleep",     fromHour = 20, toHour = 6,  anchorTag = "Anchor_House" },
		},
		chatLines = {
			wander    = { "A fine morning in the village.", "The paddies need tending." },
			work      = { "Hard work honors the ancestors.", "The harvest won't bring itself in." },
			socialize = { "Care for a cup of sake?", "Long day in the fields..." },
			sleep     = { "Zzz..." },
		},
	},
	SamuraiPatrol = {
		tag = "NPC_SamuraiPatrol",
		walkSpeed = 11,
		schedule = {
			{ state = "patrol", fromHour = 6,  toHour = 22, anchorTag = "Anchor_Gate" },
			{ state = "rest",   fromHour = 22, toHour = 6,  anchorTag = "Anchor_Barracks" },
		},
		chatLines = {
			patrol = { "Move along, citizen.", "The peace of Suzu is mine to keep.", "Bushido guides my blade." },
			rest   = { "A warrior rests, but never sleeps fully." },
		},
	},
	Priest = {
		tag = "NPC_Priest",
		walkSpeed = 7,
		schedule = {
			{ state = "morning_rite", fromHour = 5,  toHour = 7,  anchorTag = "Anchor_Shrine" },
			{ state = "tend_shrine",  fromHour = 7,  toHour = 18, anchorTag = "Anchor_Shrine" },
			{ state = "evening_rite", fromHour = 18, toHour = 20, anchorTag = "Anchor_Shrine" },
			{ state = "sleep",        fromHour = 20, toHour = 5,  anchorTag = "Anchor_House" },
		},
		chatLines = {
			morning_rite = { "The kami wake with the sun.", "Purify your heart at dawn." },
			tend_shrine  = { "Offer a coin, receive a blessing.", "The shrine welcomes all." },
			evening_rite = { "May the kami watch over Suzu tonight." },
			sleep        = { "..." },
		},
	},
	Vendor = {
		tag = "NPC_Vendor",
		walkSpeed = 8,
		schedule = {
			{ state = "setup",  fromHour = 7,  toHour = 9,  anchorTag = "Anchor_Market" },
			{ state = "trade",  fromHour = 9,  toHour = 19, anchorTag = "Anchor_Market" },
			{ state = "packup", fromHour = 19, toHour = 21, anchorTag = "Anchor_Market" },
			{ state = "sleep",  fromHour = 21, toHour = 7,  anchorTag = "Anchor_House" },
		},
		chatLines = {
			setup  = { "Setting out the day's stock...", "Fresh goods, almost ready!" },
			trade  = { "Finest rice in Suzu, fresh off the paddy!", "Best prices on the coast!", "Buy now, the kami favor a fair trade." },
			packup = { "Closing up for the night.", "Come back tomorrow, friend." },
			sleep  = { "Zzz..." },
		},
	},
} :: { [string]: ClassDef }

-- Returns the schedule entry active at `hour` (first match; handles wrap-around like 20→06).
function NPCDefs.stateForHour(className: string, hour: number): ScheduleEntry?
	local def = NPCDefs.Classes[className]
	if def == nil then return nil end
	for _, e in def.schedule do
		if e.fromHour <= e.toHour then
			if hour >= e.fromHour and hour < e.toHour then return e end
		else
			if hour >= e.fromHour or hour < e.toHour then return e end
		end
	end
	return def.schedule[#def.schedule]
end

return NPCDefs
