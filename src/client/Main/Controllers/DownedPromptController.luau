--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.DownedPromptController
-- The moral fulcrum of the game. When the server says you have downed someone, it
-- offers two paths: 斬 EXECUTE (Shura — power, corruption) or 赦 SPARE (Gi — honor).
-- The UI is built to make the weight of that choice FELT: execute is heavy and
-- ominous, spare is calm. A countdown forces a decision; silence defaults to mercy.

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net    = require(ReplicatedStorage.Framework.Net)
local Logger = require(ReplicatedStorage.Framework.Logger)

local SCOPE  = "DownedPromptController"
local player = Players.LocalPlayer

local DownedPromptController = {}

local gui:        ScreenGui?
local backdrop:   Frame?
local titleLabel: TextLabel?
local timerBar:   Frame?
local timerLabel: TextLabel?
local execBtn:    TextButton?
local spareBtn:   TextButton?
local activeToken = 0

local function makeChoiceButton(parent: Instance, side: number, kanji: string, word: string, color: Color3): TextButton
	local btn = Instance.new("TextButton")
	btn.Size                  = UDim2.fromOffset(190, 200)
	btn.Position              = UDim2.fromScale(0.5 + side * 0.16, 0.5)
	btn.AnchorPoint           = Vector2.new(0.5, 0.5)
	btn.BackgroundColor3      = Color3.fromRGB(16, 13, 11)
	btn.BorderSizePixel       = 0
	btn.AutoButtonColor       = false
	btn.Text                  = ""
	btn.Parent                = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent       = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color     = color
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent    = btn

	local k = Instance.new("TextLabel")
	k.Size                   = UDim2.fromScale(1, 0.6)
	k.BackgroundTransparency = 1
	k.Text                   = kanji
	k.TextColor3             = color
	k.TextSize               = 96
	k.Font                   = Enum.Font.Antique
	k.Parent                 = btn

	local w = Instance.new("TextLabel")
	w.Size                   = UDim2.fromScale(1, 0.3)
	w.Position               = UDim2.fromScale(0, 0.66)
	w.BackgroundTransparency = 1
	w.Text                   = word
	w.TextColor3             = color
	w.TextSize               = 24
	w.Font                   = Enum.Font.Antique
	w.Parent                 = btn

	-- hover swell
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), { Size = UDim2.fromOffset(202, 214) }):Play()
		stroke.Transparency = 0
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), { Size = UDim2.fromOffset(190, 200) }):Play()
		stroke.Transparency = 0.2
	end)
	return btn
end

local function build()
	if gui then return end
	local g = Instance.new("ScreenGui")
	g.Name           = "DownedPrompt"
	g.ResetOnSpawn   = false
	g.IgnoreGuiInset = true
	g.DisplayOrder   = 8
	g.Enabled        = false

	-- heavy modal backdrop
	local bd = Instance.new("Frame")
	bd.Size                   = UDim2.fromScale(1, 1)
	bd.BackgroundColor3       = Color3.fromRGB(8, 4, 4)
	bd.BackgroundTransparency = 1
	bd.BorderSizePixel        = 0
	bd.Parent                 = g
	backdrop = bd

	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.fromOffset(700, 40)
	title.Position               = UDim2.fromScale(0.5, 0.3)
	title.AnchorPoint            = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Text                   = ""
	title.TextColor3             = Color3.fromRGB(210, 190, 140)
	title.TextSize               = 26
	title.Font                   = Enum.Font.Antique
	title.Parent                 = bd
	titleLabel = title

	execBtn  = makeChoiceButton(bd, -1, "斬", "EXECUTE", Color3.fromRGB(170, 32, 28))
	spareBtn = makeChoiceButton(bd,  1, "赦", "SPARE",   Color3.fromRGB(120, 165, 130))

	-- countdown: depleting bar + number between the two paths
	local track = Instance.new("Frame")
	track.Size             = UDim2.fromOffset(280, 6)
	track.Position         = UDim2.fromScale(0.5, 0.68)
	track.AnchorPoint      = Vector2.new(0.5, 0.5)
	track.BackgroundColor3 = Color3.fromRGB(40, 30, 26)
	track.BorderSizePixel  = 0
	track.Parent           = bd
	local fill = Instance.new("Frame")
	fill.Size             = UDim2.fromScale(1, 1)
	fill.AnchorPoint      = Vector2.new(0.5, 0.5)
	fill.Position         = UDim2.fromScale(0.5, 0.5)
	fill.BackgroundColor3 = Color3.fromRGB(190, 150, 90)
	fill.BorderSizePixel  = 0
	fill.Parent           = track
	timerBar = fill

	local tl = Instance.new("TextLabel")
	tl.Size                   = UDim2.fromOffset(80, 28)
	tl.Position               = UDim2.fromScale(0.5, 0.72)
	tl.AnchorPoint            = Vector2.new(0.5, 0.5)
	tl.BackgroundTransparency = 1
	tl.Text                   = ""
	tl.TextColor3             = Color3.fromRGB(200, 180, 130)
	tl.TextSize               = 20
	tl.Font                   = Enum.Font.Antique
	tl.Parent                 = bd
	timerLabel = tl

	execBtn.Activated:Connect(function()
		Net.fireServer("RequestExecuteOrSpare", { choice = "execute" })
		Logger.info(SCOPE, "Chose EXECUTE")
		DownedPromptController.hide()
	end)
	spareBtn.Activated:Connect(function()
		Net.fireServer("RequestExecuteOrSpare", { choice = "spare" })
		Logger.info(SCOPE, "Chose SPARE")
		DownedPromptController.hide()
	end)

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
end

function DownedPromptController.hide()
	activeToken += 1
	if gui then gui.Enabled = false end
end

function DownedPromptController.show(victimName: string, duration: number)
	build()
	activeToken += 1
	local token = activeToken
	if titleLabel then titleLabel.Text = victimName .. " lies broken at your feet." end
	if gui then gui.Enabled = true end
	if backdrop then
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, TweenInfo.new(0.4), { BackgroundTransparency = 0.45 }):Play()
	end

	task.spawn(function()
		local start = os.clock()
		while activeToken == token do
			local remaining = math.max(0, duration - (os.clock() - start))
			if timerLabel then timerLabel.Text = string.format("%d", math.ceil(remaining)) end
			if timerBar then timerBar.Size = UDim2.fromScale(math.clamp(remaining / duration, 0, 1), 1) end
			if remaining <= 0 then
				-- silence is mercy: the server auto-spares
				DownedPromptController.hide()
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

function DownedPromptController:Init()
	Net.onClientEvent("ShowDownedPrompt", function(payload: any)
		local p = payload :: { victimName: string, duration: number }
		DownedPromptController.show(p.victimName or "Your foe", p.duration or 10)
	end)
end

function DownedPromptController:Start() end

return DownedPromptController
