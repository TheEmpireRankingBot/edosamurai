--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.MoneyChangerController
-- ProximityPrompt on a tagged money-changer spot -> placeholder exchange UI.

local Players                = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")

local Net           = require(ReplicatedStorage.Framework.Net)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)

local player = Players.LocalPlayer
local MoneyChangerController = {}

local gui: ScreenGui?
local amountBox: TextBox?
local statusLabel: TextLabel?

local function setStatus(text: string)
	if statusLabel then statusLabel.Text = text end
end

local function parseAmount(): number?
	if amountBox == nil then return nil end
	local amount = tonumber(amountBox.Text)
	if amount == nil then return nil end
	amount = math.floor(amount)
	if amount <= 0 then return nil end
	return amount
end

local function makeButton(parent: Instance, order: number, text: string): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 34)
	b.BackgroundColor3 = Color3.fromRGB(42, 52, 42)
	b.BorderSizePixel = 0
	b.TextColor3 = Color3.fromRGB(236, 232, 210)
	b.Font = Enum.Font.Gotham
	b.TextSize = 13
	b.Text = text
	b.Parent = parent
	return b
end

local function ensureGui(): ScreenGui
	if gui then return gui end

	local g = Instance.new("ScreenGui")
	g.Name = "MoneyChangerUI"
	g.ResetOnSpawn = false
	g.Enabled = false
	g.DisplayOrder = 7

	local frame = Instance.new("Frame")
	frame.Name = "Window"
	frame.Size = UDim2.fromOffset(320, 250)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(20, 18, 14)
	frame.BorderSizePixel = 0
	frame.Parent = g

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -44, 0, 34)
	title.Position = UDim2.fromOffset(10, 6)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(225, 205, 150)
	title.Font = Enum.Font.Antique
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Money Changer"
	title.Parent = frame

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(28, 28)
	close.Position = UDim2.new(1, -34, 0, 6)
	close.BackgroundColor3 = Color3.fromRGB(80, 34, 30)
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.Text = "X"
	close.Parent = frame
	close.Activated:Connect(function() g.Enabled = false end)

	local amount = Instance.new("TextBox")
	amount.Name = "Amount"
	amount.Size = UDim2.new(1, -20, 0, 32)
	amount.Position = UDim2.fromOffset(10, 46)
	amount.BackgroundColor3 = Color3.fromRGB(34, 30, 24)
	amount.BorderSizePixel = 0
	amount.ClearTextOnFocus = false
	amount.TextColor3 = Color3.fromRGB(245, 240, 220)
	amount.PlaceholderColor3 = Color3.fromRGB(160, 150, 125)
	amount.Font = Enum.Font.Gotham
	amount.TextSize = 14
	amount.Text = "250"
	amount.PlaceholderText = "Amount"
	amount.Parent = frame
	amountBox = amount

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -20, 0, 114)
	list.Position = UDim2.fromOffset(10, 86)
	list.BackgroundTransparency = 1
	list.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for index, from in EconomyConfig.CURRENCIES do
		local to = EconomyConfig.DEFAULT_EXCHANGE_TARGET[from]
		if to == nil then continue end
		local rate = EconomyConfig.EXCHANGE_RATES[from] and EconomyConfig.EXCHANGE_RATES[from][to]
		local rateText = if rate then string.format(" (%d:1, 5%% fee)", rate) else ""
		local button = makeButton(list, index, string.format("%s -> %s%s", from, to, rateText))
		local fromCurrency = from
		button.Activated:Connect(function()
			local amountValue = parseAmount()
			if amountValue == nil then
				setStatus("Enter a positive whole amount.")
				return
			end
			Net.fireServer("RequestExchange", { from = fromCurrency, amount = amountValue })
		end)
	end

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, -20, 0, 28)
	status.Position = UDim2.new(0, 10, 1, -38)
	status.BackgroundTransparency = 1
	status.TextColor3 = Color3.fromRGB(210, 200, 175)
	status.Font = Enum.Font.Gotham
	status.TextSize = 13
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = ""
	status.Parent = frame
	statusLabel = status

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	return g
end

function MoneyChangerController.open()
	local g = ensureGui()
	g.Enabled = true
	setStatus("")
end

function MoneyChangerController:Init()
	Net.onClientEvent("RequestExchange", function(payload: any)
		local p = payload :: { ok: boolean, msg: string? }
		setStatus(p.msg or (p.ok and "Exchange complete" or "Exchange failed"))
	end)
end

function MoneyChangerController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, plr: Player)
		if plr ~= player then return end
		if prompt.Name == EconomyConfig.MONEY_CHANGER_PROMPT_NAME then
			MoneyChangerController.open()
		end
	end)
end

return MoneyChangerController
