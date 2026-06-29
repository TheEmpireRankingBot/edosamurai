--!strict
-- Studio-only solo dummy input bridge. Lets a one-player test click Workspace.CombatTestArena.SoloArmorDummy.
-- It does not modify CombatService; it sends a separate test request that mirrors CombatConfig armor/gap math.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then return end

local Net = require(ReplicatedStorage.Framework.Net)
local CombatConfig = require(ReplicatedStorage.Config.CombatConfig)

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local currentWeapon = "Unarmed"
local selectedArmor = "heavy"

local armorButtons: { [string]: TextButton } = {}
local observedTools: { [Tool]: boolean } = {}
local observedContainers: { [Instance]: boolean } = {}

local function setCurrentWeapon(weaponName: string)
	if CombatConfig.Weapons[weaponName] == nil then
		weaponName = "Unarmed"
	end
	currentWeapon = weaponName
end

local function weaponNameFromTool(tool: Tool): string?
	local rawWeapon = tool:GetAttribute("weaponType")
	if type(rawWeapon) ~= "string" then
		rawWeapon = tool:GetAttribute("WeaponType")
	end
	if type(rawWeapon) == "string" and CombatConfig.Weapons[rawWeapon] ~= nil then
		return rawWeapon
	end
	if CombatConfig.Weapons[tool.Name] ~= nil then
		return tool.Name
	end
	if tool.Name == "Wakizashi" then
		return "Unarmed"
	end
	return nil
end

local function equippedToolWeapon(): string?
	local char = player.Character
	if char == nil then return nil end
	for _, child in char:GetChildren() do
		if child:IsA("Tool") then
			local weaponName = weaponNameFromTool(child :: Tool)
			if weaponName ~= nil then
				return weaponName
			end
		end
	end
	return nil
end

local function observeTool(tool: Tool)
	if observedTools[tool] then return end
	observedTools[tool] = true

	tool.Equipped:Connect(function()
		local weaponName = weaponNameFromTool(tool)
		if weaponName ~= nil then
			setCurrentWeapon(weaponName)
		end
	end)

	tool.Unequipped:Connect(function()
		local removedWeapon = weaponNameFromTool(tool)
		if removedWeapon == nil then return end
		task.defer(function()
			if equippedToolWeapon() == nil and currentWeapon == removedWeapon then
				setCurrentWeapon("Unarmed")
			end
		end)
	end)
end

local function observeToolContainer(container: Instance)
	if observedContainers[container] then return end
	observedContainers[container] = true
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			observeTool(child :: Tool)
		end
	end
	container.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			observeTool(child :: Tool)
		end
	end)
end

local function isSoloDummyTarget(target: Instance?): boolean
	if target == nil then return false end
	local model = target:FindFirstAncestor("SoloArmorDummy")
	return model ~= nil and model:GetAttribute("CombatSoloDummy") == true
end

local function setSelectedArmor(armorClass: string)
	if CombatConfig.ArmorClasses[armorClass] == nil then return end
	selectedArmor = armorClass
	for className, button in armorButtons do
		local selected = className == selectedArmor
		button.BackgroundColor3 = selected and Color3.fromRGB(210, 190, 140) or Color3.fromRGB(35, 35, 35)
		button.TextColor3 = selected and Color3.fromRGB(20, 18, 16) or Color3.fromRGB(235, 235, 235)
	end
end

local function requestArmorClass(armorClass: string)
	if CombatConfig.ArmorClasses[armorClass] == nil then return end
	setSelectedArmor(armorClass)
	Net.fireServer("RequestSoloDummyArmorClass", { armorClass = armorClass })
end

local function buildArmorSelector()
	local playerGui = player:WaitForChild("PlayerGui")
	if playerGui:FindFirstChild("SoloDummyArmorSelector") then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SoloDummyArmorSelector"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromOffset(252, 78)
	panel.Position = UDim2.new(1, -20, 1, -110)
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0, 24)
	title.Position = UDim2.fromOffset(8, 6)
	title.BackgroundTransparency = 1
	title.Text = "Solo Dummy Armor"
	title.TextColor3 = Color3.fromRGB(235, 235, 235)
	title.TextSize = 14
	title.Font = Enum.Font.GothamSemibold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	for index, armorClass in CombatConfig.ArmorClassNames do
		local button = Instance.new("TextButton")
		button.Name = armorClass
		button.Size = UDim2.fromOffset(74, 30)
		button.Position = UDim2.fromOffset(8 + ((index - 1) * 80), 38)
		button.BorderSizePixel = 0
		button.Text = string.upper(string.sub(armorClass, 1, 1)) .. string.sub(armorClass, 2)
		button.TextSize = 13
		button.Font = Enum.Font.Gotham
		button.Parent = panel
		button.MouseButton1Click:Connect(function()
			requestArmorClass(armorClass)
		end)
		armorButtons[armorClass] = button
	end

	gui.Parent = playerGui
	setSelectedArmor(selectedArmor)
end

Net.onClientEvent("CombatLoadout", function(payload: any)
	setCurrentWeapon((payload :: any).weapon or "Unarmed")
end)

Net.onClientEvent("SoloDummyFeedback", function(payload: any)
	local armorClass = (payload :: any).armorClass
	if type(armorClass) == "string" then
		setSelectedArmor(armorClass)
	end
	local damage = tostring((payload :: any).damage or 0)
	local result = tostring((payload :: any).result or "hit")
	local hp = tostring((payload :: any).health or 0)
	print("[SoloDummy] " .. result .. " damage=" .. damage .. " hp=" .. hp)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not isSoloDummyTarget(mouse.Target) then return end
		Net.fireServer("RequestSoloDummyHit", {
			weaponType = currentWeapon,
			hitPosition = mouse.Hit.Position,
		})
	elseif input.KeyCode == Enum.KeyCode.Z then
		requestArmorClass("light")
	elseif input.KeyCode == Enum.KeyCode.X then
		requestArmorClass("medium")
	elseif input.KeyCode == Enum.KeyCode.C then
		requestArmorClass("heavy")
	end
end)

local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
if backpack ~= nil then
	observeToolContainer(backpack)
end
if player.Character then
	observeToolContainer(player.Character)
end
player.CharacterAdded:Connect(function(char: Model)
	observeToolContainer(char)
	task.defer(function()
		if equippedToolWeapon() == nil then
			setCurrentWeapon("Unarmed")
		end
	end)
end)

buildArmorSelector()
