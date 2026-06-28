--!strict
-- ModuleScript: ServerScriptService.Services.TimeService
-- Layer 3 world clock. 1 real minute = 1 in-game hour; full day = 24 real minutes.
-- Drives Lighting.ClockTime every Heartbeat for a smooth sky and broadcasts
-- whole-hour ticks to other services (onHourChanged/onDayChanged) and clients.

local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Framework.Logger)
local Net    = require(ReplicatedStorage.Framework.Net)

local SCOPE = "TimeService"

-- ── tiny signal ────────────────────────────────────────────────────────────────
local function newSignal(): any
	local listeners: { (...any) -> () } = {}
	local sig = {}
	function sig:Connect(fn: (...any) -> ()): any
		table.insert(listeners, fn)
		return {
			Disconnect = function()
				local i = table.find(listeners, fn)
				if i then table.remove(listeners, i) end
			end,
		}
	end
	function sig:Fire(...: any)
		for _, fn in listeners do
			task.spawn(fn, ...)
		end
	end
	return sig
end

-- ── tunables ───────────────────────────────────────────────────────────────────
local HOURS_PER_DAY         = 24
local REAL_SECONDS_PER_HOUR = 60   -- 1 real min = 1 game hour → 24 real min/day
local NIGHT_START           = 19
local NIGHT_END             = 6

local TimeService = {}

TimeService.onHourChanged = newSignal()  -- fires (hour: number, day: number)
TimeService.onDayChanged  = newSignal()  -- fires (day: number)

local gameHour      = 6.0   -- start at dawn so the town opens immediately
local gameDay       = 1
local speedMult     = 1.0
local lastWholeHour = -1

function TimeService.getHour(): number return gameHour end
function TimeService.getDay(): number return gameDay end
function TimeService.isNight(): boolean
	return gameHour < NIGHT_END or gameHour >= NIGHT_START
end

local function broadcast()
	Net.fireAllClients("UpdateGameTime", {
		hour    = math.floor(gameHour),
		day     = gameDay,
		isNight = TimeService.isNight(),
	})
end

local function onWholeHour(hour: number)
	lastWholeHour = hour
	Lighting.ClockTime = gameHour
	broadcast()
	TimeService.onHourChanged:Fire(hour, gameDay)
	Logger.info(SCOPE, string.format("Hour %02d:00 — Day %d (%s)",
		hour, gameDay, TimeService.isNight() and "night" or "day"))
end

-- Debug: jump straight to an hour and fire its tick. Used by verification.
function TimeService.setHour(hour: number)
	hour = math.clamp(hour, 0, 23.999)
	gameHour = hour
	onWholeHour(math.floor(gameHour))
end

-- Debug: scale clock speed (e.g. 60 → one game hour per real second).
function TimeService.setSpeed(mult: number)
	speedMult = math.max(0, mult)
	Logger.info(SCOPE, "Clock speed x" .. tostring(speedMult))
end

function TimeService:Init()
	Lighting.ClockTime = gameHour
end

function TimeService:Start()
	Net.registerClientEvent("UpdateGameTime")

	lastWholeHour = math.floor(gameHour)
	onWholeHour(lastWholeHour)

	Players.PlayerAdded:Connect(function(plr: Player)
		Net.fireClient("UpdateGameTime", plr, {
			hour = math.floor(gameHour), day = gameDay, isNight = TimeService.isNight(),
		})
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		gameHour += (dt / REAL_SECONDS_PER_HOUR) * speedMult
		while gameHour >= HOURS_PER_DAY do
			gameHour -= HOURS_PER_DAY
			gameDay += 1
			TimeService.onDayChanged:Fire(gameDay)
			Logger.info(SCOPE, "-- New day: " .. gameDay .. " --")
		end
		Lighting.ClockTime = gameHour
		local whole = math.floor(gameHour)
		if whole ~= lastWholeHour then
			onWholeHour(whole)
		end
	end)
end

return TimeService
