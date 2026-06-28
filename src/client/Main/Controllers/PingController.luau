--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.PingController
-- Verification controller: proves Net → Validate → Handler round-trip.
-- Also stress-tests the rate limiter and invalid-arg rejection.
-- Remove or repurpose once Step 5 verification passes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Net    = require(ReplicatedStorage.Framework.Net)
local Logger = require(ReplicatedStorage.Framework.Logger)

local SCOPE = "PingController"

local PingController = {}

function PingController:Init()
	-- Listen for server replies before Start() fires the ping
	Net.onClientEvent("RequestPing", function(payload: any)
		local p = payload :: { reply: string, echo: string }
		Logger.info(SCOPE, "Pong received! reply=" .. tostring(p.reply) .. " | echo=" .. tostring(p.echo))
	end)
end

function PingController:Start()
	-- Test 1: normal round-trip (proof of pipeline — kept in all environments)
	Net.fireServer("RequestPing", { message = "hello" })
	Logger.info(SCOPE, "Fired RequestPing (normal round-trip test)")

	-- Tests 2 & 3 are noisy verification harness (invalid-arg + 50-ping stress). They
	-- spam the server and exist only to prove rejection/rate-limiting, so gate them to
	-- Studio — production clients fire a single benign ping and nothing more.
	if not RunService:IsStudio() then return end

	task.spawn(function()
		task.wait(0.2)

		-- Test 2: invalid arg — fires early so it runs before any kick can terminate the client
		-- Server MUST log Validation failed and the handler must NOT run.
		Logger.info(SCOPE, "Sending invalid arg (number instead of table) — server must reject…")
		Net.fireServer("RequestPing", 99999 :: any)

		task.wait(0.8)

		-- Test 3: rate-limit stress — 50 rapid fires; server should drop 30 after burst of 20
		Logger.info(SCOPE, "Starting rate-limit stress test (50 rapid pings)…")
		for i = 1, 50 do
			Net.fireServer("RequestPing", { message = "stress_" .. tostring(i) })
		end
		Logger.info(SCOPE, "50 pings fired. Check server log for [Net][WARN] Rate limit hits.")
	end)
end

return PingController
