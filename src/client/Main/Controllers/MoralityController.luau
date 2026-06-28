--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.MoralityController
-- Applies visual corruption effects (Lighting.Saturation, vignette, hand-shake)
-- based on UpdateMoralityDisplay payloads from the server.
-- Also owns TriggerMeditationStart / TriggerMeditationEnd firing when near a MeditationZone.

local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Net    = require(ReplicatedStorage.Framework.Net)
local Logger = require(ReplicatedStorage.Framework.Logger)

local SCOPE  = "MoralityController"
local player = Players.LocalPlayer

local MoralityController = {}

-- State
local currentSaturation = 1.0
local isMeditating      = false
local handShakeActive   = false
local phantomActive     = false
local shakeConn: RBXScriptConnection?

-- Vignette via ColorCorrectionEffect
local colorCorrection: ColorCorrectionEffect
do
	local existing = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if existing then
		colorCorrection = existing :: ColorCorrectionEffect
	else
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name   = "ShuraCorrection"
		colorCorrection.Parent = Lighting
	end
end

local function applyVisuals(saturation: number, vignette: number, shake: boolean, phantoms: boolean)
	-- Lighting.Saturation range: -1 (greyscale) to 0 (normal).
	-- Our saturation is 0..1; map: Lighting.Saturation = saturation - 1.
	local target = saturation - 1
	if math.abs(Lighting.ColorShift_Bottom.R - target) > 0.01 then
		TweenService:Create(
			Lighting,
			TweenInfo.new(2, Enum.EasingStyle.Sine),
			{ Saturation = target }
		):Play()
	end

	-- ColorCorrection brightness drop simulates vignette darkening.
	TweenService:Create(
		colorCorrection,
		TweenInfo.new(2, Enum.EasingStyle.Sine),
		{ Brightness = -vignette * 0.4 }
	):Play()

	-- Hand-shake: random camera offset every 3 frames when active.
	if shake and not handShakeActive then
		handShakeActive = true
		local cam = workspace.CurrentCamera
		local frame = 0
		shakeConn = RunService.RenderStepped:Connect(function()
			frame += 1
			if frame % 3 ~= 0 then return end
			local amp = 0.04
			local offset = CFrame.new(
				(math.random() - 0.5) * amp,
				(math.random() - 0.5) * amp,
				0
			)
			cam.CFrame = cam.CFrame * offset
		end)
	elseif not shake and handShakeActive then
		handShakeActive = false
		if shakeConn then shakeConn:Disconnect() shakeConn = nil end
	end

	phantomActive     = phantoms
	currentSaturation = saturation
end

-- Meditation zone proximity check (client fires server events)
local function isNearMeditationZone(): boolean
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp == nil then return false end
	for _, zone in CollectionService:GetTagged("MeditationZone") do
		if zone:IsA("BasePart") then
			local z      = zone :: BasePart
			local radius = math.max(z.Size.X, z.Size.Z) / 2 + 2
			if (hrp.Position - z.Position).Magnitude <= radius then
				return true
			end
		end
	end
	return false
end

function MoralityController:Init()
	Net.onClientEvent("UpdateMoralityDisplay", function(payload: any)
		local p = payload :: {
			score: number, tierName: string,
			saturation: number, vignette: number,
			handShake: boolean, phantoms: boolean,
		}
		Logger.info(SCOPE, string.format("Morality: %s (%.0f) sat=%.1f vig=%.1f",
			p.tierName, p.score, p.saturation, p.vignette))
		applyVisuals(p.saturation, p.vignette, p.handShake, p.phantoms)
	end)
end

function MoralityController:Start()
	-- Poll for proximity to MeditationZone every second.
	task.spawn(function()
		while true do
			task.wait(1)
			local near = isNearMeditationZone()
			if near and not isMeditating then
				isMeditating = true
				Logger.info(SCOPE, "Entered MeditationZone — notifying server")
				Net.fireServer("TriggerMeditationStart", {})
			elseif not near and isMeditating then
				isMeditating = false
				Logger.info(SCOPE, "Left MeditationZone — sending end")
				Net.fireServer("TriggerMeditationEnd", {})
			end
		end
	end)
end

return MoralityController
