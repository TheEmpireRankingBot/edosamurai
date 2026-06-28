--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.FactionSelectController
-- Full-screen faction picker. Shown when the server fires "ShowFactionSelect" (new
-- player, no faction) OR when a Start-time GetFactionStatus query reports no faction
-- (race-free fallback). Closes when the server confirms via "UpdateFactionDisplay".

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Net         = require(ReplicatedStorage.Framework.Net)
local Logger      = require(ReplicatedStorage.Framework.Logger)
local FactionDefs = require(ReplicatedStorage.Config.FactionDefs)

local SCOPE  = "FactionSelectController"
local player = Players.LocalPlayer

local FactionSelectController = {}

type Card = { name: string, kanji: string, tagline: string, color: Color3 }
local FACTIONS: { Card } = {
	{ name = "Samurai",  kanji = "\230\173\166\229\163\171", tagline = "Honor-bound blade",      color = Color3.fromRGB(150, 40, 40) },
	{ name = "Merchant", kanji = "\229\149\134\228\186\186", tagline = "Wealthy outsider",       color = Color3.fromRGB(180, 140, 40) },
	{ name = "Civilian", kanji = "\229\186\182\230\176\145", tagline = "Backbone of the realm",  color = Color3.fromRGB(70, 120, 70) },
	{ name = "Priest",   kanji = "\231\165\158\228\184\187", tagline = "Warden of the boundary", color = Color3.fromRGB(90, 90, 160) },
}

local TIMEOUT = 5  -- seconds: re-enable buttons if the server never answers

local gui: ScreenGui?
local buttons: { TextButton } = {}
local pending = false
local selectToken = 0  -- invalidates stale timeouts

local function setEnabled(enabled: boolean)
	for _, btn in buttons do
		btn.Active = enabled
		btn.AutoButtonColor = enabled
		btn.Text = "SELECT"
		btn.BackgroundColor3 = enabled and Color3.fromRGB(40, 32, 22) or Color3.fromRGB(26, 22, 16)
		btn.TextTransparency = enabled and 0 or 0.4
	end
end

local function onSelect(name: string, btn: TextButton)
	if pending then return end
	pending = true
	selectToken += 1
	local myToken = selectToken
	setEnabled(false)
	btn.Text = "..."
	Logger.info(SCOPE, "Requesting faction: " .. name)
	Net.fireServer("RequestFactionSelect", { faction = name })

	-- Never soft-lock: if the server does not confirm within TIMEOUT, re-enable.
	task.delay(TIMEOUT, function()
		if pending and myToken == selectToken and gui ~= nil then
			pending = false
			setEnabled(true)
			Logger.warn(SCOPE, "No confirm within " .. TIMEOUT .. "s — re-enabled buttons")
		end
	end)
end

local function makeCard(parent: Instance, card: Card, order: number)
	local frame = Instance.new("Frame")
	frame.Name = card.name
	frame.LayoutOrder = order
	frame.Size = UDim2.fromOffset(200, 320)
	frame.BackgroundColor3 = Color3.fromRGB(22, 18, 13)
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local strip = Instance.new("Frame")
	strip.Size = UDim2.new(1, 0, 0, 8)
	strip.BackgroundColor3 = card.color
	strip.BorderSizePixel = 0
	strip.Parent = frame

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, 0, 0, 28)
	nameLbl.Position = UDim2.fromOffset(0, 18)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = card.name
	nameLbl.TextColor3 = Color3.fromRGB(235, 220, 180)
	nameLbl.Font = Enum.Font.Antique
	nameLbl.TextSize = 22
	nameLbl.Parent = frame

	local kanjiLbl = Instance.new("TextLabel")
	kanjiLbl.Size = UDim2.new(1, 0, 0, 56)
	kanjiLbl.Position = UDim2.fromOffset(0, 50)
	kanjiLbl.BackgroundTransparency = 1
	kanjiLbl.Text = card.kanji
	kanjiLbl.TextColor3 = card.color
	kanjiLbl.Font = Enum.Font.Antique
	kanjiLbl.TextSize = 44
	kanjiLbl.Parent = frame

	local tagLbl = Instance.new("TextLabel")
	tagLbl.Size = UDim2.new(1, -20, 0, 48)
	tagLbl.Position = UDim2.fromOffset(10, 120)
	tagLbl.BackgroundTransparency = 1
	tagLbl.Text = card.tagline
	tagLbl.TextColor3 = Color3.fromRGB(200, 190, 165)
	tagLbl.Font = Enum.Font.Gotham
	tagLbl.TextSize = 15
	tagLbl.TextWrapped = true
	tagLbl.Parent = frame

	local def = FactionDefs.get(card.name)
	local startMon = def and def.startingMon or 0
	local monLbl = Instance.new("TextLabel")
	monLbl.Size = UDim2.new(1, -20, 0, 22)
	monLbl.Position = UDim2.fromOffset(10, 188)
	monLbl.BackgroundTransparency = 1
	monLbl.Text = string.format("Starting: %d mon", startMon)
	monLbl.TextColor3 = Color3.fromRGB(220, 200, 120)
	monLbl.Font = Enum.Font.GothamMedium
	monLbl.TextSize = 14
	monLbl.Parent = frame

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -24, 0, 44)
	btn.Position = UDim2.new(0, 12, 1, -56)
	btn.BackgroundColor3 = Color3.fromRGB(40, 32, 22)
	btn.BorderSizePixel = 0
	btn.Text = "SELECT"
	btn.TextColor3 = Color3.fromRGB(235, 225, 195)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.Parent = frame
	btn.Activated:Connect(function() onSelect(card.name, btn) end)
	table.insert(buttons, btn)
end

local function build()
	-- Always rebuild fresh so a respawn mid-selection can never leave a stale modal.
	if gui then gui:Destroy() end
	table.clear(buttons)
	pending = false

	local g = Instance.new("ScreenGui")
	g.Name = "FactionSelectGui"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 100

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = g

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.58)
	container.Size = UDim2.fromOffset(884, 440)
	container.BackgroundTransparency = 1
	container.Parent = backdrop

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Text = "Choose Your Path"
	title.TextColor3 = Color3.fromRGB(230, 210, 150)
	title.Font = Enum.Font.Antique
	title.TextSize = 30
	title.Parent = container

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, 0, 0, 22)
	subtitle.Position = UDim2.fromOffset(0, 40)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "This choice shapes your life in Edo. It cannot be undone."
	subtitle.TextColor3 = Color3.fromRGB(180, 165, 135)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 14
	subtitle.Parent = container

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 320)
	row.Position = UDim2.fromOffset(0, 80)
	row.BackgroundTransparency = 1
	row.Parent = container
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 28)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	for i, card in FACTIONS do
		makeCard(row, card, i)
	end

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g

	-- animate in
	TweenService:Create(backdrop, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()
	TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.5) }):Play()
end

local function close()
	local g = gui
	if not g then return end
	gui = nil
	pending = false
	selectToken += 1
	local backdrop = g:FindFirstChild("Backdrop") :: Frame?
	if backdrop then
		TweenService:Create(backdrop, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		local container = backdrop:FindFirstChild("Container") :: Frame?
		if container then
			TweenService:Create(container, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.fromScale(0.5, 0.42) }):Play()
		end
	end
	game:GetService("Debris"):AddItem(g, 0.3)
end

function FactionSelectController:Init()
	Net.onClientEvent("ShowFactionSelect", function()
		Logger.info(SCOPE, "ShowFactionSelect received — opening picker")
		build()
	end)

	Net.onClientEvent("UpdateFactionDisplay", function(payload: any)
		local p = payload :: { faction: string?, rank: string? }
		if p.faction ~= nil then
			close()  -- server confirmed a faction; dismiss the modal
		end
	end)
end

function FactionSelectController:Start()
	-- Race-free fallback: ask the server for status once we are ready. If the
	-- join-time ShowFactionSelect push was missed, this still opens the picker.
	task.spawn(function()
		local ok, status = pcall(function()
			return Net.invokeServer("GetFactionStatus")
		end)
		if ok and type(status) == "table" and status.faction == nil and gui == nil then
			Logger.info(SCOPE, "GetFactionStatus: no faction — opening picker")
			build()
		end
	end)

	-- Studio-only dev button: faction is one-time in the shipped game, but in Studio
	-- this reopens the picker so every faction (Priest, etc.) can be tested. The server
	-- handler is also Studio-gated, so this does nothing in production even if triggered.
	if game:GetService("RunService"):IsStudio() then
		local dg = Instance.new("ScreenGui")
		dg.Name = "FactionDevTools"; dg.ResetOnSpawn = false; dg.IgnoreGuiInset = true; dg.DisplayOrder = 101
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(176, 30)
		b.Position = UDim2.new(0, 8, 1, -8); b.AnchorPoint = Vector2.new(0, 1)
		b.BackgroundColor3 = Color3.fromRGB(48, 30, 30); b.BorderSizePixel = 0
		b.Text = "↺ Reset Faction (dev)"; b.TextColor3 = Color3.fromRGB(235, 200, 190)
		b.Font = Enum.Font.GothamMedium; b.TextSize = 13
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = b
		b.Parent = dg
		b.Activated:Connect(function() Net.fireServer("RequestResetFaction", {}) end)
		dg.Parent = player:WaitForChild("PlayerGui")
	end
end

return FactionSelectController
