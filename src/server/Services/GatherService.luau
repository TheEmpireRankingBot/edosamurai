--!strict
-- ModuleScript: ServerScriptService.Services.GatherService
-- Layer 3 production source. Tagged nodes yield raw items on a timed, cooldown-gated
-- gather. Closes the minimal solo loop: gather -> sell to vendor for mon -> buy gear.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Loader   = require(ReplicatedStorage.Framework.Loader)
local Logger   = require(ReplicatedStorage.Framework.Logger)
local Net      = require(ReplicatedStorage.Framework.Net)
local Validate = require(ReplicatedStorage.Framework.Validate)

local SCOPE = "GatherService"

-- Layer 3: gathering open to all until crafting/faction gates land. Flip to false
-- to require FactionService.hasPermission("canGather") (Civilian).
local ALLOW_ALL_GATHER = true
local PROXIMITY = 14  -- studs

type NodeType = { itemId: string, gatherTime: number, cooldown: number, displayName: string }
local NODE_TYPES: { [string]: NodeType } = {
	Node_RicePaddy   = { itemId = "rice", gatherTime = 3, cooldown = 10, displayName = "Rice Paddy" },
	Node_OreVein     = { itemId = "ore",  gatherTime = 4, cooldown = 15, displayName = "Ore Vein" },
	Node_FishingSpot = { itemId = "fish", gatherTime = 3, cooldown = 12, displayName = "Fishing Spot" },
}

local GatherService = {}
local inventoryService: any
local factionService:   any

local nodeBusy:          { [Instance]: boolean } = {}
local nodeCooldownUntil: { [Instance]: number }  = {}
local activeGather:      { [number]: boolean }   = {}  -- userId in-progress guard

-- Layer 5: a disaster modifier set by DisasterService. nil = no active disaster.
-- { gatherTimeMult: number, yieldChance: number, disabledItems: { [string]: boolean } }
local disasterMod: any = nil

local function nodeTypeOf(node: Instance): NodeType?
	for tag, def in NODE_TYPES do
		if CollectionService:HasTag(node, tag) then return def end
	end
	return nil
end

local function withinRange(player: Player, node: BasePart): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return false end
	return (hrp.Position - node.Position).Magnitude <= PROXIMITY
end

local function setDepleted(node: BasePart, depleted: boolean)
	local prompt = node:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt then prompt.Enabled = not depleted end
	node.Transparency = depleted and 0.6 or 0
	node:SetAttribute("Depleted", depleted)
end

function GatherService.requestGather(player: Player, node: Instance): (boolean, string)
	if not node:IsA("BasePart") then return false, "Invalid node" end
	local def = nodeTypeOf(node)
	if not def then return false, "Not a gather node" end
	if disasterMod and disasterMod.disabledItems[def.itemId] then
		return false, "This node is ruined by disaster"
	end
	if not withinRange(player, node :: BasePart) then return false, "Too far away" end
	if nodeBusy[node] then return false, "Already being gathered" end
	if (nodeCooldownUntil[node] or 0) > os.clock() then return false, "Node depleted" end
	if activeGather[player.UserId] then return false, "Already gathering" end
	if not ALLOW_ALL_GATHER and not factionService.hasPermission(player, "canGather") then
		return false, "Your faction cannot gather"
	end

	nodeBusy[node] = true
	activeGather[player.UserId] = true
	setDepleted(node :: BasePart, true)

	local success = false
	Logger.try(SCOPE, function()
		local timeMult = (disasterMod and disasterMod.gatherTimeMult) or 1
		task.wait(def.gatherTime * timeMult)
		-- re-validate after the cast time (anti-exploit: player must still be present + in range)
		if player.Parent and withinRange(player, node :: BasePart) then
			local yieldChance = (disasterMod and disasterMod.yieldChance) or 1
			if yieldChance >= 1 or math.random() <= yieldChance then
				inventoryService.addItem(player, def.itemId, 1)
				success = true
			end
		end
	end)

	nodeBusy[node] = nil
	activeGather[player.UserId] = nil

	if success then
		nodeCooldownUntil[node] = os.clock() + def.cooldown
		task.delay(def.cooldown, function()
			nodeCooldownUntil[node] = nil
			if node.Parent then setDepleted(node :: BasePart, false) end
		end)
		Logger.info(SCOPE, string.format("%s gathered %s", player.Name, def.itemId))
		return true, "Gathered " .. def.itemId
	else
		setDepleted(node :: BasePart, false)  -- interrupted: restore, no cooldown
		return false, "Gather interrupted"
	end
end

local function buildNodes()
	local count = 0
	for tag, def in NODE_TYPES do
		for _, node in CollectionService:GetTagged(tag) do
			if not node:IsA("BasePart") then continue end
			node:SetAttribute("GatherTime", def.gatherTime)
			node:SetAttribute("NodeKind", def.displayName)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "GatherPrompt"
			prompt.ActionText = "Gather"
			prompt.ObjectText = def.displayName
			prompt.HoldDuration = 0
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = PROXIMITY
			prompt.Parent = node
			count += 1
		end
	end
	Logger.info(SCOPE, "Registered " .. count .. " gather nodes")
end

-- Layer 5: DisasterService sets/clears a modifier that slows/reduces/disables gathering.
function GatherService.setDisasterModifier(mod: any)
	disasterMod = mod
	Logger.info(SCOPE, mod and "Disaster modifier active" or "Disaster modifier cleared")
end

function GatherService:Init()
	inventoryService = Loader.get("InventoryService")
	factionService   = Loader.get("FactionService")
end

function GatherService:Start()
	buildNodes()
	Net.registerEvent("RequestGather", Validate.instanceOf("BasePart"), { rate = 5 })
	Net.onEvent("RequestGather", function(player: Player, node: any)
		local ok, msg = GatherService.requestGather(player, node)
		Net.fireClient("RequestGather", player, { ok = ok, msg = msg })
	end)
end

return GatherService
