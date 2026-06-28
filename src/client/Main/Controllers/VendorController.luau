--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.VendorController
-- ProximityPrompt on a vendor NPC -> placeholder shop UI listing stock with
-- buy/sell buttons -> Net.fireServer; refreshes on result.

local Players                = game:GetService("Players")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Net = require(ReplicatedStorage.Framework.Net)

local player = Players.LocalPlayer
local VendorController = {}

local gui: ScreenGui?
local currentVendorId: string?

local function ensureGui(): ScreenGui
	if gui then return gui end
	local g = Instance.new("ScreenGui")
	g.Name = "VendorShop"; g.ResetOnSpawn = false; g.Enabled = false; g.DisplayOrder = 6

	local frame = Instance.new("Frame")
	frame.Name = "Window"
	frame.Size = UDim2.fromOffset(360, 320)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(20, 16, 12)
	frame.BorderSizePixel = 0
	frame.Parent = g

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -44, 0, 32)
	title.Position = UDim2.fromOffset(10, 6)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(230, 210, 150)
	title.Font = Enum.Font.Antique
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Vendor"
	title.Parent = frame

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(28, 28)
	close.Position = UDim2.new(1, -34, 0, 6)
	close.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.Text = "X"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.Parent = frame
	close.Activated:Connect(function() VendorController.close() end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Size = UDim2.new(1, -20, 1, -88)
	scroll.Position = UDim2.fromOffset(10, 44)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local st = Instance.new("TextLabel")
	st.Name = "Status"
	st.Size = UDim2.new(1, -20, 0, 24)
	st.Position = UDim2.new(0, 10, 1, -34)
	st.BackgroundTransparency = 1
	st.TextColor3 = Color3.fromRGB(210, 200, 175)
	st.Font = Enum.Font.Gotham
	st.TextSize = 13
	st.TextXAlignment = Enum.TextXAlignment.Left
	st.Text = ""
	st.Parent = frame

	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	return g
end

local function setStatus(text: string)
	local g = ensureGui()
	local s = g.Window:FindFirstChild("Status") :: TextLabel?
	if s then s.Text = text end
end

local function refresh()
	if not currentVendorId then return end
	local data = Net.invokeServer("GetVendorData", currentVendorId)
	local g = ensureGui()
	local list = g.Window:FindFirstChild("List") :: ScrollingFrame
	local title = g.Window:FindFirstChild("Title") :: TextLabel
	if not data then return end
	title.Text = data.name
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end
	for i, item in data.items do
		local row = Instance.new("Frame")
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 48)
		row.BackgroundColor3 = Color3.fromRGB(34, 28, 20)
		row.BorderSizePixel = 0
		row.Parent = list

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -10, 0, 20)
		name.Position = UDim2.fromOffset(6, 2)
		name.BackgroundTransparency = 1
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = Color3.fromRGB(235, 220, 180)
		name.Font = Enum.Font.Antique
		name.TextSize = 15
		name.Text = string.format("%s  (stock: %d)", item.name, item.remaining)
		name.Parent = row

		local buyBtn = Instance.new("TextButton")
		buyBtn.Size = UDim2.fromOffset(160, 20)
		buyBtn.Position = UDim2.fromOffset(6, 24)
		buyBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 40)
		buyBtn.TextColor3 = Color3.fromRGB(235, 235, 220)
		buyBtn.Font = Enum.Font.Gotham
		buyBtn.TextSize = 12
		buyBtn.Text = string.format("Buy 1  -  %d mon", item.buyPrice)
		buyBtn.Parent = row
		buyBtn.Activated:Connect(function()
			if currentVendorId then
				Net.fireServer("RequestVendorBuy", { vendorId = currentVendorId, itemId = item.itemId, qty = 1 })
			end
		end)

		local sellBtn = Instance.new("TextButton")
		sellBtn.Size = UDim2.fromOffset(160, 20)
		sellBtn.Position = UDim2.fromOffset(172, 24)
		sellBtn.BackgroundColor3 = Color3.fromRGB(70, 50, 30)
		sellBtn.TextColor3 = Color3.fromRGB(235, 235, 220)
		sellBtn.Font = Enum.Font.Gotham
		sellBtn.TextSize = 12
		sellBtn.Text = string.format("Sell 1  -  %d mon", item.sellPrice)
		sellBtn.Parent = row
		sellBtn.Activated:Connect(function()
			if currentVendorId then
				Net.fireServer("RequestVendorSell", { vendorId = currentVendorId, itemId = item.itemId, qty = 1 })
			end
		end)
	end
end

function VendorController.open(vendorId: string)
	currentVendorId = vendorId
	local g = ensureGui()
	g.Enabled = true
	setStatus("")
	refresh()
end

function VendorController.close()
	if gui then gui.Enabled = false end
	currentVendorId = nil
end

function VendorController:Init()
	local function onResult(payload: any)
		local p = payload :: { ok: boolean, msg: string }
		setStatus(tostring(p.msg))
		if currentVendorId then refresh() end
	end
	Net.onClientEvent("RequestVendorBuy", onResult)
	Net.onClientEvent("RequestVendorSell", onResult)
end

function VendorController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, plr: Player)
		if plr ~= player then return end
		if prompt.Name ~= "VendorPrompt" then return end
		local vendorId = prompt:GetAttribute("VendorId")
		if type(vendorId) == "string" then
			VendorController.open(vendorId)
		end
	end)
end

return VendorController
