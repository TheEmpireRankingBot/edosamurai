--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.OfferingController
-- Any player: a ProximityPrompt on a SaisenBox opens an amount picker -> RequestOffering
-- (mon is destroyed as a hard sink on the server). Shows the server Shrine Favor pool.

local Players                = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService      = game:GetService("CollectionService")
local TweenService           = game:GetService("TweenService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")

local Net          = require(ReplicatedStorage.Framework.Net)
local Logger       = require(ReplicatedStorage.Framework.Logger)
local PriestConfig = require(ReplicatedStorage.Config.PriestConfig)

local SCOPE  = "OfferingController"
local player = Players.LocalPlayer
local OfferingController = {}

local GOLD = Color3.fromRGB(210, 190, 140)
local INK  = Color3.fromRGB(14, 12, 10)

local gui:        ScreenGui?
local picker:     Frame?
local favorFill:  Frame?
local favorLabel: TextLabel?

local function build()
	if gui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "OfferingUI"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 5

	-- shrine favor bar (top center)
	local track = Instance.new("Frame")
	track.Size = UDim2.fromOffset(260, 16); track.Position = UDim2.new(0.5, 0, 0, 8); track.AnchorPoint = Vector2.new(0.5, 0)
	track.BackgroundColor3 = INK; track.BackgroundTransparency = 0.3; track.BorderSizePixel = 0; track.Parent = g
	local st = Instance.new("UIStroke"); st.Color = GOLD; st.Transparency = 0.5; st.Parent = track
	local fill = Instance.new("Frame"); fill.Size = UDim2.fromScale(0.1, 1); fill.BackgroundColor3 = Color3.fromRGB(225, 190, 90); fill.BorderSizePixel = 0; fill.Parent = track
	favorFill = fill
	local lab = Instance.new("TextLabel"); lab.Size = UDim2.fromScale(1,1); lab.BackgroundTransparency = 1
	lab.Text = "Shrine Favor"; lab.TextColor3 = Color3.fromRGB(40, 30, 20); lab.TextSize = 12; lab.Font = Enum.Font.Antique; lab.Parent = track
	favorLabel = lab

	-- amount picker
	local p = Instance.new("Frame")
	p.Size = UDim2.fromOffset(260, 120); p.Position = UDim2.fromScale(0.5, 0.5); p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.BackgroundColor3 = INK; p.BackgroundTransparency = 0.1; p.BorderSizePixel = 0; p.Visible = false; p.Parent = g
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,6); corner.Parent = p
	local stroke = Instance.new("UIStroke"); stroke.Color = GOLD; stroke.Transparency = 0.4; stroke.Parent = p
	local title = Instance.new("TextLabel"); title.Size = UDim2.new(1,0,0,28); title.BackgroundTransparency = 1
	title.Text = "Offer to the kami (saisen)"; title.TextColor3 = GOLD; title.TextSize = 15; title.Font = Enum.Font.Antique; title.Parent = p
	local amounts = { 10, 50, 100, 500 }
	for i, amt in amounts do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(110, 30)
		b.Position = UDim2.fromOffset(14 + ((i - 1) % 2) * 122, 36 + math.floor((i - 1) / 2) * 38)
		b.BackgroundColor3 = Color3.fromRGB(34, 28, 22); b.BorderSizePixel = 0
		b.Text = tostring(amt) .. " mon"; b.TextColor3 = GOLD; b.TextSize = 14; b.Font = Enum.Font.Antique; b.Parent = p
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = b
		local capAmt = amt
		b.Activated:Connect(function()
			Net.fireServer("RequestOffering", { amount = capAmt })
			p.Visible = false
		end)
	end
	picker = p

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
end

function OfferingController:Init()
	Net.onClientEvent("UpdateShrineFavor", function(payload: any)
		build()
		local p = payload :: { favor: number, max: number }
		local pct = math.clamp(p.favor / (p.max or PriestConfig.SHRINE_FAVOR_MAX), 0, 1)
		if favorFill then TweenService:Create(favorFill, TweenInfo.new(0.4), { Size = UDim2.fromScale(pct, 1) }):Play() end
		if favorLabel then favorLabel.Text = string.format("Shrine Favor  %d", math.floor(p.favor)) end
	end)
end

function OfferingController:Start()
	build()
	local function addPrompt(part: Instance)
		if not part:IsA("BasePart") then return end
		if part:FindFirstChild("SaisenPrompt") then return end
		local pr = Instance.new("ProximityPrompt")
		pr.Name = "SaisenPrompt"; pr.ActionText = "Offer"; pr.ObjectText = "Offering Box"
		pr.HoldDuration = 0; pr.RequiresLineOfSight = false; pr.MaxActivationDistance = 10
		pr.Parent = part
	end
	for _, part in CollectionService:GetTagged(PriestConfig.TAG_SAISEN) do addPrompt(part) end
	CollectionService:GetInstanceAddedSignal(PriestConfig.TAG_SAISEN):Connect(addPrompt)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, plr: Player)
		if plr ~= player then return end
		if prompt.Name == "SaisenPrompt" and picker then picker.Visible = true end
	end)

	Logger.info(SCOPE, "online")
end

return OfferingController
