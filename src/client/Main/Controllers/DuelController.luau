--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.DuelController
-- Sanctioned duels are how lethal fights happen without griefing. Point at a player
-- and press T to challenge them; they get an accept/decline popup. The server owns
-- all duel state — this only sends requests and shows banners.

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net    = require(ReplicatedStorage.Framework.Net)
local Logger = require(ReplicatedStorage.Framework.Logger)

local SCOPE  = "DuelController"
local player = Players.LocalPlayer

local DuelController = {}

local GOLD = Color3.fromRGB(210, 190, 140)
local INK  = Color3.fromRGB(16, 13, 10)

local gui:         ScreenGui?
local invitePanel: Frame?
local inviteLabel: TextLabel?
local banner:      TextLabel?
local pendingChallengerId: number?

local function build()
	if gui then return end
	local g = Instance.new("ScreenGui")
	g.Name           = "DuelGui"
	g.ResetOnSpawn   = false
	g.IgnoreGuiInset = true
	g.DisplayOrder   = 5

	-- invite popup (top centre)
	local panel = Instance.new("Frame")
	panel.Size             = UDim2.fromOffset(380, 96)
	panel.Position         = UDim2.new(0.5, 0, 0, 16)
	panel.AnchorPoint      = Vector2.new(0.5, 0)
	panel.BackgroundColor3 = INK
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel  = 0
	panel.Visible          = false
	panel.Parent           = g
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = panel
	local stroke = Instance.new("UIStroke"); stroke.Color = GOLD; stroke.Transparency = 0.4; stroke.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, -16, 0, 40)
	label.Position               = UDim2.fromOffset(8, 8)
	label.BackgroundTransparency = 1
	label.Text                   = ""
	label.TextColor3             = GOLD
	label.TextSize               = 17
	label.Font                   = Enum.Font.Antique
	label.TextWrapped            = true
	label.Parent                 = panel
	inviteLabel = label

	local function mkBtn(text: string, x: number, color: Color3): TextButton
		local b = Instance.new("TextButton")
		b.Size             = UDim2.fromOffset(170, 34)
		b.Position         = UDim2.fromOffset(x, 54)
		b.BackgroundColor3 = Color3.fromRGB(34, 26, 20)
		b.BorderSizePixel  = 0
		b.Text             = text
		b.TextColor3       = color
		b.TextSize         = 16
		b.Font             = Enum.Font.Antique
		b.Parent           = panel
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = b
		return b
	end

	local acceptBtn  = mkBtn("Accept (受)", 10,  Color3.fromRGB(150, 190, 150))
	local declineBtn = mkBtn("Decline",    200, Color3.fromRGB(190, 140, 130))

	acceptBtn.Activated:Connect(function()
		if pendingChallengerId then
			Net.fireServer("AcceptDuel", { challengerId = pendingChallengerId })
			Logger.info(SCOPE, "Accepted duel from " .. tostring(pendingChallengerId))
		end
		panel.Visible = false
		pendingChallengerId = nil
	end)
	declineBtn.Activated:Connect(function()
		panel.Visible = false
		pendingChallengerId = nil
	end)
	invitePanel = panel

	-- banner (transient, just under the top)
	local b = Instance.new("TextLabel")
	b.Size                   = UDim2.fromOffset(500, 30)
	b.Position               = UDim2.new(0.5, 0, 0, 120)
	b.AnchorPoint            = Vector2.new(0.5, 0)
	b.BackgroundTransparency = 1
	b.Text                   = ""
	b.TextColor3             = GOLD
	b.TextSize               = 22
	b.Font                   = Enum.Font.Antique
	b.TextTransparency       = 1
	b.Parent                 = g
	banner = b

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
end

local function showBanner(text: string, color: Color3)
	if banner == nil then return end
	banner.Text            = text
	banner.TextColor3      = color
	banner.TextTransparency = 0
	TweenService:Create(banner, TweenInfo.new(2.5, Enum.EasingStyle.Sine), { TextTransparency = 1 }):Play()
end

local function getTargetUnderMouse(): Player?
	local mouse  = player:GetMouse()
	local target = mouse.Target
	if target == nil then return nil end
	local model = target:FindFirstAncestorOfClass("Model")
	if model == nil then return nil end
	local other = Players:GetPlayerFromCharacter(model)
	if other == nil or other == player then return nil end
	return other
end

function DuelController:Init()
	Net.onClientEvent("ShowDuelInvite", function(payload: any)
		local p = payload :: { challengerId: number, challengerName: string }
		pendingChallengerId = p.challengerId
		if inviteLabel then
			inviteLabel.Text = (p.challengerName or "Someone") .. " challenges you to a duel."
		end
		if invitePanel then invitePanel.Visible = true end
	end)

	Net.onClientEvent("DuelStarted", function(payload: any)
		local p = payload :: { opponentName: string }
		showBanner("Duel begins — vs " .. (p.opponentName or "?"), GOLD)
	end)

	Net.onClientEvent("DuelEnded", function(payload: any)
		local p = payload :: { reason: string, won: boolean }
		local verb = p.won and "You prevailed" or "You fell"
		showBanner(string.format("%s (%s)", verb, tostring(p.reason)), p.won and GOLD or Color3.fromRGB(190, 120, 110))
	end)
end

function DuelController:Start()
	build()
	UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.T then
			local target = getTargetUnderMouse()
			if target then
				Net.fireServer("RequestDuel", { targetId = target.UserId })
				showBanner("Challenge sent to " .. target.Name, GOLD)
				Logger.info(SCOPE, "Challenged " .. target.Name)
			end
		end
	end)
end

return DuelController
