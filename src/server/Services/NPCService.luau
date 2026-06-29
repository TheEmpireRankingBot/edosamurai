--!strict
-- ModuleScript: ServerScriptService.Services.NPCService
-- Layer 3: class-scheduled NPCs (make the town feel populated with zero players)
-- AND the server-authoritative vendor economy (the liquidity floor for solo play).

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local Debris             = game:GetService("Debris")

local Loader         = require(ReplicatedStorage.Framework.Loader)
local Logger         = require(ReplicatedStorage.Framework.Logger)
local Net            = require(ReplicatedStorage.Framework.Net)
local Validate       = require(ReplicatedStorage.Framework.Validate)
local MoralityConfig = require(ReplicatedStorage.Config.MoralityConfig)
local NPCDefs        = require(ReplicatedStorage.Config.NPCDefs)
local VendorDefs     = require(ReplicatedStorage.Config.VendorDefs)
local ItemDefs       = require(ReplicatedStorage.Config.ItemDefs)

local SCOPE = "NPCService"

type NPCRecord = {
	model:      Model,
	primary:    BasePart,
	class:      string,
	def:        any,
	state:      string,
	anchor:     BasePart?,
	lastChatAt: number,
	lastReactionMoveAt: number,
	vendorId:   string?,
	moveTween:  Tween?,
}

local NPCService = {}
local timeService:      any
local economyService:   any
local inventoryService: any
local priestService:    any
local moralityService:  any

local npcs: { NPCRecord } = {}
-- vendorId -> { itemId -> remainingStock }
local vendorStock: { [string]: { [string]: number } } = {}

local CHAT_COOLDOWN        = 30   -- seconds per NPC between barks
local CHAT_CHANCE          = 0.35 -- per NPC per sweep
local CHAT_TICK            = 6    -- seconds between chat sweeps
local MAX_CONCURRENT_MOVES = 4    -- stagger window for movement starts

-- ── movement / chat helpers ──────────────────────────────────────────────────

local function pickAnchor(tag: string): BasePart?
	local parts: { BasePart } = {}
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") then table.insert(parts, inst) end
	end
	if #parts == 0 then return nil end
	return parts[math.random(1, #parts)]
end

-- Cheap movement: CFrame tween of the (anchored) PrimaryPart at walkSpeed.
-- (Placeholder fallback per spec; no rigged Humanoid pathfinding needed.)
local function moveNPC(rec: NPCRecord, target: BasePart, instant: boolean?)
	local goal = CFrame.new(target.Position + Vector3.new(0, rec.primary.Size.Y / 2 + target.Size.Y / 2, 0))
	-- Cancel any in-flight tween first so a fast hour change can't stack two tweens (jitter).
	if rec.moveTween then rec.moveTween:Cancel(); rec.moveTween = nil end
	if instant then
		rec.primary.CFrame = goal
		return
	end
	local dist  = (rec.primary.Position - goal.Position).Magnitude
	local dur   = math.clamp(dist / math.max(rec.def.walkSpeed, 1), 0.2, 14)
	local tween = TweenService:Create(rec.primary, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = goal })
	rec.moveTween = tween
	tween:Play()
end

local function showChat(rec: NPCRecord, line: string)
	local part = rec.primary
	local gui = Instance.new("BillboardGui")
	gui.Name = "ChatBubble"
	gui.Size = UDim2.fromOffset(240, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2.5, 0)
	gui.AlwaysOnTop = true
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundColor3 = Color3.fromRGB(12, 10, 8)
	lbl.BackgroundTransparency = 0.2
	lbl.TextColor3 = Color3.fromRGB(235, 225, 200)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.Antique
	lbl.Text = line
	lbl.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = lbl
	gui.Parent = part
	Debris:AddItem(gui, 4)
end

local function getHRP(player: Player): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

local function getModelPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function isNearVendor(player: Player, vendorId: string): boolean
	local hrp = getHRP(player)
	if hrp == nil then return false end

	for _, rec in npcs do
		if rec.vendorId == vendorId and rec.primary.Parent ~= nil then
			if (rec.primary.Position - hrp.Position).Magnitude <= VendorDefs.INTERACTION_RANGE then
				return true
			end
		end
	end

	local vendorDef = NPCDefs.Classes.Vendor
	if vendorDef == nil then return false end
	for _, inst in CollectionService:GetTagged(vendorDef.tag) do
		if inst:GetAttribute("VendorId") ~= vendorId then continue end
		local part = getModelPart(inst)
		if part and (part.Position - hrp.Position).Magnitude <= VendorDefs.INTERACTION_RANGE then
			return true
		end
	end

	return false
end

local function nearestPlayer(position: Vector3, radius: number): Player?
	local nearest: Player? = nil
	local nearestDist = radius
	for _, player in Players:GetPlayers() do
		local hrp = getHRP(player)
		if hrp == nil then continue end
		local dist = (hrp.Position - position).Magnitude
		if dist <= nearestDist then
			nearest = player
			nearestDist = dist
		end
	end
	return nearest
end

local function reactionLinesFor(className: string, standing: MoralityConfig.Standing): { string }?
	local pools = MoralityConfig.WorldReaction.NPCBarks[standing]
	if pools == nil then return nil end
	return pools[className] or pools.Default
end

local function shouldRetreat(className: string, standing: MoralityConfig.Standing): boolean
	if standing ~= "Feared" and standing ~= "Shunned" then return false end
	return MoralityConfig.WorldReaction.RETREAT_CLASSES[className] == true
end

local function moveAwayFromPlayer(rec: NPCRecord, player: Player)
	local hrp = getHRP(player)
	if hrp == nil then return end
	local away = rec.primary.Position - hrp.Position
	if away.Magnitude < 0.1 then return end
	local target = Instance.new("Part")
	target.Name = "MoralityRetreatTarget"
	target.Size = Vector3.new(0.1, 0.1, 0.1)
	target.Transparency = 1
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.CFrame = CFrame.new(rec.primary.Position + away.Unit * MoralityConfig.WorldReaction.RETREAT_DISTANCE)
	target.Parent = rec.model
	moveNPC(rec, target)
	Debris:AddItem(target, 3)
	Logger.info(SCOPE, string.format("%s backs away from %s (%s)", rec.class, player.Name, moralityService.getMoralityStanding(player)))
end

-- ── schedule application ──────────────────────────────────────────────────
local function applyHour(hour: number, instant: boolean?)
	for i, rec in npcs do
		local entry = NPCDefs.stateForHour(rec.class, hour)
		if entry == nil then continue end
		if entry.state ~= rec.state or rec.anchor == nil then
			rec.state = entry.state
			local anchor = pickAnchor(entry.anchorTag)
			rec.anchor = anchor
			if anchor == nil then
				Logger.warn(SCOPE, "No anchor tagged '" .. entry.anchorTag .. "' for " .. rec.class)
			elseif instant then
				moveNPC(rec, anchor, true)
			else
				local a = anchor
				task.delay((i % MAX_CONCURRENT_MOVES) * 0.15, function()
					if rec.model.Parent then moveNPC(rec, a) end
				end)
			end
		end
	end
end

local function startChatLoop()
	task.spawn(function()
		while true do
			task.wait(CHAT_TICK)
			local now = os.clock()
			for _, rec in npcs do
				if now - rec.lastChatAt >= CHAT_COOLDOWN and math.random() < CHAT_CHANCE then
					local nearby = nearestPlayer(rec.primary.Position, MoralityConfig.WorldReaction.NPC_REACTION_RADIUS)
					local standing: MoralityConfig.Standing = "Neutral"
					local lines = rec.def.chatLines[rec.state]
					if nearby ~= nil then
						standing = moralityService.getMoralityStanding(nearby)
						local reactionLines = reactionLinesFor(rec.class, standing)
						if reactionLines and #reactionLines > 0 then
							lines = reactionLines
							Logger.info(SCOPE, string.format("World reaction bark: %s -> %s near %s", rec.class, standing, nearby.Name))
						end
						if shouldRetreat(rec.class, standing)
							and now - rec.lastReactionMoveAt >= MoralityConfig.WorldReaction.RETREAT_COOLDOWN then
							rec.lastReactionMoveAt = now
							moveAwayFromPlayer(rec, nearby)
						end
					end
					if lines and #lines > 0 then
						rec.lastChatAt = now
						showChat(rec, lines[math.random(1, #lines)])
					end
				end
			end
		end
	end)
end

-- ── vendor economy ────────────────────────────────────────────────────
local function resetStock()
	vendorStock = {}
	for id, def in VendorDefs.Defs do
		local s: { [string]: number } = {}
		for _, entry in def.stock do s[entry.itemId] = entry.dailyStock end
		vendorStock[id] = s
	end
	Logger.info(SCOPE, "Vendor stock reset for the day")
end

local function stockEntry(def: any, itemId: string): any?
	for _, e in def.stock do
		if e.itemId == itemId then return e end
	end
	return nil
end

local function standingFor(player: Player?): MoralityConfig.Standing
	if player == nil or moralityService == nil then return "Neutral" end
	return moralityService.getMoralityStanding(player)
end

local function adjustedBuyPrice(player: Player?, entry: any): number
	local standing = standingFor(player)
	local multiplier = 1
	if standing == "Honored" then
		multiplier -= MoralityConfig.WorldReaction.HONORED_BUY_DISCOUNT
	elseif standing == "Feared" then
		multiplier += MoralityConfig.WorldReaction.FEARED_PRICE_PENALTY
	elseif standing == "Shunned" then
		multiplier += MoralityConfig.WorldReaction.SHUNNED_PRICE_PENALTY
	end
	return math.max(1, math.ceil(entry.buyPrice * multiplier))
end

local function adjustedSellPrice(player: Player?, entry: any): (number, boolean)
	local standing = standingFor(player)
	local refused = standing == "Shunned" and MoralityConfig.WorldReaction.SHUNNED_REFUSED_SELL_ITEM_IDS[entry.itemId] == true
	local multiplier = 1
	if standing == "Honored" then
		multiplier += MoralityConfig.WorldReaction.HONORED_SELL_BONUS
	elseif standing == "Feared" then
		multiplier -= MoralityConfig.WorldReaction.FEARED_PRICE_PENALTY
	elseif standing == "Shunned" then
		multiplier -= MoralityConfig.WorldReaction.SHUNNED_PRICE_PENALTY
	end
	return math.max(1, math.floor(entry.sellPrice * multiplier)), refused
end

function NPCService.buyFromVendor(player: Player, vendorId: string, itemId: string, qty: number): (boolean, string)
	local def = VendorDefs.get(vendorId)
	if not def then return false, "Unknown vendor" end
	local entry = stockEntry(def, itemId)
	if not entry then return false, "Vendor does not sell that" end
	local remaining = (vendorStock[vendorId] and vendorStock[vendorId][itemId]) or 0
	if remaining < qty then return false, "Out of stock" end
	local cost = adjustedBuyPrice(player, entry) * qty
	local ok = economyService.removeCurrency(player, "mon", cost)
	if not ok then return false, "Not enough mon" end
	local added = inventoryService.addItem(player, itemId, qty)
	if not added then
		economyService.addCurrency(player, "mon", cost)  -- refund
		return false, "Inventory error"
	end
	vendorStock[vendorId][itemId] = remaining - qty
	Logger.info(SCOPE, string.format("%s bought %dx%s from %s for %d mon",
		player.Name, qty, itemId, vendorId, cost))
	return true, string.format("Bought %d %s", qty, itemId)
end

function NPCService.sellToVendor(player: Player, vendorId: string, itemId: string, qty: number): (boolean, string)
	local def = VendorDefs.get(vendorId)
	if not def then return false, "Unknown vendor" end
	local entry = stockEntry(def, itemId)
	if not entry then return false, "Vendor won't buy that" end
	local unitPrice, refused = adjustedSellPrice(player, entry)
	if refused then return false, "Vendor refuses to buy from the Shunned" end
	local removed = inventoryService.removeItem(player, itemId, qty)
	if not removed then return false, "You don't have that" end
	local payout = unitPrice * qty
	if priestService then
		payout = math.floor(payout * (1 + priestService.getBuff(player, "sellPrice")))  -- Fortune omamori
	end
	economyService.addCurrency(player, "mon", payout)
	Logger.info(SCOPE, string.format("%s sold %dx%s to %s for %d mon",
		player.Name, qty, itemId, vendorId, payout))
	return true, string.format("Sold %d %s", qty, itemId)
end

function NPCService.getStock(vendorId: string, itemId: string): number
	return (vendorStock[vendorId] and vendorStock[vendorId][itemId]) or 0
end

function NPCService.getVendorData(player: Player?, vendorId: string): any
	local def = VendorDefs.get(vendorId)
	if not def then return nil end
	local items = {}
	local standing = standingFor(player)
	for _, e in def.stock do
		local idef = ItemDefs.get(e.itemId)
		local sellPrice, refused = adjustedSellPrice(player, e)
		table.insert(items, {
			itemId     = e.itemId,
			name       = idef and idef.name or e.itemId,
			buyPrice   = adjustedBuyPrice(player, e),
			sellPrice  = sellPrice,
			refuseSell = refused,
			standing   = standing,
			remaining  = (vendorStock[vendorId] and vendorStock[vendorId][e.itemId]) or 0,
		})
	end
	return { vendorId = vendorId, name = def.name, standing = standing, items = items }
end

-- ── setup ─────────────────────────────────────────────────────────────
local function buildNPCs()
	table.clear(npcs)
	for className, def in NPCDefs.Classes do
		for _, model in CollectionService:GetTagged(def.tag) do
			if not model:IsA("Model") then continue end
			local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if not primary then
				Logger.warn(SCOPE, "NPC " .. model.Name .. " has no BasePart — skipped"); continue
			end
			local vendorId = model:GetAttribute("VendorId")
			local rec: NPCRecord = {
				model = model, primary = primary, class = className, def = def,
				state = "", anchor = nil, lastChatAt = 0, lastReactionMoveAt = 0,
				vendorId = (type(vendorId) == "string") and vendorId or nil,
				moveTween = nil,
			}
			table.insert(npcs, rec)
			if rec.vendorId then
				local vdef = VendorDefs.get(rec.vendorId)
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "VendorPrompt"
				prompt.ActionText = "Trade"
				prompt.ObjectText = vdef and vdef.name or "Vendor"
				prompt.HoldDuration = 0
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = 12
				prompt:SetAttribute("VendorId", rec.vendorId)
				prompt.Parent = primary
			end
		end
	end
	Logger.info(SCOPE, "Registered " .. #npcs .. " NPCs")
end

-- Layer 5: make a random subset of NPCs bark one of `lines` (the town reacts to
-- disasters/quells). Reuses the existing chat-bubble path; purely cosmetic.
function NPCService.broadcastMood(lines: { string })
	if #lines == 0 then return end
	for _, rec in npcs do
		if math.random() < 0.5 then
			showChat(rec, lines[math.random(1, #lines)])
		end
	end
end

function NPCService:Init()
	timeService      = Loader.get("TimeService")
	economyService   = Loader.get("EconomyService")
	inventoryService = Loader.get("InventoryService")
	priestService    = Loader.get("PriestService")
	moralityService  = Loader.get("MoralityService")
end

function NPCService:Start()
	buildNPCs()
	resetStock()

	-- place every NPC at its current-hour anchor immediately (no tween)
	applyHour(math.floor(timeService.getHour()), true)

	timeService.onHourChanged:Connect(function(hour: number)
		applyHour(hour, false)
	end)
	timeService.onDayChanged:Connect(function()
		resetStock()
	end)

	startChatLoop()

	-- ── remotes (validated + rate-limited via Net) ──
	Net.registerFunction("GetVendorData",
		Validate.string,
		function(player: Player, vendorId: any): any
			if type(vendorId) ~= "string" then return nil end
			return NPCService.getVendorData(player, vendorId)
		end,
		{ rate = 5 }
	)

	local buySellShape = Validate.shape({
		vendorId = Validate.string,
		itemId   = Validate.string,
		qty      = Validate.positiveInteger,
	})

	Net.registerEvent("RequestVendorBuy", buySellShape, { rate = 5 })
	Net.onEvent("RequestVendorBuy", function(player: Player, payload: any)
		local p = payload :: { vendorId: string, itemId: string, qty: number }
		local ok, msg
		if not isNearVendor(player, p.vendorId) then
			ok, msg = false, "Too far from vendor"
		else
			ok, msg = NPCService.buyFromVendor(player, p.vendorId, p.itemId, p.qty)
		end
		Net.fireClient("RequestVendorBuy", player, { ok = ok, msg = msg, vendorId = p.vendorId })
	end)

	Net.registerEvent("RequestVendorSell", buySellShape, { rate = 5 })
	Net.onEvent("RequestVendorSell", function(player: Player, payload: any)
		local p = payload :: { vendorId: string, itemId: string, qty: number }
		local ok, msg
		if not isNearVendor(player, p.vendorId) then
			ok, msg = false, "Too far from vendor"
		else
			ok, msg = NPCService.sellToVendor(player, p.vendorId, p.itemId, p.qty)
		end
		Net.fireClient("RequestVendorSell", player, { ok = ok, msg = msg, vendorId = p.vendorId })
	end)
end

return NPCService
