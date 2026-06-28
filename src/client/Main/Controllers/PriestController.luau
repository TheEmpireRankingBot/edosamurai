--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.PriestController
-- Priest HUD + rites. Sends REQUESTS only; the server decides everything.
--   Kegare meter + spiritual-energy bar (priests only)
--   ProximityPrompt on a MisogiZone -> RequestMisogi (20s server-timed bar)
--   H while pointing at a player    -> RequestHarae (they get a consent popup)
--   Rite menu                       -> craft omamori
-- Also renders "PurifyFeel" (the calm light-bloom + chime, the opposite of Shura).

local Players                = game:GetService("Players")
local UserInputService       = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService      = game:GetService("CollectionService")
local TweenService           = game:GetService("TweenService")
local Lighting               = game:GetService("Lighting")
local SoundService           = game:GetService("SoundService")
local Debris                 = game:GetService("Debris")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")

local Net          = require(ReplicatedStorage.Framework.Net)
local Logger       = require(ReplicatedStorage.Framework.Logger)
local PriestConfig = require(ReplicatedStorage.Config.PriestConfig)

local SCOPE  = "PriestController"
local player = Players.LocalPlayer

local PriestController = {}

local INK   = Color3.fromRGB(14, 12, 10)
local GOLD  = Color3.fromRGB(210, 190, 140)
local JADE  = Color3.fromRGB(150, 205, 175)
local KEGARE_COL = Color3.fromRGB(120, 70, 150)
local BLOOD = Color3.fromRGB(180, 70, 70)

local isPriest    = false
local barred      = false
local pendingPriestId: number? = nil

-- UI refs
local gui:          ScreenGui?
local kegareFill:   Frame?
local energyFill:   Frame?
local barredLabel:  TextLabel?
local toast:        TextLabel?
local misogiBar:    Frame?
local misogiFill:   Frame?
local craftPanel:   Frame?
local consentPanel: Frame?
local consentLabel: TextLabel?

local function makeBar(parent: Instance, pos: UDim2, w: number, h: number, col: Color3): Frame
	local track = Instance.new("Frame")
	track.Size = UDim2.fromOffset(w, h); track.Position = pos; track.AnchorPoint = Vector2.new(0, 0.5)
	track.BackgroundColor3 = INK; track.BackgroundTransparency = 0.2; track.BorderSizePixel = 0
	track.Parent = parent
	local st = Instance.new("UIStroke"); st.Color = GOLD; st.Transparency = 0.6; st.Parent = track
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1); fill.BackgroundColor3 = col; fill.BorderSizePixel = 0; fill.Parent = track
	return fill
end

local function makeButton(parent: Instance, order: number, text: string): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = order; b.Size = UDim2.new(1, 0, 0, 30)
	b.BackgroundColor3 = Color3.fromRGB(34, 28, 22); b.BorderSizePixel = 0
	b.Text = text; b.TextColor3 = GOLD; b.TextSize = 14; b.Font = Enum.Font.Antique
	b.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = b
	return b
end

local function build()
	if gui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "PriestHUD"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 5
	g.Enabled = false

	-- left-side priest panel
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(230, 96); panel.Position = UDim2.new(0, 8, 0.5, -120)
	panel.BackgroundColor3 = INK; panel.BackgroundTransparency = 0.35; panel.BorderSizePixel = 0
	panel.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10); pad.PaddingTop = UDim.new(0, 8); pad.Parent = panel

	local kTitle = Instance.new("TextLabel")
	kTitle.Size = UDim2.fromOffset(210, 16); kTitle.Position = UDim2.fromOffset(0, 2)
	kTitle.BackgroundTransparency = 1; kTitle.Text = "穢 Kegare"; kTitle.TextColor3 = KEGARE_COL
	kTitle.TextXAlignment = Enum.TextXAlignment.Left; kTitle.TextSize = 13; kTitle.Font = Enum.Font.Antique
	kTitle.Parent = panel
	kegareFill = makeBar(panel, UDim2.fromOffset(0, 30), 200, 12, KEGARE_COL)

	local eTitle = Instance.new("TextLabel")
	eTitle.Size = UDim2.fromOffset(210, 16); eTitle.Position = UDim2.fromOffset(0, 44)
	eTitle.BackgroundTransparency = 1; eTitle.Text = "霊 Spiritual Energy"; eTitle.TextColor3 = JADE
	eTitle.TextXAlignment = Enum.TextXAlignment.Left; eTitle.TextSize = 13; eTitle.Font = Enum.Font.Antique
	eTitle.Parent = panel
	energyFill = makeBar(panel, UDim2.fromOffset(0, 72), 200, 10, JADE)

	local bl = Instance.new("TextLabel")
	bl.Size = UDim2.fromOffset(220, 18); bl.Position = UDim2.new(0, 8, 0.5, -28)
	bl.BackgroundTransparency = 1; bl.Text = ""; bl.TextColor3 = BLOOD
	bl.TextXAlignment = Enum.TextXAlignment.Left; bl.TextSize = 13; bl.Font = Enum.Font.Antique
	bl.Parent = g
	barredLabel = bl

	-- rite menu (right of the bars)
	local menu = Instance.new("Frame")
	menu.Size = UDim2.fromOffset(180, 150); menu.Position = UDim2.new(0, 8, 0.5, -16)
	menu.BackgroundColor3 = INK; menu.BackgroundTransparency = 0.35; menu.BorderSizePixel = 0
	menu.Parent = g
	local ml = Instance.new("UIListLayout"); ml.Padding = UDim.new(0, 4); ml.SortOrder = Enum.SortOrder.LayoutOrder; ml.Parent = menu
	local mp = Instance.new("UIPadding"); mp.PaddingLeft = UDim.new(0,8); mp.PaddingRight = UDim.new(0,8); mp.PaddingTop = UDim.new(0,8); mp.Parent = menu
	local hint = Instance.new("TextLabel")
	hint.LayoutOrder = 0; hint.Size = UDim2.new(1,0,0,30); hint.BackgroundTransparency = 1
	hint.Text = "Rites of the Kannushi"; hint.TextColor3 = GOLD; hint.TextSize = 13; hint.Font = Enum.Font.Antique
	hint.TextWrapped = true; hint.Parent = menu
	local haraeHint = makeButton(menu, 1, "Harae — aim + press H")
	haraeHint.AutoButtonColor = false
	local craftBtn = makeButton(menu, 2, "Craft Omamori ▾")

	-- craft sub-panel
	local craft = Instance.new("Frame")
	craft.Size = UDim2.fromOffset(220, 150); craft.Position = UDim2.new(0, 196, 0.5, -16)
	craft.BackgroundColor3 = INK; craft.BackgroundTransparency = 0.3; craft.BorderSizePixel = 0
	craft.Visible = false; craft.Parent = g
	local cl = Instance.new("UIListLayout"); cl.Padding = UDim.new(0,4); cl.SortOrder = Enum.SortOrder.LayoutOrder; cl.Parent = craft
	local cpad = Instance.new("UIPadding"); cpad.PaddingLeft = UDim.new(0,8); cpad.PaddingRight = UDim.new(0,8); cpad.PaddingTop = UDim.new(0,8); cpad.Parent = craft
	local order = 1
	for id, om in PriestConfig.Omamori do
		local b = makeButton(craft, order, om.name .. "  (霊" .. tostring(om.energyCost) .. ")")
		b.TextSize = 12
		local capId = id
		b.Activated:Connect(function() Net.fireServer("RequestCraftOmamori", { id = capId }) end)
		order += 1
	end
	craftPanel = craft
	craftBtn.Activated:Connect(function() craft.Visible = not craft.Visible end)

	-- misogi progress bar (center)
	local mb = Instance.new("Frame")
	mb.Size = UDim2.fromOffset(280, 20); mb.Position = UDim2.fromScale(0.5, 0.8); mb.AnchorPoint = Vector2.new(0.5, 0.5)
	mb.BackgroundColor3 = INK; mb.BorderSizePixel = 0; mb.Visible = false; mb.Parent = g
	local mf = Instance.new("Frame"); mf.Size = UDim2.fromScale(0,1); mf.BackgroundColor3 = Color3.fromRGB(120, 180, 230); mf.BorderSizePixel = 0; mf.Parent = mb
	local mlab = Instance.new("TextLabel"); mlab.Size = UDim2.fromScale(1,1); mlab.BackgroundTransparency = 1
	mlab.Text = "Misogi — cold water purification"; mlab.TextColor3 = Color3.fromRGB(220,235,245); mlab.TextSize = 13; mlab.Font = Enum.Font.Antique; mlab.Parent = mb
	misogiBar = mb; misogiFill = mf

	-- harae consent popup
	local cp = Instance.new("Frame")
	cp.Size = UDim2.fromOffset(360, 92); cp.Position = UDim2.new(0.5, 0, 0, 90); cp.AnchorPoint = Vector2.new(0.5, 0)
	cp.BackgroundColor3 = INK; cp.BackgroundTransparency = 0.1; cp.BorderSizePixel = 0; cp.Visible = false; cp.Parent = g
	local cpc = Instance.new("UICorner"); cpc.CornerRadius = UDim.new(0,6); cpc.Parent = cp
	local cps = Instance.new("UIStroke"); cps.Color = JADE; cps.Transparency = 0.3; cps.Parent = cp
	local cpl = Instance.new("TextLabel"); cpl.Size = UDim2.new(1,-16,0,40); cpl.Position = UDim2.fromOffset(8,6)
	cpl.BackgroundTransparency = 1; cpl.Text = ""; cpl.TextColor3 = JADE; cpl.TextSize = 16; cpl.Font = Enum.Font.Antique; cpl.TextWrapped = true; cpl.Parent = cp
	consentLabel = cpl
	local acc = makeButton(cp, 1, "Accept purification (受)"); acc.Size = UDim2.fromOffset(165, 30); acc.Position = UDim2.fromOffset(10, 52)
	local dec = makeButton(cp, 2, "Decline"); dec.Size = UDim2.fromOffset(165, 30); dec.Position = UDim2.fromOffset(185, 52)
	acc.Activated:Connect(function() Net.fireServer("RequestHaraeConsent", { accept = true }); cp.Visible = false end)
	dec.Activated:Connect(function() Net.fireServer("RequestHaraeConsent", { accept = false }); cp.Visible = false end)
	consentPanel = cp

	-- toast
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromOffset(420, 26); t.Position = UDim2.fromScale(0.5, 0.72); t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.BackgroundTransparency = 1; t.Text = ""; t.TextColor3 = JADE; t.TextSize = 18; t.Font = Enum.Font.Antique; t.TextTransparency = 1; t.Parent = g
	toast = t

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
end

local function showToast(text: string, color: Color3)
	if toast == nil then return end
	toast.Text = text; toast.TextColor3 = color; toast.TextTransparency = 0
	TweenService:Create(toast, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { TextTransparency = 1 }):Play()
end

local function becomePriest()
	if isPriest then return end
	isPriest = true
	build()
	if gui then gui.Enabled = true end
end

-- the calm opposite of Shura: a white bloom + soft chime on the cleansed player
local function purifyFeel()
	Logger.try(SCOPE, function()
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "PurifyBloom"; cc.Brightness = 0; cc.Saturation = 0; cc.Contrast = 0; cc.Parent = Lighting
		TweenService:Create(cc, TweenInfo.new(0.4, Enum.EasingStyle.Sine), { Brightness = 0.18, Saturation = 0.25 }):Play()
		task.delay(0.45, function()
			TweenService:Create(cc, TweenInfo.new(1.1, Enum.EasingStyle.Sine), { Brightness = 0, Saturation = 0 }):Play()
			Debris:AddItem(cc, 1.3)
		end)
		local s = Instance.new("Sound")
		s.SoundId = "rbxasset://sounds/bell.wav"; s.Volume = 0.6; s.Parent = SoundService; s:Play()
		Debris:AddItem(s, 3)
	end)
end

local function getPlayerUnderMouse(): Player?
	local m = player:GetMouse()
	local target = m.Target
	if target == nil then return nil end
	local model = target:FindFirstAncestorOfClass("Model")
	if model == nil then return nil end
	local other = Players:GetPlayerFromCharacter(model)
	if other == nil or other == player then return nil end
	return other
end

function PriestController:Init()
	Net.onClientEvent("UpdateKegare", function(payload: any)
		becomePriest()
		local p = payload :: { kegare: number, threshold: number, barred: boolean }
		barred = p.barred == true
		if kegareFill then kegareFill.Size = UDim2.fromScale(math.clamp(p.kegare / PriestConfig.KEGARE_MAX, 0, 1), 1) end
		if barredLabel then barredLabel.Text = barred and "— BARRED: purify yourself (kegare ≥ 50) —" or "" end
	end)

	Net.onClientEvent("UpdateEnergy", function(payload: any)
		becomePriest()
		local p = payload :: { energy: number, max: number }
		if energyFill then energyFill.Size = UDim2.fromScale(math.clamp(p.energy / (p.max or 100), 0, 1), 1) end
	end)

	Net.onClientEvent("RiteResult", function(payload: any)
		local p = payload :: { rite: string, state: string, reason: string?, elapsed: number?, duration: number?, name: string?, targetName: string?, amount: number? }
		if p.rite == "misogi" then
			if p.state == "begin" then
				if misogiBar then misogiBar.Visible = true end
				if misogiFill then misogiFill.Size = UDim2.fromScale(0, 1) end
			elseif p.state == "progress" then
				if misogiFill then misogiFill.Size = UDim2.fromScale(math.clamp((p.elapsed or 0) / (p.duration or 20), 0, 1), 1) end
			elseif p.state == "done" then
				if misogiBar then misogiBar.Visible = false end
				showToast("You are cleansed. The seal accepts you.", Color3.fromRGB(150, 200, 235))
			elseif p.state == "cancel" then
				if misogiBar then misogiBar.Visible = false end
				showToast(p.reason or "Misogi interrupted", BLOOD)
			end
		elseif p.state == "fail" then
			showToast(p.reason or "The rite fails", BLOOD)
		elseif p.state == "done" and p.rite == "harae" then
			showToast("You purified " .. tostring(p.targetName) .. ".", JADE)
		elseif p.state == "awaitingConsent" then
			showToast("Awaiting " .. tostring(p.targetName) .. "'s consent…", GOLD)
		elseif p.state == "declined" then
			showToast(tostring(p.targetName) .. " refused purification", BLOOD)
		elseif p.state == "done" and p.rite == "craft" then
			showToast("Crafted " .. tostring(p.name), GOLD)
		elseif p.state == "done" and p.rite == "offering" then
			showToast("Offered " .. tostring(p.amount) .. " mon to the kami", GOLD)
		end
	end)

	Net.onClientEvent("HaraeConsentRequest", function(payload: any)
		local p = payload :: { priestId: number, priestName: string }
		pendingPriestId = p.priestId
		if consentLabel then consentLabel.Text = (p.priestName or "A priest") .. " wishes to purify your spirit (harae)." end
		if consentPanel then consentPanel.Visible = true end
	end)

	Net.onClientEvent("PurifyFeel", function()
		purifyFeel()
	end)
end

function PriestController:Start()
	-- Attach a Misogi prompt to every MisogiZone (placeholder tagged parts per spec).
	local function addMisogiPrompt(part: Instance)
		if not part:IsA("BasePart") then return end
		if part:FindFirstChild("MisogiPrompt") then return end
		local pr = Instance.new("ProximityPrompt")
		pr.Name = "MisogiPrompt"; pr.ActionText = "Misogi"; pr.ObjectText = "Purify yourself"
		pr.HoldDuration = 0; pr.RequiresLineOfSight = false; pr.MaxActivationDistance = 12
		pr.Parent = part
	end
	for _, part in CollectionService:GetTagged(PriestConfig.TAG_MISOGI) do addMisogiPrompt(part) end
	CollectionService:GetInstanceAddedSignal(PriestConfig.TAG_MISOGI):Connect(addMisogiPrompt)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, plr: Player)
		if plr ~= player then return end
		if prompt.Name == "MisogiPrompt" then Net.fireServer("RequestMisogi", {}) end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp or not isPriest then return end
		if input.KeyCode == Enum.KeyCode.H then
			if barred then showToast("You are too polluted — purify yourself first", BLOOD); return end
			local target = getPlayerUnderMouse()
			if target then
				Net.fireServer("RequestHarae", { targetId = target.UserId })
			end
		end
	end)

	Logger.info(SCOPE, "online")
end

return PriestController
