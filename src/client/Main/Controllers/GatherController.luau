--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.GatherController
-- ProximityPrompt on a gather node -> RequestGather; shows a gather progress bar.

local Players                = game:GetService("Players")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService           = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Framework.Net)

local player = Players.LocalPlayer
local GatherController = {}

local gui:    ScreenGui?
local fill:   Frame?
local label:  TextLabel?
local status: TextLabel?
local busy = false
local activeTween: Tween?

local function ensure()
	if gui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "GatherUI"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 4

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.fromScale(0.5, 0.86)
	bar.Size = UDim2.fromOffset(260, 22)
	bar.BackgroundColor3 = Color3.fromRGB(20, 16, 12)
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = g

	local f = Instance.new("Frame")
	f.Name = "Fill"
	f.Size = UDim2.fromScale(0, 1)
	f.BackgroundColor3 = Color3.fromRGB(90, 160, 90)
	f.BorderSizePixel = 0
	f.Parent = bar
	fill = f

	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(235, 230, 210)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 13
	l.Text = ""
	l.Parent = bar
	label = l

	local s = Instance.new("TextLabel")
	s.Name = "Status"
	s.AnchorPoint = Vector2.new(0.5, 1)
	s.Position = UDim2.fromScale(0.5, 0.80)
	s.Size = UDim2.fromOffset(300, 20)
	s.BackgroundTransparency = 1
	s.TextColor3 = Color3.fromRGB(220, 210, 180)
	s.Font = Enum.Font.Gotham
	s.TextSize = 14
	s.Text = ""
	s.Parent = g
	status = s

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
end

local function showBar(seconds: number, name: string)
	ensure()
	if fill then fill.Size = UDim2.fromScale(0, 1) end
	if label then label.Text = "Gathering " .. name .. "..." end
	local bar = gui and gui:FindFirstChild("Bar") :: Frame?
	if bar then bar.Visible = true end
	if activeTween then activeTween:Cancel() end
	if fill then
		local tw = TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 1) })
		activeTween = tw
		tw:Play()
	end
end

local function hideBar()
	local bar = gui and gui:FindFirstChild("Bar") :: Frame?
	if bar then bar.Visible = false end
	if activeTween then activeTween:Cancel(); activeTween = nil end
end

function GatherController:Init()
	Net.onClientEvent("RequestGather", function(payload: any)
		local p = payload :: { ok: boolean, msg: string }
		busy = false
		hideBar()
		if status then status.Text = tostring(p.msg) end
	end)
end

function GatherController:Start()
	ensure()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, plr: Player)
		if plr ~= player then return end
		if prompt.Name ~= "GatherPrompt" then return end
		if busy then return end
		local node = prompt.Parent
		if not node or not node:IsA("BasePart") then return end
		busy = true
		local gt = node:GetAttribute("GatherTime")
		local seconds = (type(gt) == "number") and gt or 3
		showBar(seconds, prompt.ObjectText)
		Net.fireServer("RequestGather", node)
	end)
end

return GatherController
