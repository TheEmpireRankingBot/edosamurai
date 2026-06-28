--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.JiseiController
-- Death is meaningful. When someone falls nearby, their jisei (death poem) fades
-- across the screen like calligraphy on silk, then fades away. Players may compose
-- their own poem ahead of time (press P) so their death carries their own words.

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net    = require(ReplicatedStorage.Framework.Net)
local Logger = require(ReplicatedStorage.Framework.Logger)
local CombatConfig = require(ReplicatedStorage.Config.CombatConfig)

local SCOPE  = "JiseiController"
local player = Players.LocalPlayer

local JiseiController = {}

local INK  = Color3.fromRGB(10, 8, 7)
local GOLD = Color3.fromRGB(214, 196, 150)

-- overlay refs
local overlayGui:  ScreenGui?
local vignette:    Frame?
local poemLabel:   TextLabel?
local authorLabel: TextLabel?
local showToken    = 0
local lastPoem     = ""

-- compose refs
local composeGui:   ScreenGui?
local composeBox:   TextBox?
local composeCount: TextLabel?

-- ── Death-poem overlay ─────────────────────────────────────────────
local function buildOverlay()
	if overlayGui then return end
	local g = Instance.new("ScreenGui")
	g.Name           = "JiseiOverlay"
	g.ResetOnSpawn   = false
	g.IgnoreGuiInset = true
	g.DisplayOrder   = 9

	local v = Instance.new("Frame")
	v.Size                   = UDim2.fromScale(1, 1)
	v.BackgroundColor3       = INK
	v.BackgroundTransparency = 1
	v.BorderSizePixel        = 0
	v.Parent                 = g
	vignette = v

	local poem = Instance.new("TextLabel")
	poem.Size                   = UDim2.fromScale(0.8, 0.5)
	poem.Position               = UDim2.fromScale(0.5, 0.44)
	poem.AnchorPoint            = Vector2.new(0.5, 0.5)
	poem.BackgroundTransparency = 1
	poem.Text                   = ""
	poem.TextColor3             = GOLD
	poem.TextSize               = 34
	poem.Font                   = Enum.Font.Antique
	poem.TextTransparency       = 1
	poem.LineHeight             = 1.4
	poem.RichText               = false
	poem.Parent                 = v
	poemLabel = poem

	local author = Instance.new("TextLabel")
	author.Size                   = UDim2.fromScale(0.8, 0.08)
	author.Position               = UDim2.fromScale(0.5, 0.74)
	author.AnchorPoint            = Vector2.new(0.5, 0.5)
	author.BackgroundTransparency = 1
	author.Text                   = ""
	author.TextColor3             = Color3.fromRGB(170, 150, 110)
	author.TextSize               = 18
	author.Font                   = Enum.Font.Antique
	author.TextTransparency       = 1
	author.Parent                 = v
	authorLabel = author

	g.Parent = player:WaitForChild("PlayerGui")
	overlayGui = g
end

local function showPoem(poem: string, victimName: string)
	buildOverlay()
	if poem == "" then poem = CombatConfig.DEFAULT_JISEI end
	lastPoem = poem
	showToken += 1
	local token = showToken

	if poemLabel then poemLabel.Text = poem end
	if authorLabel then authorLabel.Text = "— " .. victimName end

	-- fade in -> hold 5s -> fade out
	local fadeIn  = TweenInfo.new(1.0, Enum.EasingStyle.Sine)
	local fadeOut = TweenInfo.new(1.5, Enum.EasingStyle.Sine)
	if vignette then TweenService:Create(vignette, fadeIn, { BackgroundTransparency = 0.5 }):Play() end
	if poemLabel then TweenService:Create(poemLabel, fadeIn, { TextTransparency = 0 }):Play() end
	if authorLabel then TweenService:Create(authorLabel, fadeIn, { TextTransparency = 0.1 }):Play() end

	task.delay(6.0, function()
		if showToken ~= token then return end  -- a newer death overrode this one
		if vignette then TweenService:Create(vignette, fadeOut, { BackgroundTransparency = 1 }):Play() end
		if poemLabel then TweenService:Create(poemLabel, fadeOut, { TextTransparency = 1 }):Play() end
		if authorLabel then TweenService:Create(authorLabel, fadeOut, { TextTransparency = 1 }):Play() end
	end)
end

-- ── Compose-your-poem panel ────────────────────────────────────────
local function buildCompose()
	if composeGui then return end
	local g = Instance.new("ScreenGui")
	g.Name           = "JiseiCompose"
	g.ResetOnSpawn   = false
	g.IgnoreGuiInset = true
	g.DisplayOrder   = 6
	g.Enabled        = false

	local panel = Instance.new("Frame")
	panel.Size             = UDim2.fromOffset(420, 260)
	panel.Position         = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint      = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(18, 14, 11)
	panel.BorderSizePixel  = 0
	panel.Parent           = g
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = panel
	local stroke = Instance.new("UIStroke"); stroke.Color = GOLD; stroke.Transparency = 0.5; stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Text                   = "Compose your death poem"
	title.TextColor3             = GOLD
	title.TextSize               = 20
	title.Font                   = Enum.Font.Antique
	title.Parent                 = panel

	local box = Instance.new("TextBox")
	box.Size                   = UDim2.new(1, -32, 0, 130)
	box.Position               = UDim2.fromOffset(16, 48)
	box.BackgroundColor3       = Color3.fromRGB(28, 22, 18)
	box.BorderSizePixel        = 0
	box.Text                   = ""
	box.PlaceholderText        = "Three lines, if you can…"
	box.TextColor3             = Color3.fromRGB(220, 205, 165)
	box.TextSize               = 16
	box.Font                   = Enum.Font.Antique
	box.TextWrapped            = true
	box.TextYAlignment         = Enum.TextYAlignment.Top
	box.MultiLine              = true
	box.ClearTextOnFocus       = false
	box.Parent                 = panel
	composeBox = box

	local count = Instance.new("TextLabel")
	count.Size                   = UDim2.fromOffset(120, 20)
	count.Position               = UDim2.fromOffset(16, 186)
	count.BackgroundTransparency = 1
	count.Text                   = "0 / " .. CombatConfig.JISEI_MAX_CHARS
	count.TextColor3             = Color3.fromRGB(150, 135, 100)
	count.TextSize               = 14
	count.Font                   = Enum.Font.Antique
	count.TextXAlignment         = Enum.TextXAlignment.Left
	count.Parent                 = panel
	composeCount = count

	local function makeBtn(text: string, x: number, color: Color3): TextButton
		local b = Instance.new("TextButton")
		b.Size             = UDim2.fromOffset(120, 36)
		b.Position         = UDim2.fromOffset(x, 212)
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

	local saveBtn  = makeBtn("Inscribe", 16,  GOLD)
	local closeBtn = makeBtn("Close",    284, Color3.fromRGB(170, 120, 110))

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > CombatConfig.JISEI_MAX_CHARS then
			box.Text = string.sub(box.Text, 1, CombatConfig.JISEI_MAX_CHARS)
		end
		if composeCount then composeCount.Text = #box.Text .. " / " .. CombatConfig.JISEI_MAX_CHARS end
	end)

	saveBtn.Activated:Connect(function()
		Net.fireServer("RequestSetJisei", { poem = box.Text })
		Logger.info(SCOPE, "Submitted jisei (" .. #box.Text .. " chars)")
		g.Enabled = false
	end)
	closeBtn.Activated:Connect(function() g.Enabled = false end)

	g.Parent = player:WaitForChild("PlayerGui")
	composeGui = g
end

local function toggleCompose()
	buildCompose()
	if composeGui then composeGui.Enabled = not composeGui.Enabled end
end

function JiseiController:Init()
	Net.onClientEvent("ShowJiseiPoem", function(payload: any)
		local p = payload :: { poem: string, victimName: string }
		showPoem(p.poem or "", p.victimName or "Unknown")
	end)
end

function JiseiController:Start()
	buildOverlay()
	buildCompose()
	UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.P then
			toggleCompose()
		end
	end)
end

return JiseiController
