--!strict
-- ModuleScript: ServerScriptService.Services.MoralityService
-- Owns the Gi/Shura axis, kill logging, meditation, and combat modifier reads.

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader         = require(ReplicatedStorage.Framework.Loader)
local Logger         = require(ReplicatedStorage.Framework.Logger)
local Net            = require(ReplicatedStorage.Framework.Net)
local MoralityConfig = require(ReplicatedStorage.Config.MoralityConfig)

local SCOPE = "MoralityService"

local MoralityService = {}
local dataService: any
local meditating: { [number]: number } = {}  -- userId → os.clock() start

function MoralityService:Init()
	dataService = Loader.get("DataService")
end

function MoralityService:Start()
	Net.registerClientEvent("UpdateMoralityDisplay")

	Net.registerEvent("TriggerMeditationStart",
		function(...: any): (boolean, string?) return true, nil end
	)
	Net.onEvent("TriggerMeditationStart", function(player: Player, ...: any)
		MoralityService.startMeditation(player)
	end)

	Net.registerEvent("TriggerMeditationEnd",
		function(...: any): (boolean, string?) return true, nil end
	)
	Net.onEvent("TriggerMeditationEnd", function(player: Player, ...: any)
		MoralityService.completeMeditation(player)
	end)

	-- Push initial corruption state on join so a returning Shura player's screen
	-- desaturates / vignettes immediately (corruption must be legible across sessions),
	-- instead of waiting for the next gi_shura change. Mirrors PriestService.pushPriestState.
	local function pushOnReady(player: Player)
		task.spawn(function()
			local waited = 0
			while dataService.getProfile(player) == nil and waited < 30 do
				task.wait(0.2); waited += 0.2
			end
			if dataService.getProfile(player) ~= nil then
				MoralityService.fireMoralityDisplay(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(pushOnReady)
	for _, player in Players:GetPlayers() do pushOnReady(player) end
end

-- ── Core logic ───────────────────────────────────────────────────────────────

function MoralityService.getTier(player: Player): MoralityConfig.Tier
	local score = (dataService.get(player, "gi_shura") :: number?) or 0
	return MoralityConfig.getTierForScore(score)
end

function MoralityService.getMoralityStanding(player: Player): MoralityConfig.Standing
	local score = (dataService.get(player, "gi_shura") :: number?) or 0
	return MoralityConfig.getStandingForScore(score)
end

function MoralityService.adjust(player: Player, delta: number, reason: string)
	local current  = (dataService.get(player, "gi_shura") :: number?) or 0
	local newScore = math.clamp(current + delta, -100, 100)
	dataService.set(player, "gi_shura", newScore)
	Logger.info(SCOPE, string.format("gi_shura: %s | %d→%d (%s)", player.Name, current, newScore, reason))
	MoralityService.fireMoralityDisplay(player)
end

export type KillContext = {
	wasHelpless:  boolean,
	wasFleeing:   boolean,
	wasDuel:      boolean?,
	wasInTown:    boolean,
}

function MoralityService.applyKill(killer: Player, victim: Player, ctx: KillContext)
	local delta = 0
	if ctx.wasHelpless then
		delta += MoralityConfig.ShuraGains.killHelpless         -- -5
	end
	if ctx.wasFleeing then
		delta += MoralityConfig.ShuraGains.killFleeing          -- -4
	end
	if not ctx.wasDuel and not ctx.wasHelpless and not ctx.wasFleeing then
		delta += MoralityConfig.ShuraGains.killUnprovoked       -- -3 (only if nothing worse)
	end
	if ctx.wasInTown then
		delta += MoralityConfig.ShuraGains.killInTown           -- -1
	end
	if delta == 0 then return end  -- clean duel, no Shura

	-- Append to shura_kills log
	local killLog = (dataService.get(killer, "shura_kills") :: { any }?) or {}
	table.insert(killLog, { victimName = victim.Name, timestamp = os.time(), wasHelpless = ctx.wasHelpless })
	dataService.set(killer, "shura_kills", killLog)

	-- Combat stats (totalKills/honorableKills) are owned by CombatService.kill —
	-- a single writer per stat avoids double counting. MoralityService owns morality only.
	MoralityService.adjust(killer, delta, "kill:" .. victim.Name)
end

function MoralityService.applyGi(player: Player, reason: string)
	local delta = MoralityConfig.GiGains[reason]
	if delta == nil then Logger.warn(SCOPE, "Unknown Gi reason: " .. reason) return end

	-- Duel stats (honorableKills/duelsWon) are owned by Combat/DuelService —
	-- MoralityService only moves the gi_shura axis here.
	MoralityService.adjust(player, delta, "gi:" .. reason)
end

function MoralityService.getCombatModifiers(player: Player): { damageBonus: number, accuracyPenalty: number }
	local tier = MoralityService.getTier(player)
	return { damageBonus = tier.damageBonus, accuracyPenalty = tier.accuracyPenalty }
end

function MoralityService.startMeditation(player: Player)
	if meditating[player.UserId] ~= nil then
		Logger.warn(SCOPE, player.Name .. " is already meditating") return
	end
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp == nil then Logger.warn(SCOPE, "No HRP for " .. player.Name) return end

	local inZone = false
	for _, zone in CollectionService:GetTagged("MeditationZone") do
		if zone:IsA("BasePart") then
			local z      = zone :: BasePart
			local radius = math.max(z.Size.X, z.Size.Z) / 2 + 2
			if (hrp.Position - z.Position).Magnitude <= radius then
				inZone = true break
			end
		end
	end
	if not inZone then
		Logger.warn(SCOPE, player.Name .. " not in a MeditationZone") return
	end

	meditating[player.UserId] = os.clock()
	Logger.info(SCOPE, player.Name .. " started meditation")
end

function MoralityService.completeMeditation(player: Player)
	local startTime = meditating[player.UserId]
	if startTime == nil then
		Logger.warn(SCOPE, player.Name .. " completed meditation without starting") return
	end
	local elapsed = os.clock() - startTime
	if elapsed < MoralityConfig.MEDITATION_DURATION then
		Logger.warn(SCOPE, string.format(
			"%s ended meditation too early (%.1fs / %ds)",
			player.Name, elapsed, MoralityConfig.MEDITATION_DURATION))
		return
	end
	meditating[player.UserId] = nil
	MoralityService.adjust(player, MoralityConfig.MEDITATION_RECOVERY, "meditation")
	Logger.info(SCOPE, player.Name .. " completed meditation")
end

function MoralityService.fireMoralityDisplay(player: Player)
	local tier  = MoralityService.getTier(player)
	local score = (dataService.get(player, "gi_shura") :: number?) or 0
	Net.fireClient("UpdateMoralityDisplay", player, {
		score      = score,
		tierName   = tier.name,
		saturation = tier.saturation,
		vignette   = tier.vignette,
		handShake  = tier.handShake,
		phantoms   = tier.phantoms,
	})
end

return MoralityService
