--!strict
-- Script: ServerScriptService.CombatTestHarness
-- ============================================================================
--  COMBAT TEST HARNESS  (Studio-only test scaffolding; NOT a Loader service)
-- ============================================================================
--  CombatService damages ONLY players. It stores state by UserId, and
--  RequestMeleeHit resolves targets with Players:GetPlayerByUserId. A non-player
--  NPC rig cannot exercise hit detection, armor reduction, downed, or kill logic
--  without changing CombatService, so this harness uses Studio's local server:
--
--      Test tab -> Clients & Servers -> 2 players -> Start
--
--  P1 becomes ATTACKER. P2 and later clients become frozen armored DUMMY players.
--  The dummy is a real R15 player character with Humanoid health, welded grey armor,
--  equipped.armor set through DataService, and two GapZone attachments from the
--  ArmorPlaceholder model. P1 receives the grey weapon proxy Tools.
--
--  It changes NO CombatConfig values and NO combat logic.
-- ============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then return end

local TestAssets = ServerStorage:WaitForChild("TestAssets", 10)
if TestAssets == nil then warn("[CombatTestHarness] Missing ServerStorage.TestAssets") return end
local WeaponsFolder = TestAssets:WaitForChild("Weapons")
local ArmorTemplate = TestAssets:WaitForChild("ArmorPlaceholder")
local DataService = require(ServerScriptService.Services.DataService) :: any

local SCOPE = "CombatTestHarness"
local attackerAssigned = false

local function standCFrame(name: string, lookAtName: string): CFrame?
	local arena = Workspace:FindFirstChild("CombatTestArena")
	local stand = arena and arena:FindFirstChild(name)
	local lookAt = arena and arena:FindFirstChild(lookAtName)
	if stand and stand:IsA("BasePart") then
		local pos = stand.Position + Vector3.new(0, 3.2, 0)
		local target = if lookAt and lookAt:IsA("BasePart") then lookAt.Position + Vector3.new(0, 3.2, 0) else pos + Vector3.new(0, 0, -1)
		return CFrame.lookAt(pos, target)
	end
	return nil
end

local function moveToStand(char: Model, standName: string, lookAtName: string)
	local cf = standCFrame(standName, lookAtName)
	if cf ~= nil then
		char:PivotTo(cf)
	end
end

local function giveWeapons(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
	if backpack == nil then return end
	for _, tool in WeaponsFolder:GetChildren() do
		if tool:IsA("Tool")
			and backpack:FindFirstChild(tool.Name) == nil
			and not (player.Character and player.Character:FindFirstChild(tool.Name)) then
			tool:Clone().Parent = backpack
		end
	end
end

local function flagArmored(player: Player)
	task.spawn(function()
		local waited = 0
		while DataService.getProfile(player) == nil and waited < 30 do
			task.wait(0.2)
			waited += 0.2
		end
		if DataService.getProfile(player) == nil then return end
		local equipped = DataService.get(player, "equipped") or {}
		equipped.armor = "test_armor"
		DataService.set(player, "equipped", equipped)
		print(string.format("[%s] %s flagged armored (equipped.armor=test_armor)", SCOPE, player.Name))
	end)
end

local function weldArmor(char: Model)
	if char:FindFirstChild("ArmorPlaceholder") then return end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if torso == nil or not torso:IsA("BasePart") then return end
	local armor = ArmorTemplate:Clone()
	local plate = armor.PrimaryPart
	if plate == nil then return end
	armor:PivotTo(torso.CFrame)
	for _, descendant in armor:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = plate
	weld.Part1 = torso
	weld.Parent = plate
	armor.Parent = char
end

local function freezeStationary(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum ~= nil then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
		hum.AutoRotate = false
	end
	task.delay(0.6, function()
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			hrp.Anchored = true
		end
	end)
end

local function setup(player: Player)
	local forced = player:GetAttribute("ForceDummy") == true
	local isDummy: boolean
	if forced then
		isDummy = true
	elseif not attackerAssigned then
		attackerAssigned = true
		isDummy = false
	else
		isDummy = true
	end
	player:SetAttribute("CombatTestRole", isDummy and "DUMMY" or "ATTACKER")

	local function onCharacter(char: Model)
		giveWeapons(player)
		if isDummy then
			moveToStand(char, "DummyStand", "AttackerStand")
			flagArmored(player)
			task.delay(0.4, function()
				weldArmor(char)
				freezeStationary(char)
			end)
		else
			moveToStand(char, "AttackerStand", "DummyStand")
		end
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then task.spawn(onCharacter, player.Character) end
	print(string.format("[%s] %s -> %s", SCOPE, player.Name, isDummy and "DUMMY (frozen armored player target)" or "ATTACKER (weapon proxies in Backpack)"))
end

Players.PlayerAdded:Connect(setup)
for _, player in Players:GetPlayers() do setup(player) end

print("[" .. SCOPE .. "] online. Use Studio local 2-player test: P1 attacks, P2 is frozen armored dummy. Katana torso=armor reduced, Katana GapZone=full, Kanabo=full.")
