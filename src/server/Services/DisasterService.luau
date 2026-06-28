--!strict
-- ModuleScript: ServerScriptService.Services.DisasterService
-- Layer 5 — the live-op that gives the priesthood its spotlight. Periodic server
-- threats (drought, blight) damage the crop economy; only a pure priest can quell
-- them via a server-validated ritual at the shrine. When crops die, the whole server
-- needs a priest — and a successful quelling is announced and celebrated.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader       = require(ReplicatedStorage.Framework.Loader)
local Logger       = require(ReplicatedStorage.Framework.Logger)
local Net          = require(ReplicatedStorage.Framework.Net)
local Validate     = require(ReplicatedStorage.Framework.Validate)
local PriestConfig = require(ReplicatedStorage.Config.PriestConfig)

local SCOPE = "DisasterService"

local DisasterService = {}

local timeService:    any
local priestService:  any
local gatherService:  any
local economyService: any
local npcService:     any

-- runtime
local activeDisaster: any = nil   -- PriestConfig.DisasterDef or nil
local ritual:         any = nil   -- { priest, kind, startedAt, currentStep, hits, finished }
local lastDisasterDay = 0

local KINDS: { string } = {}
for k in PriestConfig.Disasters do table.insert(KINDS, k) end

local WORRIED_LINES = {
	"The kami are angry with us…",
	"Nothing grows. What did we do?",
	"Is there no priest to lift this curse?",
	"The fields are dying.",
	"Pray — someone, pray!",
}
local RELIEF_LINES = {
	"The curse lifts! Bless the priest!",
	"The kami are appeased at last.",
	"The rains return — we are saved!",
	"The seal holds once more.",
	"Ring the bells — ring them true!",
}

-- ── disaster lifecycle ───────────────────────────────────────────
function DisasterService.isActive(): boolean
	return activeDisaster ~= nil
end

function DisasterService.startDisaster(kind: string)
	if activeDisaster ~= nil then return end
	local def = PriestConfig.Disasters[kind]
	if def == nil then Logger.warn(SCOPE, "Unknown disaster: " .. tostring(kind)); return end

	activeDisaster = def
	gatherService.setDisasterModifier({
		gatherTimeMult = def.gatherTimeMult,
		yieldChance    = def.yieldChance,
		disabledItems  = def.disabledItems,
	})
	priestService.resetRecentOfferings()

	Net.fireAllClients("DisasterStarted", { kind = def.kind, name = def.name, description = def.description })
	if npcService then npcService.broadcastMood(WORRIED_LINES) end
	Logger.info(SCOPE, "DISASTER STARTED: " .. def.name)
end

function DisasterService._quellSucceed(priest: Player)
	local def = activeDisaster
	activeDisaster = nil
	gatherService.setDisasterModifier(nil)

	-- reward the officiating priest: mon + standing (renown) + shrine favor
	economyService.addCurrency(priest, "mon", PriestConfig.QUELL_REWARD_MON)
	local dataService = Loader.get("DataService")
	local r = (dataService.get(priest, "reputation") :: any) or { renown = 0, notoriety = 0 }
	r.renown = (r.renown or 0) + PriestConfig.QUELL_REWARD_RENOWN
	dataService.set(priest, "reputation", r)
	priestService.addShrineFavor(PriestConfig.QUELL_FAVOR_GAIN)

	Net.fireAllClients("DisasterQuelled", {
		kind = def and def.kind or "?",
		name = def and def.name or "the disaster",
		by   = priest.Name,
	})
	if npcService then npcService.broadcastMood(RELIEF_LINES) end
	Logger.info(SCOPE, string.format("DISASTER QUELLED by %s (+%d mon, +%d renown)",
		priest.Name, PriestConfig.QUELL_REWARD_MON, PriestConfig.QUELL_REWARD_RENOWN))
end

-- Debug / verification + auto-scheduler entry point.
function DisasterService.triggerDisaster(kind: string?)
	local k = kind
	if k == nil or PriestConfig.Disasters[k] == nil then
		k = KINDS[math.random(1, #KINDS)]
	end
	DisasterService.startDisaster(k)
end

-- ── quelling ritual (server-validated rhythm) ────────────────────────────
function DisasterService._finishRitual()
	if ritual == nil or ritual.finished then return end
	ritual.finished = true
	local priest = ritual.priest :: Player

	local credits = math.min(
		PriestConfig.RITUAL_MAX_OFFER_CREDITS,
		math.floor(priestService.getRecentOfferings() / PriestConfig.OFFERING_PER_CREDIT)
	)
	local success = (ritual.hits + credits) >= PriestConfig.RITUAL_REQUIRED_HITS

	Net.fireClient("RitualState", priest, {
		state = "result", success = success,
		hits = ritual.hits, credits = credits, required = PriestConfig.RITUAL_REQUIRED_HITS,
	})
	Logger.info(SCOPE, string.format("Ritual by %s: hits=%d credits=%d required=%d -> %s",
		priest.Name, ritual.hits, credits, PriestConfig.RITUAL_REQUIRED_HITS, success and "SUCCESS" or "FAIL"))

	ritual = nil
	if success then
		DisasterService._quellSucceed(priest)
	end
end

function DisasterService.requestQuellRitual(priest: Player)
	if activeDisaster == nil then
		Net.fireClient("RitualState", priest, { state = "reject", reason = "There is no disaster to quell" }); return
	end
	if ritual ~= nil then
		Net.fireClient("RitualState", priest, { state = "reject", reason = "A ritual is already underway" }); return
	end
	if not priestService.canPerformRite(priest) then
		Net.fireClient("RitualState", priest, { state = "reject", reason = "You are too polluted — purify yourself first" }); return
	end
	if not priestService.isNearTag(priest, PriestConfig.TAG_SHRINE_GROUND, PriestConfig.RITUAL_SHRINE_RANGE) then
		Net.fireClient("RitualState", priest, { state = "reject", reason = "You must stand on the shrine ground" }); return
	end

	ritual = {
		priest = priest, kind = activeDisaster.kind,
		startedAt = os.clock(), currentStep = 0, hits = 0, finished = false,
	}
	Net.fireClient("RitualState", priest, {
		state       = "begin",
		totalSteps  = PriestConfig.RITUAL_STEPS,
		stepInterval = PriestConfig.RITUAL_STEP_INTERVAL,
		leadIn      = PriestConfig.RITUAL_LEAD_IN,
		tolerance   = PriestConfig.RITUAL_TOLERANCE,
	})
	Logger.info(SCOPE, priest.Name .. " began the quelling ritual")

	-- hard timeout: if the priest never finishes, the ritual fails and the disaster persists
	local mine = ritual
	task.delay(PriestConfig.RITUAL_TIMEOUT, function()
		if ritual == mine and not mine.finished then
			DisasterService._finishRitual()
		end
	end)
end

function DisasterService.submitRitualStep(priest: Player, stepId: number, _timing: number)
	if ritual == nil or ritual.finished then return end
	if ritual.priest ~= priest then return end

	-- SERVER-measured timing is the only source of truth. The client-sent `timing`
	-- is ignored for validation (it cannot be trusted). A spoofed instant "done"
	-- submits every step at elapsed~=0 and misses every beat -> ritual fails.
	if stepId ~= ritual.currentStep then return end  -- must be the next expected beat, in order
	ritual.currentStep += 1

	local elapsed    = os.clock() - ritual.startedAt
	local expectedAt = PriestConfig.RITUAL_LEAD_IN + stepId * PriestConfig.RITUAL_STEP_INTERVAL
	local hit        = math.abs(elapsed - expectedAt) <= PriestConfig.RITUAL_TOLERANCE
	if hit then ritual.hits += 1 end

	Net.fireClient("RitualState", priest, {
		state = "step", stepId = stepId, hit = hit, hits = ritual.hits,
		totalSteps = PriestConfig.RITUAL_STEPS,
	})

	if ritual.currentStep >= PriestConfig.RITUAL_STEPS then
		DisasterService._finishRitual()
	end
end

-- ── lifecycle ────────────────────────────────────────────────
function DisasterService:Init()
	timeService    = Loader.get("TimeService")
	priestService  = Loader.get("PriestService")
	gatherService  = Loader.get("GatherService")
	economyService = Loader.get("EconomyService")
	npcService     = Loader.get("NPCService")
end

function DisasterService:Start()
	Net.registerClientEvent("DisasterStarted")
	Net.registerClientEvent("DisasterQuelled")
	Net.registerClientEvent("RitualState")

	Net.registerEvent("RequestQuellRitual", Validate.shape({}))
	Net.onEvent("RequestQuellRitual", function(player: Player)
		DisasterService.requestQuellRitual(player)
	end)

	Net.registerEvent("SubmitRitualStep", Validate.shape({
		stepId = Validate.integer,
		timing = Validate.number,
	}), { rate = 12 })
	Net.onEvent("SubmitRitualStep", function(player: Player, payload: any)
		local p = payload :: { stepId: number, timing: number }
		DisasterService.submitRitualStep(player, p.stepId, p.timing)
	end)

	-- auto-scheduler: every N game-days (or when shrine favor is low) a disaster strikes
	timeService.onDayChanged:Connect(function(day: number)
		if activeDisaster ~= nil then return end
		local due = (day - lastDisasterDay) >= PriestConfig.DISASTER_INTERVAL_DAYS
		local lowFavor = priestService.getShrineFavor() < PriestConfig.SHRINE_FAVOR_LOW
		if due or lowFavor then
			lastDisasterDay = day
			DisasterService.triggerDisaster(nil)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		if ritual ~= nil and ritual.priest == player then
			ritual = nil
		end
	end)
end

return DisasterService
