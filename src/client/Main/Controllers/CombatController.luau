--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.CombatController
-- Sample combat HUD + input. Sends REQUESTS only — the server is the authority.
--   Left click  : attack the player under the cursor
--   Right hold  : block
--   Q           : dodge
--   1/2/3/4     : equip Katana / Naginata / Kanabo / Unarmed (test convenience)

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net          = require(ReplicatedStorage.Framework.Net)
local Logger       = require(ReplicatedStorage.Framework.Logger)
local CombatConfig = require(ReplicatedStorage.Config.CombatConfig)

local SCOPE  = "CombatController"
local player = Players.LocalPlayer

local CombatController = {}

-- palette (matches the rest of the HUD: ink, parchment-gold, blood, sage)
local INK     = Color3.fromRGB(12, 10, 8)
local GOLD    = Color3.fromRGB(210, 190, 140)
local BLOOD   = Color3.fromRGB(150, 30, 28)
local SAGE    = Color3.fromRGB(110, 150, 120)
local STAMINA = Color3.fromRGB(196, 170, 90)

-- local mirror of server state (display only)
local currentWeapon = "Unarmed"
local maxStamina    = CombatConfig.MAX_STAMINA
local isDowned      = false
local swingTrack: AnimationTrack?

-- UI refs
local gui: ScreenGui?
local healthFill:    Frame?
local staminaFill:   Frame?
local weaponLabel:   TextLabel?
local hitMarker:     Frame?
local blockGlow:     Frame?
local flashLabel:    TextLabel?
local downedOverlay: Frame?

local function makeBar(parent: Instance, y: number, w: number, h: number, fillColor: Color3): Frame
	local track = Instance.new("Frame")
	track.Size                   = UDim2.fromOffset(w, h)
	track.Position               = UDim2.new(0.5, 0, 1, y)
	track.AnchorPoint            = Vector2.new(0.5, 1)
	track.BackgroundColor3       = INK
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel        = 0
	track.Parent                 = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Transparency = 0.5
	stroke.Thickness = 1
	stroke.Parent = track
	local fill = Instance.new("Frame")
	fill.Size             = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel  = 0
	fill.Parent           = track
	return fill
end

local function buildHud()
	if gui then return end
	local g = Instance.new("ScreenGui")
	g.Name           = "CombatHUD"
	g.ResetOnSpawn   = false
	g.IgnoreGuiInset = true
	g.DisplayOrder   = 4

	-- health + stamina bars, bottom centre
	healthFill  = makeBar(g, -54, 320, 16, BLOOD)
	staminaFill = makeBar(g, -34, 320, 10, STAMINA)

	-- weapon label
	local wl = Instance.new("TextLabel")
	wl.Size                   = UDim2.fromOffset(320, 18)
	wl.Position               = UDim2.new(0.5, 0, 1, -72)
	wl.AnchorPoint            = Vector2.new(0.5, 1)
	wl.BackgroundTransparency = 1
	wl.Text                   = "⚔ Unarmed"
	wl.TextColor3             = GOLD
	wl.TextSize               = 15
	wl.Font                   = Enum.Font.Antique
	wl.Parent                 = g
	weaponLabel = wl

	-- centre hit marker (hidden until a hit confirms)
	local hm = Instance.new("Frame")
	hm.Size                   = UDim2.fromOffset(16, 16)
	hm.Position               = UDim2.fromScale(0.5, 0.5)
	hm.AnchorPoint            = Vector2.new(0.5, 0.5)
	hm.BackgroundTransparency = 1
	hm.Parent                 = g
	for _, rot in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.Size             = UDim2.fromOffset(16, 2)
		bar.Position         = UDim2.fromScale(0.5, 0.5)
		bar.AnchorPoint      = Vector2.new(0.5, 0.5)
		bar.Rotation         = rot
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BackgroundTransparency = 1
		bar.BorderSizePixel  = 0
		bar.Parent           = hm
	end
	hitMarker = hm

	-- block glow (screen-edge sheen while guarding)
	local bg = Instance.new("Frame")
	bg.Size                   = UDim2.fromScale(1, 1)
	bg.BackgroundTransparency = 1
	bg.Parent                 = g
	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color        = GOLD
	bgStroke.Thickness    = 6
	bgStroke.Transparency = 1
	bgStroke.Parent       = bg
	blockGlow = bg

	-- transient flash text (PARRY! / STAGGERED / GUARD BROKEN)
	local fl = Instance.new("TextLabel")
	fl.Size                   = UDim2.fromOffset(400, 40)
	fl.Position               = UDim2.fromScale(0.5, 0.4)
	fl.AnchorPoint            = Vector2.new(0.5, 0.5)
	fl.BackgroundTransparency = 1
	fl.Text                   = ""
	fl.TextColor3             = GOLD
	fl.TextSize               = 30
	fl.Font                   = Enum.Font.Antique
	fl.TextTransparency       = 1
	fl.Parent                 = g
	flashLabel = fl

	-- downed overlay (grey-out + crawl hint)
	local ov = Instance.new("Frame")
	ov.Size                   = UDim2.fromScale(1, 1)
	ov.BackgroundColor3       = Color3.fromRGB(20, 18, 16)
	ov.BackgroundTransparency = 1
	ov.Visible                = false
	ov.ZIndex                 = 10
	ov.Parent                 = g
	local dl = Instance.new("TextLabel")
	dl.Size                   = UDim2.fromScale(1, 0.2)
	dl.Position               = UDim2.fromScale(0, 0.62)
	dl.BackgroundTransparency = 1
	dl.Text                   = "You are downed\nyour fate rests in their hands…  (crawl with movement keys)"
	dl.TextColor3             = Color3.fromRGB(200, 70, 70)
	dl.TextSize               = 22
	dl.Font                   = Enum.Font.Antique
	dl.ZIndex                 = 11
	dl.Parent                 = ov
	downedOverlay = ov

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
end

-- ── UI updates ────────────────────────────────────────────────────
local function updateHealth(hp: number)
	if healthFill == nil then return end
	local pct = math.clamp(hp / CombatConfig.MAX_HEALTH, 0, 1)
	TweenService:Create(healthFill, TweenInfo.new(0.2), { Size = UDim2.fromScale(pct, 1) }):Play()
end

local function updateStamina(value: number)
	if staminaFill == nil then return end
	local pct = math.clamp(value / maxStamina, 0, 1)
	staminaFill.Size = UDim2.fromScale(pct, 1)
end

local function flashHitMarker(color: Color3)
	if hitMarker == nil then return end
	for _, bar in hitMarker:GetChildren() do
		if bar:IsA("Frame") then
			bar.BackgroundColor3 = color
			bar.BackgroundTransparency = 0
			TweenService:Create(bar, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
	end
end

local function flashText(text: string, color: Color3)
	if flashLabel == nil then return end
	flashLabel.Text            = text
	flashLabel.TextColor3      = color
	flashLabel.TextTransparency = 0
	TweenService:Create(flashLabel, TweenInfo.new(0.9), { TextTransparency = 1 }):Play()
end

local function setBlockGlow(on: boolean)
	if blockGlow == nil then return end
	local stroke = blockGlow:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.15), { Transparency = on and 0.4 or 1 }):Play()
	end
end

local function showDowned(on: boolean)
	isDowned = on
	if downedOverlay == nil then return end
	downedOverlay.Visible = on
	TweenService:Create(downedOverlay, TweenInfo.new(0.4), { BackgroundTransparency = on and 0.45 or 1 }):Play()
end

-- ── Input -> requests ─────────────────────────────────────────────
local function getTargetUnderMouse(): (Player?, Vector3?)
	local mouse  = player:GetMouse()
	local target = mouse.Target
	if target == nil then return nil, nil end
	local model = target:FindFirstAncestorOfClass("Model")
	if model == nil then return nil, nil end
	local other = Players:GetPlayerFromCharacter(model)
	if other == nil or other == player then return nil, nil end
	return other, mouse.Hit.Position
end

local function playSwing()
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if hum == nil then return end
	pcall(function()
		local animator = (hum :: Humanoid):FindFirstChildOfClass("Animator")
		if animator == nil then return end
		if swingTrack == nil then
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://522635514"  -- placeholder slash
			swingTrack = animator:LoadAnimation(anim)
		end
		if swingTrack then swingTrack:Play() end
	end)
end

local function tryAttack()
	if isDowned then return end
	local target, hitPos = getTargetUnderMouse()
	if target == nil or hitPos == nil then return end
	Net.fireServer("RequestMeleeHit", {
		targetId    = target.UserId,
		weaponType  = currentWeapon,
		hitPosition = hitPos,
	})
	playSwing()
end

local function equip(weaponName: string)
	Net.fireServer("RequestEquipWeapon", { weapon = weaponName })
end

function CombatController:Init()
	Net.onClientEvent("CombatLoadout", function(payload: any)
		currentWeapon = (payload :: any).weapon or "Unarmed"
		if weaponLabel then weaponLabel.Text = "⚔ " .. currentWeapon end
	end)

	Net.onClientEvent("StaminaUpdate", function(payload: any)
		maxStamina = (payload :: any).max or maxStamina
		updateStamina((payload :: any).stamina)
	end)

	Net.onClientEvent("HitConfirmed", function(payload: any)
		local r = (payload :: any).result
		if r == "hit" then
			flashHitMarker(Color3.new(1, 1, 1))
		elseif r == "parried" then
			flashHitMarker(BLOOD); flashText("PARRIED", BLOOD)
		else  -- miss / dodged
			flashHitMarker(Color3.fromRGB(120, 120, 120))
		end
	end)

	Net.onClientEvent("CombatFeedback", function(payload: any)
		local e = (payload :: any).event
		if e == "hurt" then
			updateHealth((payload :: any).health)
		elseif e == "staggered" then
			flashText("STAGGERED", BLOOD)
		elseif e == "guardBreak" then
			flashText("GUARD BROKEN", BLOOD)
		elseif e == "parry" then
			flashText("PARRY!", SAGE)
		elseif e == "dodge" then
			flashText("— dodge —", GOLD)
		end
	end)

	Net.onClientEvent("EnterDownedState", function()
		updateHealth(0)
		showDowned(true)
	end)

	Net.onClientEvent("ExitDownedState", function(payload: any)
		showDowned(false)
		updateHealth((payload :: any).health or CombatConfig.SPARE_RECOVERY_HEALTH)
	end)
end

function CombatController:Start()
	buildHud()
	updateHealth(CombatConfig.MAX_HEALTH)
	updateStamina(maxStamina)

	player.CharacterAdded:Connect(function()
		swingTrack = nil
		showDowned(false)
		updateHealth(CombatConfig.MAX_HEALTH)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			tryAttack()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			Net.fireServer("RequestBlock", { active = true })
			setBlockGlow(true)
		elseif input.KeyCode == Enum.KeyCode.Q then
			Net.fireServer("RequestDodge", {})
		elseif input.KeyCode == Enum.KeyCode.One then equip("Katana")
		elseif input.KeyCode == Enum.KeyCode.Two then equip("Naginata")
		elseif input.KeyCode == Enum.KeyCode.Three then equip("Kanabo")
		elseif input.KeyCode == Enum.KeyCode.Four then equip("Unarmed")
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			Net.fireServer("RequestBlock", { active = false })
			setBlockGlow(false)
		end
	end)

	Logger.info(SCOPE, "Combat input online (LMB attack / RMB block / Q dodge / 1-4 weapon)")
end

return CombatController
