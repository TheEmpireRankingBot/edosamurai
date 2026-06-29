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

type PhantomVictim = {
	victimName: string,
	timestamp: number?,
	wasHelpless: boolean?,
}

-- State
local currentSaturation = 1.0
local isMeditating      = false
local handShakeActive   = false
local phantomActive     = false
local shakeConn: RBXScriptConnection?
local phantomConn: RBXScriptConnection?
local phantomFolder: Folder?
local phantomModels: { Model } = {}

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

local function clearPhantoms()
	if phantomConn then
		phantomConn:Disconnect()
		phantomConn = nil
	end
	if phantomFolder then
		phantomFolder:Destroy()
		phantomFolder = nil
	end
	table.clear(phantomModels)
end

local function ensurePhantomFolder(): Folder
	if phantomFolder and phantomFolder.Parent then
		return phantomFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "LocalShuraPhantoms"
	folder.Parent = workspace
	phantomFolder = folder
	return folder
end

local function makePhantom(victimName: string, order: number): Model
	local model = Instance.new("Model")
	model.Name = "Phantom_" .. tostring(order)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(1.2, 3.2, 0.35)
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false
	body.Material = Enum.Material.SmoothPlastic
	body.Color = Color3.fromRGB(48, 48, 52)
	body.Transparency = 0.62
	body.Parent = model
	model.PrimaryPart = body

	local labelGui = Instance.new("BillboardGui")
	labelGui.Name = "VictimName"
	labelGui.Size = UDim2.fromOffset(140, 30)
	labelGui.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	labelGui.AlwaysOnTop = false
	labelGui.Parent = body

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(185, 185, 190)
	label.TextTransparency = 0.18
	label.TextStrokeTransparency = 0.55
	label.Font = Enum.Font.Antique
	label.TextScaled = true
	label.Text = victimName
	label.Parent = labelGui

	model.Parent = ensurePhantomFolder()
	return model
end

local function syncPhantoms(active: boolean, victims: { PhantomVictim })
	if not active or #victims == 0 then
		clearPhantoms()
		return
	end

	clearPhantoms()
	ensurePhantomFolder()
	for index, victim in victims do
		table.insert(phantomModels, makePhantom(victim.victimName, index))
	end

	phantomConn = RunService.RenderStepped:Connect(function()
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp == nil or not hrp:IsA("BasePart") then return end

		local count = #phantomModels
		if count == 0 then return end
		local t = os.clock()
		for index, model in phantomModels do
			local part = model.PrimaryPart
			if part == nil then continue end
			local angle = t * 0.32 + (index / count) * math.pi * 2
			local radius = 4.5 + (index % 2) * 1.2
			local bob = math.sin(t * 1.3 + index) * 0.25
			local pos = hrp.Position + Vector3.new(math.cos(angle) * radius, 1.8 + bob, math.sin(angle) * radius)
			part.CFrame = CFrame.lookAt(pos, Vector3.new(hrp.Position.X, pos.Y, hrp.Position.Z))
			part.Transparency = 0.58 + math.sin(t * 1.6 + index) * 0.08
		end
	end)
end

local function applyVisuals(saturation: number, vignette: number, shake: boolean, phantoms: boolean)
	-- Lighting.Saturation range: -1 (greyscale) to 0 (normal).
	-- Our saturation is 0..1; map: Lighting.Saturation = saturation - 1.
	local target = saturation - 1
	if math.abs(colorCorrection.Saturation - target) > 0.01 then
		TweenService:Create(
			colorCorrection,
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
	if not phantoms then clearPhantoms() end
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
			phantomVictims: { PhantomVictim }?,
		}
		Logger.info(SCOPE, string.format("Morality: %s (%.0f) sat=%.1f vig=%.1f",
			p.tierName, p.score, p.saturation, p.vignette))
		applyVisuals(p.saturation, p.vignette, p.handShake, p.phantoms)
		syncPhantoms(p.phantoms, p.phantomVictims or {})
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
