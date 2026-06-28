--!strict
-- ModuleScript: ServerScriptService.Services.DuelService
-- The anti-griefing AUTHORITY. Decides WHEN damage is allowed.
--
-- DESIGN: combat is lethal but contextual. You cannot freely murder in town
-- (SafeZone) or harm your own faction unless a duel is sanctioned (or you are a
-- samurai exercising canKirisute — which still triggers Shura). Real fights happen
-- in declared duels or in the lawless wilderness.

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader   = require(ReplicatedStorage.Framework.Loader)
local Logger   = require(ReplicatedStorage.Framework.Logger)
local Net      = require(ReplicatedStorage.Framework.Net)
local Validate = require(ReplicatedStorage.Framework.Validate)

local SCOPE = "DuelService"

local DuelService = {}

local dataService:     any
local factionService:  any
local moralityService: any

export type Duel = {
	challenger: Player,
	target:     Player,
	startedAt:  number,
}

-- Keyed by a sorted pair id ("<lowUserId>_<highUserId>").
local activeDuels: { [string]: Duel } = {}

-- Pending invites: keyed by target UserId -> challenger. One open invite per target.
local pendingInvites: { [number]: Player } = {}

-- Throttle for aggression flagging (per attacker) so wilderness brawls don't spam notoriety.
local lastAggressionFlag: { [number]: number } = {}
local AGGRESSION_FLAG_COOLDOWN = 5

-- ── Helpers ───────────────────────────────────────────────────────────────
local function pairId(a: Player, b: Player): string
	local lo = math.min(a.UserId, b.UserId)
	local hi = math.max(a.UserId, b.UserId)
	return tostring(lo) .. "_" .. tostring(hi)
end

local function getHRP(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- ── Lifecycle ───────────────────────────────────────────────────────────
function DuelService:Init()
	dataService     = Loader.get("DataService")
	factionService  = Loader.get("FactionService")
	moralityService = Loader.get("MoralityService")
end

function DuelService:Start()
	Net.registerClientEvent("ShowDuelInvite")
	Net.registerClientEvent("DuelStarted")
	Net.registerClientEvent("DuelEnded")

	Net.registerEvent("RequestDuel",
		Validate.shape({ targetId = Validate.integer })
	)
	Net.onEvent("RequestDuel", function(player: Player, payload: any)
		local target = Players:GetPlayerByUserId((payload :: any).targetId)
		if target then DuelService.requestDuel(player, target) end
	end)

	Net.registerEvent("AcceptDuel",
		Validate.shape({ challengerId = Validate.integer })
	)
	Net.onEvent("AcceptDuel", function(player: Player, payload: any)
		local challenger = Players:GetPlayerByUserId((payload :: any).challengerId)
		if challenger then DuelService.acceptDuel(player, challenger) end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		DuelService._cleanupPlayer(player)
	end)
end

-- ── Safe zones ──────────────────────────────────────────────────────────
-- A player is in a safe zone if their HRP is inside any Part tagged "SafeZone".
-- Town hub = SafeZone. Uses object-space test so rotated zones work.
function DuelService.inSafeZone(player: Player): boolean
	local hrp = getHRP(player)
	if hrp == nil then return false end
	for _, zone in CollectionService:GetTagged("SafeZone") do
		if zone:IsA("BasePart") then
			local z     = zone :: BasePart
			local local_ = z.CFrame:PointToObjectSpace(hrp.Position)
			local half  = z.Size / 2
			if math.abs(local_.X) <= half.X
				and math.abs(local_.Y) <= half.Y
				and math.abs(local_.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

-- ── Duel state queries ───────────────────────────────────────────────────
function DuelService.areDueling(a: Player, b: Player): boolean
	return activeDuels[pairId(a, b)] ~= nil
end

-- The core anti-griefing gate. See DESIGN note above.
function DuelService.canDamage(attacker: Player, target: Player): boolean
	if attacker == target then return false end

	-- An accepted duel always permits mutual damage.
	if DuelService.areDueling(attacker, target) then
		return true
	end

	-- No duel: town is sacrosanct.
	if DuelService.inSafeZone(target) then
		return false
	end

	-- No duel: you cannot harm your own faction…
	local aFaction = factionService.getFaction(attacker)
	local tFaction = factionService.getFaction(target)
	if aFaction ~= nil and aFaction == tFaction then
		-- …unless you are a samurai exercising canKirisute (still triggers Shura elsewhere).
		return factionService.hasPermission(attacker, "canKirisute")
	end

	-- Wilderness, lawful (cross-faction or unaligned) target: open season.
	return true
end

-- ── Invites & acceptance ─────────────────────────────────────────────────
function DuelService.requestDuel(challenger: Player, target: Player)
	if challenger == target then
		Logger.warn(SCOPE, challenger.Name .. " tried to duel themselves") return
	end
	if DuelService.areDueling(challenger, target) then
		Logger.warn(SCOPE, "Already dueling: " .. challenger.Name .. " / " .. target.Name) return
	end
	pendingInvites[target.UserId] = challenger
	Logger.info(SCOPE, challenger.Name .. " challenged " .. target.Name .. " to a duel")
	Net.fireClient("ShowDuelInvite", target, {
		challengerId   = challenger.UserId,
		challengerName = challenger.Name,
	})
end

function DuelService.acceptDuel(target: Player, challenger: Player)
	local pending = pendingInvites[target.UserId]
	if pending == nil or pending ~= challenger then
		Logger.warn(SCOPE, target.Name .. " accepted a duel with no matching invite") return
	end
	pendingInvites[target.UserId] = nil

	local id = pairId(challenger, target)
	if activeDuels[id] ~= nil then return end
	activeDuels[id] = { challenger = challenger, target = target, startedAt = os.clock() }

	Logger.info(SCOPE, "Duel started: " .. challenger.Name .. " vs " .. target.Name)
	Net.fireClient("DuelStarted", challenger, { opponentId = target.UserId,     opponentName = target.Name })
	Net.fireClient("DuelStarted", target,     { opponentId = challenger.UserId, opponentName = challenger.Name })
end

-- ── Ending duels ────────────────────────────────────────────────────────
function DuelService.endDuel(id: string, winner: Player?, loser: Player?, reason: string)
	if activeDuels[id] == nil then return end
	activeDuels[id] = nil

	if winner and loser then
		local wStats = (dataService.get(winner, "stats") :: any) or {}
		wStats.duelsWon = (wStats.duelsWon or 0) + 1
		dataService.set(winner, "stats", wStats)

		local lStats = (dataService.get(loser, "stats") :: any) or {}
		lStats.duelsLost = (lStats.duelsLost or 0) + 1
		dataService.set(loser, "stats", lStats)

		if reason == "honorable" then
			moralityService.applyGi(winner, "honorableDuelWin")
		end
	end

	Logger.info(SCOPE, "Duel ended (" .. reason .. "): " .. id)
	if winner then Net.fireClient("DuelEnded", winner, { reason = reason, won = true  }) end
	if loser  then Net.fireClient("DuelEnded", loser,  { reason = reason, won = false }) end
end

-- Public convenience used by CombatService when a duel resolves via downed/spare.
function DuelService.endDuelBetween(winner: Player, loser: Player, reason: string)
	DuelService.endDuel(pairId(winner, loser), winner, loser, reason)
end

-- ── Aggression flagging (notoriety + bounty stub for a future law system) ────────────
function DuelService.flagAggression(attacker: Player, target: Player)
	-- Only flag unsanctioned aggression in the lawless wilderness.
	if DuelService.areDueling(attacker, target) then return end
	if DuelService.inSafeZone(target) then return end

	local now  = os.clock()
	local last = lastAggressionFlag[attacker.UserId]
	if last ~= nil and now - last < AGGRESSION_FLAG_COOLDOWN then return end
	lastAggressionFlag[attacker.UserId] = now

	local rep = (dataService.get(attacker, "reputation") :: any) or { renown = 0, notoriety = 0 }
	rep.notoriety = (rep.notoriety or 0) + 1
	dataService.set(attacker, "reputation", rep)

	-- BOUNTY HOOK (stub): a future LawService consumes this signal.
	Logger.info(SCOPE, string.format("BOUNTY: %s flagged for aggression (notoriety=%d)", attacker.Name, rep.notoriety))
end

-- ── Cleanup ────────────────────────────────────────────────────────────
function DuelService._cleanupPlayer(player: Player)
	pendingInvites[player.UserId] = nil
	lastAggressionFlag[player.UserId] = nil
	-- A disconnect forfeits any active duel (opponent wins by default).
	for id, duel in activeDuels do
		if duel.challenger == player or duel.target == player then
			local opponent = if duel.challenger == player then duel.target else duel.challenger
			DuelService.endDuel(id, opponent, player, "forfeit")
		end
	end
end

return DuelService
