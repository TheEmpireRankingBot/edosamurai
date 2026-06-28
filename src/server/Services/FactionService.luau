--!strict
-- ModuleScript: ServerScriptService.Services.FactionService
-- Owns faction selection, rank, permissions, and faction-spawn teleport.

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader      = require(ReplicatedStorage.Framework.Loader)
local Logger      = require(ReplicatedStorage.Framework.Logger)
local Net         = require(ReplicatedStorage.Framework.Net)
local Validate    = require(ReplicatedStorage.Framework.Validate)
local FactionDefs = require(ReplicatedStorage.Config.FactionDefs)

local SCOPE = "FactionService"

local FactionService = {}
local dataService: any
local economyService: any

function FactionService:Init()
	-- Init caches deps only (Loader.get is a reference fetch, never a cross-service call).
	dataService    = Loader.get("DataService")
	economyService = Loader.get("EconomyService")
end

function FactionService:Start()

	Net.registerClientEvent("UpdateFactionDisplay")
	Net.registerClientEvent("ShowFactionSelect")

	-- Race-free fallback: the client may ask for its faction status once it is ready,
	-- so a missed join-time push never soft-locks the picker.
	Net.registerFunction("GetFactionStatus",
		function() return true end,
		function(requester: Player): any
			local waited = 0
			while dataService.getProfile(requester) == nil and waited < 10 do
				task.wait(0.1); waited += 0.1
			end
			return { faction = dataService.get(requester, "faction") :: string? }
		end
	)

	Net.registerEvent("RequestFactionSelect",
		Validate.shape({
			faction = Validate.literal(FactionDefs.Names),  -- single source: FactionDefs
		})
	)
	Net.onEvent("RequestFactionSelect", function(player: Player, payload: any)
		FactionService._handleSelect(player, (payload :: any).faction)
	end)

	-- Studio-only dev helper: faction choice is one-time in production, but during
	-- development we need to test every faction (e.g. Priest). This clears the faction
	-- and reopens the picker. Ignored outside Studio, so the shipped rule is untouched.
	Net.registerEvent("RequestResetFaction", Validate.shape({}))
	Net.onEvent("RequestResetFaction", function(player: Player)
		if not RunService:IsStudio() then return end
		dataService.set(player, "faction", nil)
		dataService.set(player, "rank", 1)
		Logger.warn(SCOPE, "[DEV] Faction reset for " .. player.Name .. " — reopening picker")
		Net.fireClient("UpdateFactionDisplay", player, { faction = nil, rank = nil })
		Net.fireClient("ShowFactionSelect", player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(FactionService._onReady, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(FactionService._onReady, player)
	end
end

function FactionService._onReady(player: Player)
	local waited = 0
	while dataService.getProfile(player) == nil and waited < 30 do
		task.wait(0.1)
		waited += 0.1
	end
	if not player:IsDescendantOf(game) then return end
	if dataService.getProfile(player) == nil then return end

	local faction   = dataService.get(player, "faction") :: string?
	local rankIndex = (dataService.get(player, "rank") :: number?) or 1
	local rankName: string? = nil
	if faction ~= nil then
		local def = FactionDefs.get(faction)
		if def ~= nil then rankName = def.ranks[rankIndex] end
	end
	Net.fireClient("UpdateFactionDisplay", player, { faction = faction, rank = rankName })

	-- Dedicated server→client trigger: only new players (no faction) get the picker.
	if faction == nil then
		Net.fireClient("ShowFactionSelect", player)
	end
end

function FactionService._handleSelect(player: Player, factionName: string)
	if not FactionService.canChoose(player) then
		Logger.warn(SCOPE, player.Name .. " tried to re-select faction")
		return
	end
	local def = FactionDefs.get(factionName)
	if def == nil then
		Logger.warn(SCOPE, "Unknown faction: " .. factionName)
		return
	end

	dataService.set(player, "faction", factionName)
	dataService.set(player, "rank", 1)
	economyService.addCurrency(player, "mon", def.startingMon)

	FactionService._teleport(player, def.spawnTag)

	Logger.info(SCOPE, player.Name .. " chose faction: " .. factionName)
	Net.fireClient("UpdateFactionDisplay", player, { faction = factionName, rank = def.ranks[1] })
end

function FactionService._teleport(player: Player, spawnTag: string)
	local tagged = CollectionService:GetTagged(spawnTag)
	local part: BasePart? = nil
	for _, inst in tagged do
		if inst:IsA("BasePart") then part = inst :: BasePart break end
	end
	if part == nil then
		Logger.warn(SCOPE, "No spawn part tagged '" .. spawnTag .. "' — using default")
		return
	end
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
	end
end

-- Public API

function FactionService.getFaction(player: Player): string?
	return dataService.get(player, "faction") :: string?
end

function FactionService.getRank(player: Player): number
	return (dataService.get(player, "rank") :: number?) or 1
end

function FactionService.hasPermission(player: Player, perm: string): boolean
	local faction = FactionService.getFaction(player)
	if faction == nil then return false end
	local def = FactionDefs.get(faction)
	if def == nil then return false end
	return def.permissions[perm] == true
end

function FactionService.canChoose(player: Player): boolean
	return FactionService.getFaction(player) == nil
end

-- The CollectionService tag of this player's faction spawn (nil if unaligned).
function FactionService.getSpawnTag(player: Player): string?
	local faction = FactionService.getFaction(player)
	if faction == nil then return nil end
	local def = FactionDefs.get(faction)
	return def and def.spawnTag or nil
end

-- Public respawn helper: place the player's current character at their faction spawn.
-- Used by CombatService after a death/respawn. No-op for unaligned players.
function FactionService.teleportToFactionSpawn(player: Player)
	local tag = FactionService.getSpawnTag(player)
	if tag == nil then return end
	FactionService._teleport(player, tag)
end

return FactionService
