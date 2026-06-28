--!strict
-- ModuleScript: ServerScriptService.Services.DataService
-- The ONLY authority for player data. All reads/writes from other
-- services must use DataService.get() and DataService.set().
-- Never touch DataStoreService directly. Never expose profile.Data outside this module.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger       = require(ReplicatedStorage.Framework.Logger)
local DataSchema   = require(ReplicatedStorage.Data.DataSchema)
local Constants    = require(ReplicatedStorage.Config.Constants)
local ProfileStore = require(ReplicatedStorage.Packages.ProfileStore)

local SCOPE     = "DataService"
local STORE_KEY = "PlayerData_v1"

local DataService = {}

local store: any
local activeProfiles: { [number]: any } = {}  -- userId → Profile

function DataService:Init()
	store = ProfileStore.New(STORE_KEY, DataSchema.ProfileTemplate)
	Logger.info(SCOPE, "ProfileStore initialised | store=" .. STORE_KEY)
end

function DataService:Start()
	-- Handle players already in-game (Studio local test edge case)
	for _, player in Players:GetPlayers() do
		task.spawn(DataService._loadPlayer, player)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(DataService._loadPlayer, player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		DataService._releasePlayer(player)
	end)

	-- Auto-save loop
	task.spawn(function()
		while true do
			task.wait(Constants.AUTOSAVE_INTERVAL)
			for userId, profile in activeProfiles do
				if profile:IsActive() then
					Logger.info(SCOPE, "Auto-saving userId=" .. tostring(userId))
					profile:Save()
				end
			end
		end
	end)

	-- Release all sessions cleanly on server shutdown
	game:BindToClose(function()
		Logger.info(SCOPE, "BindToClose: releasing all sessions…")
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				DataService._releasePlayer(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 10
		while pending > 0 and os.clock() < deadline do
			task.wait(0.05)
		end
		Logger.info(SCOPE, "All sessions released.")
	end)
end

function DataService._loadPlayer(player: Player)
	local key     = "Player_" .. player.UserId
	local profile = store:StartSessionAsync(key)

	if profile == nil or not profile:IsActive() then
		Logger.warn(SCOPE, "Failed to load profile for " .. player.Name .. " — kicking")
		player:Kick(
			"Your data could not be loaded. Please rejoin. " ..
			"If this continues, contact support."
		)
		return
	end

	Logger.try(SCOPE, function()
		DataSchema.migrate(profile.Data)
	end)

	activeProfiles[player.UserId] = profile

	profile.OnSessionEnd:Connect(function()
		activeProfiles[player.UserId] = nil
	end)

	local currency = profile.Data.currency :: any
	Logger.info(SCOPE, string.format(
		"Profile loaded | player=%s | mon=%d | gi_shura=%d | version=%d",
		player.Name,
		currency and currency.mon or 0,
		profile.Data.gi_shura or 0,
		profile.Data.version or 0
	))
end

function DataService._releasePlayer(player: Player)
	local profile = activeProfiles[player.UserId]
	if profile then
		profile:EndSession()
		activeProfiles[player.UserId] = nil
		Logger.info(SCOPE, "Session ended for " .. player.Name)
	end
end

-- ── Public API ───────────────────────────────────────────────────────────────

function DataService.getProfile(player: Player): any?
	return activeProfiles[player.UserId]
end

function DataService.get(player: Player, key: string): any?
	local profile = activeProfiles[player.UserId]
	if not profile then
		Logger.warn(SCOPE, "get() called for player with no profile: " .. player.Name)
		return nil
	end
	return profile.Data[key]
end

function DataService.set(player: Player, key: string, value: any)
	assert(
		DataSchema.ValidKeys[key] == true,
		"DataService.set: key '" .. key .. "' is not in the schema"
	)
	local profile = activeProfiles[player.UserId]
	if not profile then
		Logger.warn(SCOPE, "set() called for player with no profile: " .. player.Name)
		return
	end
	profile.Data[key] = value
end

return DataService
