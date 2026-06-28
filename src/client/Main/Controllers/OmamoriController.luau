--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.OmamoriController
-- Any player: open the charm pouch (O) to apply an owned omamori, and watch active
-- buff timers tick down. The server enforces ownership (apply fails if not owned).

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net          = require(ReplicatedStorage.Framework.Net)
local Logger       = require(ReplicatedStorage.Framework.Logger)
local PriestConfig = require(ReplicatedStorage.Config.PriestConfig)

local SCOPE  = "OmamoriController"
local player = Players.LocalPlayer
local OmamoriController = {}

local GOLD = Color3.fromRGB(210, 190, 140)
local JADE = Color3.fromRGB(150, 205, 175)
local INK  = Color3.fromRGB(14, 12, 10)

local gui:        ScreenGui?
local buffsHolder: Frame?
local activeBuffs: { { name: string, expiresAt: number, label: TextLabel } } = {}

local function build()
	if gui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "OmamoriUI"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 5

	-- pouch panel (toggle with O)
	local panel = Instance.new("Frame")
	panel.Name = "Pouch"
	panel.Size = UDim2.fromOffset(260, 200); panel.Position = UDim2.fromScale(0.5, 0.5); panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = INK; panel.BackgroundTransparency = 0.1; panel.BorderSizePixel = 0
	panel.Visible = false; panel.Parent = g
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,6); corner.Parent = panel
	local stroke = Instance.new("UIStroke"); stroke.Color = GOLD; stroke.Transparency = 0.5; stroke.Parent = panel
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1,0,0,30); title.BackgroundTransparency = 1; title.Text = "Charm Pouch (O)"
	title.TextColor3 = GOLD; title.TextSize = 16; title.Font = Enum.Font.Antique; title.Parent = panel
	local list = Instance.new("UIListLayout"); list.Padding = UDim.new(0,4); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = panel
	local lp = Instance.new("UIPadding"); lp.PaddingTop = UDim.new(0,34); lp.PaddingLeft = UDim.new(0,10); lp.PaddingRight = UDim.new(0,10); lp.Parent = panel
	local order = 1
	for id, om in PriestConfig.Omamori do
		local b = Instance.new("TextButton")
		b.LayoutOrder = order; b.Size = UDim2.new(1,0,0,28); b.BackgroundColor3 = Color3.fromRGB(34,28,22); b.BorderSizePixel = 0
		b.Text = "Apply " .. om.name; b.TextColor3 = GOLD; b.TextSize = 12; b.Font = Enum.Font.Antique; b.Parent = panel
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = b
		local capId = id
		b.Activated:Connect(function() Net.fireServer("RequestApplyOmamori", { id = capId }) end)
		order += 1
	end

	-- active-buff strip (top-right under HUD)
	local holder = Instance.new("Frame")
	holder.Name = "Buffs"; holder.Size = UDim2.fromOffset(220, 120); holder.Position = UDim2.new(1, -228, 0, 140)
	holder.BackgroundTransparency = 1; holder.Parent = g
	local hl = Instance.new("UIListLayout"); hl.Padding = UDim.new(0,2); hl.HorizontalAlignment = Enum.HorizontalAlignment.Right; hl.Parent = holder
	buffsHolder = holder

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
end

local function rebuildBuffs(buffs: { any })
	if buffsHolder == nil then return end
	for _, e in activeBuffs do if e.label then e.label:Destroy() end end
	activeBuffs = {}
	for _, b in buffs do
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromOffset(220, 18); lbl.BackgroundColor3 = INK; lbl.BackgroundTransparency = 0.4; lbl.BorderSizePixel = 0
		lbl.TextColor3 = JADE; lbl.TextSize = 13; lbl.Font = Enum.Font.Antique; lbl.TextXAlignment = Enum.TextXAlignment.Right
		lbl.Parent = buffsHolder
		table.insert(activeBuffs, { name = b.name, expiresAt = os.clock() + (b.remaining or 0), label = lbl })
	end
end

function OmamoriController:Init()
	Net.onClientEvent("OmamoriUpdate", function(payload: any)
		build()
		rebuildBuffs((payload :: any).buffs or {})
	end)
end

function OmamoriController:Start()
	build()
	game:GetService("UserInputService").InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.O then
			local pouch = gui and gui:FindFirstChild("Pouch") :: Frame?
			if pouch then pouch.Visible = not pouch.Visible end
		end
	end)

	-- tick buff timers
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for i = #activeBuffs, 1, -1 do
			local e = activeBuffs[i]
			local remaining = e.expiresAt - now
			if remaining <= 0 then
				if e.label then e.label:Destroy() end
				table.remove(activeBuffs, i)
			else
				e.label.Text = string.format("%s  %ds", e.name, math.ceil(remaining))
			end
		end
	end)

	Logger.info(SCOPE, "online")
end

return OmamoriController
