--!strict
-- ModuleScript: ServerScriptService.Services.EconomyService
-- Dupe-safe currency authority. addCurrency/transfer are server-internal only.
-- The client may only call RequestExchange.

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Loader        = require(ReplicatedStorage.Framework.Loader)
local Logger        = require(ReplicatedStorage.Framework.Logger)
local Net           = require(ReplicatedStorage.Framework.Net)
local Validate      = require(ReplicatedStorage.Framework.Validate)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)

local SCOPE = "EconomyService"

local EconomyService = {}
local dataService: any

local pendingTransactions: { [number]: boolean } = {}   -- mutex per UserId
local completedTransactions: { [string]: boolean } = {} -- idempotency set

local function isCurrency(c: string): boolean
	for _, v in EconomyConfig.CURRENCIES do
		if v == c then return true end
	end
	return false
end

local function getBal(player: Player): { [string]: number }?
	return dataService.get(player, "currency") :: { [string]: number }?
end

local function getInstancePart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function ensureMoneyChangerPrompt(inst: Instance)
	local part = getInstancePart(inst)
	if part == nil then return end
	if part:FindFirstChild(EconomyConfig.MONEY_CHANGER_PROMPT_NAME) then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = EconomyConfig.MONEY_CHANGER_PROMPT_NAME
	prompt.ActionText = "Exchange"
	prompt.ObjectText = "Money Changer"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = EconomyConfig.MONEY_CHANGER_RANGE
	prompt.Parent = part
end

local function ensureStudioMoneyChangerFallback()
	if not EconomyConfig.MONEY_CHANGER_FALLBACK_IN_STUDIO or not RunService:IsStudio() then return end
	if #CollectionService:GetTagged(EconomyConfig.MONEY_CHANGER_TAG) > 0 then return end

	local existing = workspace:FindFirstChild("MoneyChangerSpot")
	local spot: BasePart
	if existing and existing:IsA("BasePart") then
		spot = existing
	else
		local part = Instance.new("Part")
		part.Name = "MoneyChangerSpot"
		part.Size = Vector3.new(4, 1, 4)
		part.Anchored = true
		part.CanCollide = true
		part.Color = Color3.fromRGB(92, 92, 92)
		part.Material = Enum.Material.SmoothPlastic
		part.Position = Vector3.new(0, 2, 0)
		part.Parent = workspace
		spot = part
	end

	CollectionService:AddTag(spot, EconomyConfig.MONEY_CHANGER_TAG)
	ensureMoneyChangerPrompt(spot)
	Logger.warn(SCOPE, "Created Studio fallback MoneyChangerSpot; replace with a tagged map NPC/spot before content lock")
end

function EconomyService:Init()
	dataService = Loader.get("DataService")
end

function EconomyService:Start()
	Net.registerClientEvent("UpdateCurrencyDisplay")

	ensureStudioMoneyChangerFallback()
	for _, inst in CollectionService:GetTagged(EconomyConfig.MONEY_CHANGER_TAG) do
		ensureMoneyChangerPrompt(inst)
	end
	CollectionService:GetInstanceAddedSignal(EconomyConfig.MONEY_CHANGER_TAG):Connect(ensureMoneyChangerPrompt)

	Net.registerEvent("RequestExchange",
		Validate.shape({
			from   = Validate.literal(EconomyConfig.CURRENCIES),
			amount = Validate.positiveInteger,
		}),
		{ rate = EconomyConfig.TRANSACTION_RATE }
	)
	Net.onEvent("RequestExchange", function(player: Player, payload: any)
		local p  = payload :: { from: string, amount: number }
		local to = EconomyConfig.DEFAULT_EXCHANGE_TARGET[p.from]
		if to == nil then
			Logger.warn(SCOPE, "No exchange target for: " .. p.from)
			Net.fireClient("RequestExchange", player, { ok = false, msg = "No exchange target" })
			return
		end
		if not EconomyService.isNearMoneyChanger(player) then
			Net.fireClient("RequestExchange", player, { ok = false, msg = "Too far from money changer" })
			return
		end
		local ok = EconomyService.exchange(player, p.from, to, p.amount)
		Net.fireClient("RequestExchange", player, {
			ok = ok,
			msg = ok and string.format("Exchanged %d %s", p.amount, p.from) or "Exchange failed",
		})
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		pendingTransactions[player.UserId] = nil
	end)

	-- Push the balance once the profile is ready so the currency HUD is correct on join
	-- (a returning player must see their mon immediately, not "Mon: —" until the next change).
	local function pushOnReady(player: Player)
		task.spawn(function()
			local waited = 0
			while dataService.getProfile(player) == nil and waited < 30 do
				task.wait(0.2); waited += 0.2
			end
			if dataService.getProfile(player) ~= nil then
				EconomyService.fireBalance(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(pushOnReady)
	for _, player in Players:GetPlayers() do pushOnReady(player) end
end

-- ── Server-only API (never exposed to client directly) ────────────────────────────

function EconomyService.isNearMoneyChanger(player: Player): boolean
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp == nil or not hrp:IsA("BasePart") then return false end

	for _, inst in CollectionService:GetTagged(EconomyConfig.MONEY_CHANGER_TAG) do
		local part = getInstancePart(inst)
		if part and (part.Position - hrp.Position).Magnitude <= EconomyConfig.MONEY_CHANGER_RANGE then
			return true
		end
	end
	return false
end

function EconomyService.addCurrency(player: Player, currency: string, amount: number)
	assert(isCurrency(currency), "Invalid currency: " .. currency)
	assert(amount > 0 and math.floor(amount) == amount, "Amount must be a positive integer")
	local bal = getBal(player)
	if bal == nil then Logger.warn(SCOPE, "addCurrency: no profile for " .. player.Name) return end
	bal[currency] = math.min((bal[currency] or 0) + amount, EconomyConfig.MAX_MON)
	dataService.set(player, "currency", bal)
	EconomyService.fireBalance(player)
end

function EconomyService.removeCurrency(player: Player, currency: string, amount: number): boolean
	assert(isCurrency(currency), "Invalid currency: " .. currency)
	assert(amount > 0 and math.floor(amount) == amount, "Amount must be a positive integer")
	local bal = getBal(player)
	if bal == nil then Logger.warn(SCOPE, "removeCurrency: no profile for " .. player.Name) return false end
	if (bal[currency] or 0) < amount then
		Logger.warn(SCOPE, string.format(
			"Insufficient %s (%d < %d) for %s", currency, bal[currency] or 0, amount, player.Name))
		return false
	end
	bal[currency] = bal[currency] - amount
	dataService.set(player, "currency", bal)
	EconomyService.fireBalance(player)
	return true
end

function EconomyService.exchange(player: Player, from: string, to: string, fromAmount: number): boolean
	assert(isCurrency(from) and isCurrency(to), "Invalid currency pair")
	assert(from ~= to, "Cannot exchange currency with itself")
	assert(fromAmount > 0 and math.floor(fromAmount) == fromAmount, "Amount must be positive integer")

	local rates = EconomyConfig.EXCHANGE_RATES[from]
	if rates == nil or rates[to] == nil then
		Logger.warn(SCOPE, "No rate for " .. from .. "→" .. to) return false
	end

	local rate      = rates[to]
	local rawOut    = math.floor(fromAmount / rate)
	if rawOut <= 0 then
		Logger.warn(SCOPE, "Exchange too small: " .. fromAmount .. " " .. from .. " yields 0 " .. to)
		return false
	end

	local fee    = math.floor(rawOut * EconomyConfig.CHANGER_FEE)
	local netOut = rawOut - fee  -- fee is destroyed (gold sink)

	local bal = getBal(player)
	if bal == nil then return false end
	if (bal[from] or 0) < fromAmount then
		Logger.warn(SCOPE, "Insufficient " .. from .. " for exchange: " .. player.Name) return false
	end

	bal[from] = bal[from] - fromAmount
	bal[to]   = math.min((bal[to] or 0) + netOut, EconomyConfig.MAX_MON)
	dataService.set(player, "currency", bal)

	Logger.info(SCOPE, string.format(
		"Exchange: %s | %d %s → %d %s (fee=%d)", player.Name, fromAmount, from, netOut, to, fee))
	EconomyService.fireBalance(player)
	return true
end

function EconomyService.transfer(
	fromPlayer: Player, toPlayer: Player,
	currency: string, amount: number, transactionId: string
): boolean
	assert(isCurrency(currency), "Invalid currency: " .. currency)
	assert(amount > 0 and math.floor(amount) == amount, "Amount must be positive integer")

	if completedTransactions[transactionId] then
		Logger.info(SCOPE, "Duplicate transaction ignored: " .. transactionId)
		return true
	end

	local uid = fromPlayer.UserId
	if pendingTransactions[uid] then
		Logger.warn(SCOPE, "Concurrent transfer rejected for " .. fromPlayer.Name) return false
	end

	local bal = getBal(fromPlayer)
	if bal == nil or (bal[currency] or 0) < amount then
		Logger.warn(SCOPE, "Insufficient " .. currency .. " from " .. fromPlayer.Name) return false
	end

	pendingTransactions[uid] = true
	local success = false
	Logger.try(SCOPE .. "/transfer", function()
		local ok = EconomyService.removeCurrency(fromPlayer, currency, amount)
		if not ok then error("removeCurrency failed") end
		EconomyService.addCurrency(toPlayer, currency, amount)
		completedTransactions[transactionId] = true
		success = true
	end)
	pendingTransactions[uid] = nil  -- always clears; Logger.try catches errors above

	if success then
		Logger.info(SCOPE, string.format(
			"Transfer: %s→%s | %d %s | id=%s",
			fromPlayer.Name, toPlayer.Name, amount, currency, transactionId))
	end
	return success
end

function EconomyService.getBalance(player: Player): { [string]: number }?
	return getBal(player)
end

function EconomyService.fireBalance(player: Player)
	local bal = getBal(player)
	if bal then Net.fireClient("UpdateCurrencyDisplay", player, bal) end
end

return EconomyService
