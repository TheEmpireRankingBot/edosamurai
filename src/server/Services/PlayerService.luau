--!strict
-- ModuleScript: ServerScriptService.Services.PlayerService
-- Template service — every future service copies this pattern.
-- Init():  cache dependencies from Loader. No cross-service calls.
-- Start(): wire events, register remotes. Safe to call other services.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader   = require(ReplicatedStorage.Framework.Loader)
local Logger   = require(ReplicatedStorage.Framework.Logger)
local Net      = require(ReplicatedStorage.Framework.Net)
local Validate = require(ReplicatedStorage.Framework.Validate)

local SCOPE = "PlayerService"

local PlayerService = {}
local dataService: any  -- DataService, fetched in Init

function PlayerService:Init()
	dataService = Loader.get("DataService")
end

function PlayerService:Start()
	-- Register the proof-of-pipeline remote.
	-- Validator: expects one argument — a table with field `message: string`.
	Net.registerEvent("RequestPing", function(...: any): (boolean, string?)
		local args = { ... }
		return Validate.shape({ message = Validate.string })(args[1])
	end)

	Net.onEvent("RequestPing", function(player: Player, payload: any)
		Logger.info(SCOPE,
			"RequestPing from " .. player.Name .. " | message=" .. tostring((payload :: any).message))
		Net.fireClient("RequestPing", player, { reply = "pong", echo = (payload :: any).message })
	end)

	-- Log each player's initial state once their profile is ready.
	Players.PlayerAdded:Connect(function(player: Player)
		task.wait(2)  -- allow DataService._loadPlayer to finish
		local currency = dataService.get(player, "currency")
		local faction  = dataService.get(player, "faction")
		local mon      = currency and (currency :: any).mon or 0
		Logger.info(SCOPE, string.format(
			"Player joined | %s | faction=%s | mon=%d",
			player.Name, tostring(faction), mon
		))
	end)
end

return PlayerService
