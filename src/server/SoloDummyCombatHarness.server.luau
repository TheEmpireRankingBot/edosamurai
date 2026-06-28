--!strict
-- Script: ServerScriptService.SoloDummyCombatHarness
-- Studio-only single-player combat proxy. This exists because production CombatService
-- targets real Players by UserId; a loose part cannot be hit by RequestMeleeHit.
-- This harness does not alter CombatService or CombatConfig. It reads CombatConfig and
-- applies the same armor/gap/Kanabo damage math to Workspace.CombatTestArena.SoloArmorDummy.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then return end

local Net = require(ReplicatedStorage.Framework.Net)
local Validate = require(ReplicatedStorage.Framework.Validate)
local CombatConfig = require(ReplicatedStorage.Config.CombatConfig)
local DataService = require(ServerScriptService.Services.DataService) :: any

local SCOPE = "SoloDummyCombatHarness"
local healthByDummy: { [Instance]: number } = {}

local function getDummy(): Model?
	local arena = Workspace:FindFirstChild("CombatTestArena")
	local dummy = arena and arena:FindFirstChild("SoloArmorDummy")
	if dummy and dummy:IsA("Model") then return dummy end
	return nil
end

local function getTorso(dummy: Model): BasePart?
	local torso = dummy:FindFirstChild("ArmoredTorso")
	return if torso and torso:IsA("BasePart") then torso else nil
end

local function setBillboard(dummy: Model, text: string)
	local torso = getTorso(dummy)
	local label = torso and torso:FindFirstChild("SoloDummyBillboard") and torso.SoloDummyBillboard:FindFirstChild("Status")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function resetDummy(dummy: Model)
	healthByDummy[dummy] = CombatConfig.MAX_HEALTH
	dummy:SetAttribute("Health", CombatConfig.MAX_HEALTH)
	dummy:SetAttribute("State", "Ready")
	local torso = getTorso(dummy)
	if torso then torso.Color = Color3.fromRGB(105, 105, 105) end
	setBillboard(dummy, string.format("Solo Dummy\nHP %d/%d", CombatConfig.MAX_HEALTH, CombatConfig.MAX_HEALTH))
end

local function isGapHit(dummy: Model, hitPosition: Vector3): boolean
	for _, descendant in dummy:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == CombatConfig.GAP_ATTACHMENT_NAME then
			if (descendant.WorldPosition - hitPosition).Magnitude <= CombatConfig.GAP_RADIUS then
				return true
			end
		end
	end
	return false
end

local function getHRP(player: Player): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

local function currentEquippedWeapon(player: Player): string
	local ok, equipped = pcall(function()
		return DataService.get(player, "equipped")
	end)
	if ok and type(equipped) == "table" and type(equipped.weapon) == "string" then
		return equipped.weapon
	end
	return "Unarmed"
end

local function applyHit(player: Player, weaponType: string, hitPosition: Vector3)
	local dummy = getDummy()
	if dummy == nil then return end
	local torso = getTorso(dummy)
	if torso == nil then return end

	if healthByDummy[dummy] == nil then resetDummy(dummy) end

	local weapon = CombatConfig.Weapons[weaponType]
	if weapon == nil then return end

	local equipped = currentEquippedWeapon(player)
	if equipped ~= weaponType then
		warn(string.format("[%s] rejected weapon mismatch: client=%s equipped=%s", SCOPE, weaponType, equipped))
		return
	end

	local hrp = getHRP(player)
	if hrp == nil then return end
	local distance = (hrp.Position - torso.Position).Magnitude
	local maxReach = weapon.range + CombatConfig.RANGE_SLACK
	if distance > maxReach then
		setBillboard(dummy, string.format("OUT OF RANGE\n%.1f > %.1f", distance, maxReach))
		warn(string.format("[%s] out of range %.1f > %.1f", SCOPE, distance, maxReach))
		return
	end

	local gap = isGapHit(dummy, hitPosition)
	local damage = weapon.damage
	local result = "torso reduced"
	if weapon.ignoresArmor then
		result = "armor ignored"
	elseif gap then
		result = "gap full"
	else
		damage *= (1 - CombatConfig.ARMOR_DAMAGE_REDUCTION)
	end
	damage = math.floor(damage + 0.5)

	local health = math.max(0, (healthByDummy[dummy] or CombatConfig.MAX_HEALTH) - damage)
	healthByDummy[dummy] = health
	dummy:SetAttribute("Health", health)

	local state = health <= 0 and "Downed" or "Ready"
	dummy:SetAttribute("State", state)
	if torso then torso.Color = health <= 0 and Color3.fromRGB(70, 70, 70) or Color3.fromRGB(105, 105, 105) end
	setBillboard(dummy, string.format("%s\n-%d %s\nHP %d/%d", state, damage, result, health, CombatConfig.MAX_HEALTH))

	print(string.format("[%s] %s hit solo dummy with %s for %d (%s, hp=%d)", SCOPE, player.Name, weaponType, damage, result, health))
	Net.fireClient("SoloDummyFeedback", player, {
		result = result,
		damage = damage,
		health = health,
		state = state,
		gap = gap,
	})

	if health <= 0 then
		task.delay(3, function()
			local current = getDummy()
			if current == dummy and (healthByDummy[dummy] or 0) <= 0 then
				resetDummy(dummy)
			end
		end)
	end
end

Net.registerClientEvent("SoloDummyFeedback")
Net.registerEvent("RequestSoloDummyHit", Validate.shape({
	weaponType = Validate.literal(CombatConfig.WeaponNames),
	hitPosition = Validate.vector,
}))
Net.onEvent("RequestSoloDummyHit", function(player: Player, payload: any)
	local p = payload :: { weaponType: string, hitPosition: Vector3 }
	applyHit(player, p.weaponType, p.hitPosition)
end)

local initial = getDummy()
if initial then resetDummy(initial) end
Players.PlayerAdded:Connect(function()
	local dummy = getDummy()
	if dummy then resetDummy(dummy) end
end)

print("[" .. SCOPE .. "] online. One-player test: equip Katana/Kanabo/Wakizashi and click SoloArmorDummy. Torso=33 Katana, GapZone=55 Katana, Kanabo=70.")
