--!strict
-- Studio-only solo dummy input bridge. Lets a one-player test click Workspace.CombatTestArena.SoloArmorDummy.
-- It does not modify CombatService; it sends a separate test request that mirrors CombatConfig armor/gap math.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then return end

local Net = require(ReplicatedStorage.Framework.Net)

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local currentWeapon = "Unarmed"

local function isSoloDummyTarget(target: Instance?): boolean
	if target == nil then return false end
	local model = target:FindFirstAncestor("SoloArmorDummy")
	return model ~= nil and model:GetAttribute("CombatSoloDummy") == true
end

Net.onClientEvent("CombatLoadout", function(payload: any)
	currentWeapon = (payload :: any).weapon or currentWeapon
end)

Net.onClientEvent("SoloDummyFeedback", function(payload: any)
	local damage = tostring((payload :: any).damage or 0)
	local result = tostring((payload :: any).result or "hit")
	local hp = tostring((payload :: any).health or 0)
	print("[SoloDummy] " .. result .. " damage=" .. damage .. " hp=" .. hp)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not isSoloDummyTarget(mouse.Target) then return end
	Net.fireServer("RequestSoloDummyHit", {
		weaponType = currentWeapon,
		hitPosition = mouse.Hit.Position,
	})
end)
