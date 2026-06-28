--!strict
-- ModuleScript: ServerScriptService.Services.InventoryService
-- Layer 3 item authority. ALL item ops route through DataService (never DataStore).
-- Centralises inventory mutation so GatherService and NPCService stay DRY.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader   = require(ReplicatedStorage.Framework.Loader)
local Logger   = require(ReplicatedStorage.Framework.Logger)
local ItemDefs = require(ReplicatedStorage.Config.ItemDefs)

local SCOPE = "InventoryService"

type Item = { itemId: string, quantity: number }

local InventoryService = {}
local dataService: any

function InventoryService:Init()
	dataService = Loader.get("DataService")
end

function InventoryService:Start() end

local function getInv(player: Player): { Item }?
	return dataService.get(player, "inventory") :: { Item }?
end

function InventoryService.getInventory(player: Player): { Item }
	return getInv(player) or {}
end

function InventoryService.count(player: Player, itemId: string): number
	local inv = getInv(player)
	if not inv then return 0 end
	for _, it in inv do
		if it.itemId == itemId then return it.quantity end
	end
	return 0
end

function InventoryService.addItem(player: Player, itemId: string, qty: number): boolean
	if ItemDefs.get(itemId) == nil then
		Logger.warn(SCOPE, "addItem: unknown item " .. tostring(itemId)); return false
	end
	if qty <= 0 or math.floor(qty) ~= qty then
		Logger.warn(SCOPE, "addItem: bad qty " .. tostring(qty)); return false
	end
	local inv = getInv(player)
	if not inv then Logger.warn(SCOPE, "addItem: no profile for " .. player.Name); return false end
	for _, it in inv do
		if it.itemId == itemId then
			it.quantity += qty
			dataService.set(player, "inventory", inv)
			return true
		end
	end
	table.insert(inv, { itemId = itemId, quantity = qty })
	dataService.set(player, "inventory", inv)
	return true
end

function InventoryService.removeItem(player: Player, itemId: string, qty: number): boolean
	if qty <= 0 or math.floor(qty) ~= qty then return false end
	local inv = getInv(player)
	if not inv then return false end
	for idx, it in inv do
		if it.itemId == itemId then
			if it.quantity < qty then return false end
			it.quantity -= qty
			if it.quantity <= 0 then table.remove(inv, idx) end
			dataService.set(player, "inventory", inv)
			return true
		end
	end
	return false
end

return InventoryService
