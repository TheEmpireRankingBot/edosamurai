--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.DisasterController
-- Server-wide disaster banners + the priest's quelling-ritual QTE. The priest stands
-- on the ShrineGround, begins the rite, and presses SPACE on each beat; the SERVER
-- validates the timing of every step (a spoofed instant 'done' is rejected). Everyone
-- else can contribute by offering (see OfferingController) to boost the priest's odds.

local Players                = game:GetService("Players")
local RunService             = game:GetService("RunService")
local UserInputService       = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService      = game:GetService("CollectionService")
local TweenService           = game:GetService("TweenService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")

local Net          = require(ReplicatedStorage.Framework.Net)
local Logger       = require(ReplicatedStorage.Framework.Logger)
local PriestConfig = require(ReplicatedStorage.Config.PriestConfig)

local SCOPE  = "DisasterController"
local player = Players.LocalPlayer
local DisasterController = {}

local GOLD  = Color3.fromRGB(210, 190, 140)
local INK   = Color3.fromRGB(14, 12, 10)
local GREEN = Color3.fromRGB(120, 200, 130)
local RED   = Color3.fromRGB(200, 90, 80)

local gui:        ScreenGui?
local banner:     TextLabel?
local ritualPanel: Frame?
local playhead:   Frame?
local pips:       { Frame } = {}
local resultLabel: TextLabel?

-- ritual runtime
local active   = false
local localStep = 0
local totalSteps = 0
local leadIn, interval, sweepEnd = 0, 0, 1
local t0 = 0

local function build()
	if gui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "DisasterUI"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 7

	local b = Instance.new("TextLabel")
	b.Size = UDim2.fromOffset(720, 40); b.Position = UDim2.fromScale(0.5, 0.12); b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.BackgroundTransparency = 1; b.Text = ""; b.TextColor3 = RED; b.TextSize = 26; b.Font = Enum.Font.Antique
	b.TextTransparency = 1; b.Parent = g
	banner = b

	-- ritual panel (priest QTE)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(520, 120); panel.Position = UDim2.fromScale(0.5, 0.82); panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = INK; panel.BackgroundTransparency = 0.15; panel.BorderSizePixel = 0
	panel.Visible = false; panel.Parent = g
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,6); corner.Parent = panel
	local stroke = Instance.new("UIStroke"); stroke.Color = GOLD; stroke.Transparency = 0.4; stroke.Parent = panel
	local title = Instance.new("TextLabel"); title.Size = UDim2.new(1,0,0,24); title.Position = UDim2.fromOffset(0,6)
	title.BackgroundTransparency = 1; title.Text = "Quelling Rite — strike SPACE on each beat"; title.TextColor3 = GOLD; title.TextSize = 15; title.Font = Enum.Font.Antique; title.Parent = panel

	-- timeline
	local track = Instance.new("Frame")
	track.Size = UDim2.fromOffset(480, 8); track.Position = UDim2.fromOffset(20, 64); track.BackgroundColor3 = Color3.fromRGB(40,32,26); track.BorderSizePixel = 0; track.Parent = panel
	local ph = Instance.new("Frame"); ph.Size = UDim2.fromOffset(3, 28); ph.Position = UDim2.fromScale(0,0.5); ph.AnchorPoint = Vector2.new(0.5,0.5); ph.BackgroundColor3 = Color3.fromRGB(240,230,200); ph.BorderSizePixel = 0; ph.Parent = track
	playhead = ph
	resultLabel = title
	ritualPanel = panel

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
end

local function showBanner(text: string, color: Color3)
	build()
	if banner == nil then return end
	banner.Text = text; banner.TextColor3 = color; banner.TextTransparency = 0
	task.delay(3.5, function()
		if banner and banner.Text == text then
			TweenService:Create(banner, TweenInfo.new(1.5), { TextTransparency = 1 }):Play()
		end
	end)
end

local function layoutPips(track: Frame)
	for _, p in pips do p:Destroy() end
	pips = {}
	for i = 0, totalSteps - 1 do
		local beatAt = leadIn + i * interval
		local x = math.clamp(beatAt / sweepEnd, 0, 1)
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromOffset(14, 14); pip.AnchorPoint = Vector2.new(0.5, 0.5)
		pip.Position = UDim2.fromScale(x, 0.5); pip.BackgroundColor3 = GOLD; pip.BackgroundTransparency = 0.3; pip.BorderSizePixel = 0
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = pip
		pip.Parent = track
		table.insert(pips, pip)
	end
end

local function endRitual()
	active = false
	if ritualPanel then
		task.delay(1.6, function() if ritualPanel and not active then ritualPanel.Visible = false end end)
	end
end

function DisasterController:Init()
	Net.onClientEvent("DisasterStarted", function(payload: any)
		local p = payload :: { name: string, description: string }
		showBanner("⚠ " .. tostring(p.name) .. " — " .. tostring(p.description), RED)
	end)

	Net.onClientEvent("DisasterQuelled", function(payload: any)
		local p = payload :: { name: string, by: string }
		showBanner("⛩ " .. tostring(p.name) .. " is quelled — the bells ring true! (" .. tostring(p.by) .. ")", GREEN)
	end)

	Net.onClientEvent("RitualState", function(payload: any)
		local p = payload :: any
		if p.state == "reject" then
			showBanner(tostring(p.reason), RED)
		elseif p.state == "begin" then
			build()
			totalSteps = p.totalSteps; leadIn = p.leadIn; interval = p.stepInterval
			sweepEnd = leadIn + totalSteps * interval
			localStep = 0; t0 = os.clock(); active = true
			if resultLabel then resultLabel.Text = "Quelling Rite — strike SPACE on each beat"; resultLabel.TextColor3 = GOLD end
			local track = ritualPanel and ritualPanel:FindFirstChildWhichIsA("Frame")
			if track then layoutPips(track) end
			if ritualPanel then ritualPanel.Visible = true end
		elseif p.state == "step" then
			local pip = pips[(p.stepId or 0) + 1]
			if pip then pip.BackgroundColor3 = p.hit and GREEN or RED; pip.BackgroundTransparency = 0 end
		elseif p.state == "result" then
			if resultLabel then
				resultLabel.Text = p.success
					and string.format("The rite holds! (%d hits)", p.hits or 0)
					or string.format("The rite falters… (%d/%d) — try again", p.hits or 0, p.required or 0)
				resultLabel.TextColor3 = p.success and GREEN or RED
			end
			endRitual()
		end
	end)
end

function DisasterController:Start()
	build()

	-- ShrineGround prompt -> begin the quelling rite (server rejects non-priests / no disaster)
	local function addPrompt(part: Instance)
		if not part:IsA("BasePart") then return end
		if part:FindFirstChild("QuellPrompt") then return end
		local pr = Instance.new("ProximityPrompt")
		pr.Name = "QuellPrompt"; pr.ActionText = "Quell"; pr.ObjectText = "Begin the rite"
		pr.HoldDuration = 0; pr.RequiresLineOfSight = false; pr.MaxActivationDistance = 12
		pr.Parent = part
	end
	for _, part in CollectionService:GetTagged(PriestConfig.TAG_SHRINE_GROUND) do addPrompt(part) end
	CollectionService:GetInstanceAddedSignal(PriestConfig.TAG_SHRINE_GROUND):Connect(addPrompt)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, plr: Player)
		if plr ~= player then return end
		if prompt.Name == "QuellPrompt" then Net.fireServer("RequestQuellRitual", {}) end
	end)

	-- SPACE strikes the current beat; the SERVER scores it against its own clock.
	UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp or not active then return end
		if input.KeyCode == Enum.KeyCode.Space and localStep < totalSteps then
			Net.fireServer("SubmitRitualStep", { stepId = localStep, timing = os.clock() - t0 })
			localStep += 1
		end
	end)

	-- sweep the playhead across the timeline while a rite is active
	RunService.Heartbeat:Connect(function()
		if not active or playhead == nil then return end
		local x = math.clamp((os.clock() - t0) / sweepEnd, 0, 1)
		playhead.Position = UDim2.fromScale(x, 0.5)
	end)

	Logger.info(SCOPE, "online")
end

return DisasterController
