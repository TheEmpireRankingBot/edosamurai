--!strict
-- ModuleScript: ServerScriptService.Services.PriestService
-- Layer 5 — the Shinto priest: the NON-COMBAT faction whose loop is support power,
-- status, and server-wide impact. Priests alone purify others' corruption (harae) and
-- alone hold the seal against kegare. Blood and death pollute them; misogi cleanses.
--
-- Server-authoritative throughout: clients only REQUEST. Misogi/ritual timing is
-- measured on the SERVER clock; consent and range are enforced server-side.

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader       = require(ReplicatedStorage.Framework.Loader)
local Logger       = require(ReplicatedStorage.Framework.Logger)
local Net          = require(ReplicatedStorage.Framework.Net)
local Validate     = require(ReplicatedStorage.Framework.Validate)
local PriestConfig = require(ReplicatedStorage.Config.PriestConfig)

local SCOPE = "PriestService"

local PriestService = {}

local dataService:      any
local moralityService:  any
local economyService:   any
local factionService:   any
local inventoryService: any
local combatService:    any

-- runtime state
local energy:           { [number]: number } = {}                 -- userId -> spiritual energy
local activeBuffs:      { [number]: { [string]: any } } = {}      -- userId -> effectType -> { magnitude, expiresAt, name, id }
local pendingHarae:     { [number]: any } = {}                    -- target userId -> { priest, expiresAt }
local misogiActive:     { [number]: boolean } = {}               -- userId currently mid-misogi
local lastBloodContact: { [number]: number } = {}
local lastWitness:      { [number]: number } = {}

local shrineFavor      = PriestConfig.SHRINE_FAVOR_START          -- server-wide pool
local recentOfferings  = 0                                       -- mon offered since last disaster reset

local OMAMORI_IDS: { string } = {}
for id in PriestConfig.Omamori do table.insert(OMAMORI_IDS, id) end

-- ── helpers ─────────────────────────────────────────────────────
local function getHRP(player: Player): BasePart?
	local char = player.Character
	return (char and char:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local function isPriest(player: Player): boolean
	return factionService.getFaction(player) == "Priest"
end

local function inRange(a: Player, b: Player, range: number): boolean
	local ah, bh = getHRP(a), getHRP(b)
	if ah == nil or bh == nil then return false end
	return (ah.Position - bh.Position).Magnitude <= range
end

local function riteFail(player: Player, rite: string, reason: string)
	Net.fireClient("RiteResult", player, { rite = rite, state = "fail", reason = reason })
	Logger.info(SCOPE, string.format("%s rite '%s' failed: %s", player.Name, rite, reason))
end

-- inside any part tagged `tag` (object-space test so rotated zones work)
function PriestService.isInZone(player: Player, tag: string): boolean
	local hrp = getHRP(player)
	if hrp == nil then return false end
	for _, part in CollectionService:GetTagged(tag) do
		if part:IsA("BasePart") then
			local lp   = part.CFrame:PointToObjectSpace(hrp.Position)
			local half = part.Size / 2
			if math.abs(lp.X) <= half.X and math.abs(lp.Y) <= half.Y and math.abs(lp.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

-- within `range` studs of any part tagged `tag`
function PriestService.isNearTag(player: Player, tag: string, range: number): boolean
	local hrp = getHRP(player)
	if hrp == nil then return false end
	for _, part in CollectionService:GetTagged(tag) do
		if part:IsA("BasePart") and (part.Position - hrp.Position).Magnitude <= range then
			return true
		end
	end
	return false
end

-- ── kegare ──────────────────────────────────────────────────
local function getKegare(player: Player): number
	return (dataService.get(player, "kegare") :: number?) or 0
end

local function setKegare(player: Player, value: number)
	value = math.clamp(value, 0, PriestConfig.KEGARE_MAX)
	dataService.set(player, "kegare", value)
	Net.fireClient("UpdateKegare", player, {
		kegare    = value,
		threshold = PriestConfig.KEGARE_BAR_THRESHOLD,
		barred    = value >= PriestConfig.KEGARE_BAR_THRESHOLD,
	})
end

function PriestService.addKegare(player: Player, amount: number, reason: string)
	if not isPriest(player) then return end
	local nv = getKegare(player) + amount
	setKegare(player, nv)
	Logger.info(SCOPE, string.format("kegare +%d (%s) -> %s now %d",
		amount, reason, player.Name, math.clamp(nv, 0, PriestConfig.KEGARE_MAX)))
end

function PriestService.canPerformRite(priest: Player): boolean
	if not isPriest(priest) then return false end
	return getKegare(priest) < PriestConfig.KEGARE_BAR_THRESHOLD
end

-- ── spiritual energy ───────────────────────────────────────────
local function ensureEnergy(player: Player): number
	local uid = player.UserId
	if energy[uid] == nil then
		energy[uid] = (dataService.get(player, "spiritualEnergy") :: number?) or PriestConfig.MAX_ENERGY
	end
	return energy[uid]
end

local function setEnergy(player: Player, value: number)
	value = math.clamp(value, 0, PriestConfig.MAX_ENERGY)
	energy[player.UserId] = value
	dataService.set(player, "spiritualEnergy", value)
	Net.fireClient("UpdateEnergy", player, { energy = value, max = PriestConfig.MAX_ENERGY })
end

-- ── misogi (cold-water purification; server-timed) ──────────────────────────
function PriestService.doMisogi(priest: Player)
	if not isPriest(priest) then return end
	if misogiActive[priest.UserId] then return end
	if not PriestService.isInZone(priest, PriestConfig.TAG_MISOGI) then
		riteFail(priest, "misogi", "You must stand in the misogi waters"); return
	end
	misogiActive[priest.UserId] = true
	Net.fireClient("RiteResult", priest, { rite = "misogi", state = "begin", duration = PriestConfig.MISOGI_DURATION })
	task.spawn(function()
		local elapsed = 0
		while elapsed < PriestConfig.MISOGI_DURATION do
			task.wait(1)
			if not priest.Parent or not PriestService.isInZone(priest, PriestConfig.TAG_MISOGI) then
				misogiActive[priest.UserId] = nil
				Net.fireClient("RiteResult", priest, { rite = "misogi", state = "cancel", reason = "You left the waters too soon" })
				Logger.info(SCOPE, priest.Name .. " left misogi early — rejected")
				return
			end
			elapsed += 1
			Net.fireClient("RiteResult", priest, { rite = "misogi", state = "progress", elapsed = elapsed, duration = PriestConfig.MISOGI_DURATION })
		end
		misogiActive[priest.UserId] = nil
		setKegare(priest, 0)
		Net.fireClient("RiteResult", priest, { rite = "misogi", state = "done" })
		Logger.info(SCOPE, priest.Name .. " completed misogi (kegare -> 0)")
	end)
end

-- ── harae (purify another player's Shura) ────────────────────────────────
function PriestService._performHarae(priest: Player, target: Player)
	if not PriestService.canPerformRite(priest) then riteFail(priest, "harae", "You are too polluted to purify"); return end
	if ensureEnergy(priest) < PriestConfig.HARAE_ENERGY_COST then riteFail(priest, "harae", "Not enough spiritual energy"); return end
	if not inRange(priest, target, PriestConfig.HARAE_RANGE) then riteFail(priest, "harae", "Target moved out of range"); return end

	setEnergy(priest, ensureEnergy(priest) - PriestConfig.HARAE_ENERGY_COST)
	moralityService.adjust(target, PriestConfig.HARAE_GI_RESTORE, "harae")

	Net.fireClient("PurifyFeel", target, { fromId = priest.UserId, asPriest = false })
	Net.fireClient("PurifyFeel", priest, { fromId = priest.UserId, asPriest = true })
	Net.fireClient("RiteResult", priest, { rite = "harae", state = "done", targetName = target.Name })
	Logger.info(SCOPE, string.format("%s purified %s (+%d gi)", priest.Name, target.Name, PriestConfig.HARAE_GI_RESTORE))
end

function PriestService.requestHarae(priest: Player, target: Player?)
	if target == nil or target == priest then return end
	if not PriestService.canPerformRite(priest) then
		riteFail(priest, "harae", isPriest(priest) and "You are too polluted — purify yourself first" or "Only a priest may purify")
		return
	end
	if ensureEnergy(priest) < PriestConfig.HARAE_ENERGY_COST then riteFail(priest, "harae", "Not enough spiritual energy"); return end
	if not inRange(priest, target, PriestConfig.HARAE_RANGE) then riteFail(priest, "harae", "Move closer to purify"); return end

	-- downed/willing targets consent implicitly; otherwise ask.
	if combatService and combatService.isDowned(target) then
		PriestService._performHarae(priest, target); return
	end
	pendingHarae[target.UserId] = { priest = priest, expiresAt = os.clock() + PriestConfig.HARAE_CONSENT_TIMEOUT }
	Net.fireClient("HaraeConsentRequest", target, { priestId = priest.UserId, priestName = priest.Name })
	Net.fireClient("RiteResult", priest, { rite = "harae", state = "awaitingConsent", targetName = target.Name })
end

function PriestService.respondHarae(target: Player, accept: boolean)
	local pend = pendingHarae[target.UserId]
	if pend == nil then return end
	pendingHarae[target.UserId] = nil
	if os.clock() > pend.expiresAt then return end
	local priest = pend.priest :: Player
	if not accept then
		Net.fireClient("RiteResult", priest, { rite = "harae", state = "declined", targetName = target.Name })
		return
	end
	PriestService._performHarae(priest, target)
end

-- ── omamori (craft / apply / buff query) ────────────────────────────────
function PriestService.prepareTalismanPaper(priest: Player)
	if not isPriest(priest) then riteFail(priest, "preparePaper", "Only a priest may prepare gofu paper"); return end
	local def = PriestConfig.TalismanPaper
	if ensureEnergy(priest) < def.energyCost then riteFail(priest, "preparePaper", "Not enough spiritual energy"); return end
	if not economyService.removeCurrency(priest, "mon", def.monCost) then
		riteFail(priest, "preparePaper", "Not enough mon for paper and ink"); return
	end

	setEnergy(priest, ensureEnergy(priest) - def.energyCost)
	if not inventoryService.addItem(priest, def.itemId, 1) then
		economyService.addCurrency(priest, "mon", def.monCost)
		setEnergy(priest, ensureEnergy(priest) + def.energyCost)
		riteFail(priest, "preparePaper", "Inventory error"); return
	end

	Net.fireClient("RiteResult", priest, {
		rite = "preparePaper",
		state = "done",
		name = def.name,
		amount = def.monCost,
	})
	Logger.info(SCOPE, string.format("%s prepared %s", priest.Name, def.itemId))
end

function PriestService.craftOmamori(priest: Player, omamoriId: string)
	if not isPriest(priest) then riteFail(priest, "craft", "Only a priest may craft omamori"); return end
	local om = PriestConfig.Omamori[omamoriId]
	if om == nil then return end
	if ensureEnergy(priest) < om.energyCost then riteFail(priest, "craft", "Not enough spiritual energy"); return end
	for itemId, qty in om.materials do
		if inventoryService.count(priest, itemId) < qty then
			riteFail(priest, "craft", "Missing material: " .. itemId); return
		end
	end
	for itemId, qty in om.materials do inventoryService.removeItem(priest, itemId, qty) end
	setEnergy(priest, ensureEnergy(priest) - om.energyCost)
	inventoryService.addItem(priest, om.id, 1)
	Net.fireClient("RiteResult", priest, { rite = "craft", state = "done", omamori = om.id, name = om.name })
	Logger.info(SCOPE, priest.Name .. " crafted " .. om.id)
end

function PriestService.sellOmamori(priest: Player, target: Player?, omamoriId: string)
	if not isPriest(priest) then riteFail(priest, "sellOmamori", "Only a priest may sell omamori"); return end
	if target == nil then riteFail(priest, "sellOmamori", "Target not found"); return end
	if target == priest then riteFail(priest, "sellOmamori", "Choose another player"); return end
	if not inRange(priest, target, PriestConfig.OMAMORI_TRADE_RANGE) then
		riteFail(priest, "sellOmamori", "Buyer is too far away"); return
	end

	local om = PriestConfig.Omamori[omamoriId]
	if om == nil then return end
	if inventoryService.count(priest, om.id) < 1 then
		riteFail(priest, "sellOmamori", "You do not have that omamori"); return
	end

	if not inventoryService.removeItem(priest, om.id, 1) then
		riteFail(priest, "sellOmamori", "Inventory error"); return
	end

	local transactionId = string.format(
		"omamori:%d:%d:%s:%d:%d",
		target.UserId,
		priest.UserId,
		om.id,
		os.time(),
		math.floor(os.clock() * 1000)
	)
	local paid = economyService.transfer(target, priest, "mon", om.monCost, transactionId)
	if not paid then
		inventoryService.addItem(priest, om.id, 1)
		riteFail(priest, "sellOmamori", target.Name .. " cannot pay"); return
	end

	if not inventoryService.addItem(target, om.id, 1) then
		economyService.transfer(priest, target, "mon", om.monCost, transactionId .. ":refund")
		inventoryService.addItem(priest, om.id, 1)
		riteFail(priest, "sellOmamori", "Buyer inventory error"); return
	end

	Net.fireClient("RiteResult", priest, {
		rite = "sellOmamori",
		state = "done",
		name = om.name,
		targetName = target.Name,
		amount = om.monCost,
	})
	Net.fireClient("RiteResult", target, {
		rite = "receiveOmamori",
		state = "done",
		name = om.name,
		targetName = priest.Name,
		amount = om.monCost,
	})
	Logger.info(SCOPE, string.format("%s sold %s to %s for %d mon", priest.Name, om.id, target.Name, om.monCost))
end

function PriestService._pushBuffs(player: Player)
	local list = {}
	local b = activeBuffs[player.UserId]
	if b then
		for effectType, entry in b do
			table.insert(list, {
				effectType = effectType, name = entry.name, magnitude = entry.magnitude,
				remaining = math.max(0, entry.expiresAt - os.clock()),
			})
		end
	end
	Net.fireClient("OmamoriUpdate", player, { buffs = list })
end

function PriestService.applyOmamori(player: Player, omamoriId: string)
	local om = PriestConfig.Omamori[omamoriId]
	if om == nil then return end
	if not inventoryService.removeItem(player, om.id, 1) then
		riteFail(player, "apply", "You don't have that omamori"); return
	end
	local uid = player.UserId
	activeBuffs[uid] = activeBuffs[uid] or {}
	activeBuffs[uid][om.effectType] = {
		magnitude = om.magnitude, expiresAt = os.clock() + om.duration, name = om.name, id = om.id,
	}
	PriestService._pushBuffs(player)
	Net.fireClient("RiteResult", player, { rite = "apply", state = "done", omamori = om.id, name = om.name, duration = om.duration })
	Logger.info(SCOPE, player.Name .. " applied " .. om.id)
end

-- Read by CombatService (accuracyOffset/damageResist/staminaRegen) and NPCService (sellPrice).
function PriestService.getBuff(player: Player, effectType: string): number
	local b = activeBuffs[player.UserId]
	if b == nil then return 0 end
	local entry = b[effectType]
	if entry == nil then return 0 end
	if os.clock() >= entry.expiresAt then
		b[effectType] = nil
		return 0
	end
	return entry.magnitude
end

-- ── offerings (saisen sink) + shrine favor ───────────────────────────────
function PriestService.getShrineFavor(): number return shrineFavor end
function PriestService.getRecentOfferings(): number return recentOfferings end
function PriestService.resetRecentOfferings() recentOfferings = 0 end

local function broadcastFavor()
	Net.fireAllClients("UpdateShrineFavor", { favor = math.floor(shrineFavor), max = PriestConfig.SHRINE_FAVOR_MAX })
end

function PriestService.addShrineFavor(delta: number)
	shrineFavor = math.clamp(shrineFavor + delta, 0, PriestConfig.SHRINE_FAVOR_MAX)
	broadcastFavor()
end

function PriestService.offer(player: Player, amount: number)
	amount = math.floor(amount)
	if amount < PriestConfig.OFFERING_MIN then return end
	amount = math.min(amount, PriestConfig.OFFERING_MAX)
	-- removeCurrency DESTROYS the mon (hard sink) — it is added back to NOTHING.
	if not economyService.removeCurrency(player, "mon", amount) then
		riteFail(player, "offering", "Not enough mon to offer"); return
	end
	shrineFavor = math.min(PriestConfig.SHRINE_FAVOR_MAX, shrineFavor + amount * PriestConfig.OFFERING_TO_FAVOR)
	recentOfferings += amount

	local renownGain = math.floor(amount / PriestConfig.OFFERING_PER_RENOWN)
	if renownGain > 0 then
		local rep = (dataService.get(player, "reputation") :: any) or { renown = 0, notoriety = 0 }
		rep.renown = (rep.renown or 0) + renownGain
		dataService.set(player, "reputation", rep)
	end

	broadcastFavor()
	Net.fireClient("RiteResult", player, { rite = "offering", state = "done", amount = amount, renown = renownGain })
	Logger.info(SCOPE, string.format("%s offered %d mon (SINK). ShrineFavor=%d", player.Name, amount, math.floor(shrineFavor)))
end

-- ── pollution triggers ──────────────────────────────────────────
function PriestService._onLethalEvent(kind: string, position: Vector3)
	local gain: number, radius: number
	if kind == "kill" then
		gain, radius = PriestConfig.KegareGains.nearDeath, PriestConfig.NEAR_DEATH_RADIUS
	elseif kind == "down" then
		gain, radius = PriestConfig.KegareGains.witnessCombat, PriestConfig.WITNESS_RADIUS
	else
		return
	end
	for _, player in Players:GetPlayers() do
		if isPriest(player) then
			local hrp = getHRP(player)
			if hrp and (hrp.Position - position).Magnitude <= radius then
				if kind == "down" then
					local now = os.clock()
					if now - (lastWitness[player.UserId] or 0) < PriestConfig.WITNESS_COOLDOWN then continue end
					lastWitness[player.UserId] = now
				end
				PriestService.addKegare(player, gain, kind == "kill" and "nearDeath" or "witnessCombat")
			end
		end
	end
end

local function pushPriestState(player: Player)
	if not isPriest(player) then return end
	setKegare(player, getKegare(player))      -- re-fires UpdateKegare with current value
	setEnergy(player, ensureEnergy(player))    -- re-fires UpdateEnergy
	Net.fireClient("UpdateShrineFavor", player, { favor = math.floor(shrineFavor), max = PriestConfig.SHRINE_FAVOR_MAX })
end

-- ── lifecycle ────────────────────────────────────────────────
function PriestService:Init()
	dataService      = Loader.get("DataService")
	moralityService  = Loader.get("MoralityService")
	economyService   = Loader.get("EconomyService")
	factionService   = Loader.get("FactionService")
	inventoryService = Loader.get("InventoryService")
	combatService    = Loader.get("CombatService")
end

function PriestService:Start()
	for _, name in { "UpdateKegare", "UpdateEnergy", "UpdateShrineFavor", "PurifyFeel",
		"HaraeConsentRequest", "RiteResult", "OmamoriUpdate" } do
		Net.registerClientEvent(name)
	end

	Net.registerEvent("RequestMisogi", Validate.shape({}))
	Net.onEvent("RequestMisogi", function(player: Player)
		PriestService.doMisogi(player)
	end)

	Net.registerEvent("RequestHarae", Validate.shape({ targetId = Validate.integer }))
	Net.onEvent("RequestHarae", function(player: Player, payload: any)
		local target = Players:GetPlayerByUserId((payload :: any).targetId)
		PriestService.requestHarae(player, target)
	end)

	Net.registerEvent("RequestHaraeConsent", Validate.shape({ accept = Validate.boolean }))
	Net.onEvent("RequestHaraeConsent", function(player: Player, payload: any)
		PriestService.respondHarae(player, (payload :: any).accept)
	end)

	Net.registerEvent("RequestPrepareTalismanPaper", Validate.shape({}), { rate = 2 })
	Net.onEvent("RequestPrepareTalismanPaper", function(player: Player, _payload: any)
		PriestService.prepareTalismanPaper(player)
	end)

	Net.registerEvent("RequestCraftOmamori", Validate.shape({ id = Validate.literal(OMAMORI_IDS) }))
	Net.onEvent("RequestCraftOmamori", function(player: Player, payload: any)
		PriestService.craftOmamori(player, (payload :: any).id)
	end)

	Net.registerEvent("RequestSellOmamori",
		Validate.shape({ targetId = Validate.integer, id = Validate.literal(OMAMORI_IDS) }),
		{ rate = 3 }
	)
	Net.onEvent("RequestSellOmamori", function(player: Player, payload: any)
		local p = payload :: { targetId: number, id: string }
		PriestService.sellOmamori(player, Players:GetPlayerByUserId(p.targetId), p.id)
	end)

	Net.registerEvent("RequestApplyOmamori", Validate.shape({ id = Validate.literal(OMAMORI_IDS) }))
	Net.onEvent("RequestApplyOmamori", function(player: Player, payload: any)
		PriestService.applyOmamori(player, (payload :: any).id)
	end)

	Net.registerEvent("RequestOffering", Validate.shape({ amount = Validate.positiveInteger }), { rate = 4 })
	Net.onEvent("RequestOffering", function(player: Player, payload: any)
		PriestService.offer(player, (payload :: any).amount)
	end)

	-- pollution: react to kills/downs from CombatService
	combatService.onLethalEvent:Connect(function(kind: string, _victim: Player, _attacker: Player, position: Vector3)
		PriestService._onLethalEvent(kind, position)
	end)

	-- BloodZone contact poll + energy regen (1 Hz)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				if isPriest(player) then
					-- blood pollution
					if PriestService.isInZone(player, PriestConfig.TAG_BLOOD)
						and now - (lastBloodContact[player.UserId] or 0) >= PriestConfig.BLOOD_CONTACT_COOLDOWN then
						lastBloodContact[player.UserId] = now
						PriestService.addKegare(player, PriestConfig.KegareGains.enterBloodZone, "bloodZone")
					end
					-- energy regen (faster while tending the shrine)
					local cur = ensureEnergy(player)
					if cur < PriestConfig.MAX_ENERGY then
						local perSec = PriestConfig.ENERGY_REGEN_PER_MIN / 60
						if PriestService.isInZone(player, PriestConfig.TAG_SHRINE_TEND) then
							perSec *= PriestConfig.SHRINE_TEND_MULT
						end
						setEnergy(player, cur + perSec)
					end
				end
			end
		end
	end)

	local function onJoin(player: Player)
		task.spawn(function()
			local waited = 0
			while dataService.getProfile(player) == nil and waited < 30 do task.wait(0.2); waited += 0.2 end
			if dataService.getProfile(player) ~= nil then pushPriestState(player) end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do onJoin(player) end

	Players.PlayerRemoving:Connect(function(player: Player)
		local uid = player.UserId
		energy[uid] = nil
		activeBuffs[uid] = nil
		pendingHarae[uid] = nil
		misogiActive[uid] = nil
		lastBloodContact[uid] = nil
		lastWitness[uid] = nil
	end)
end

return PriestService
