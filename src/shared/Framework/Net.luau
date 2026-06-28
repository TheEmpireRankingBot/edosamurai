--!strict
-- ModuleScript: ReplicatedStorage.Framework.Net
-- Anti-exploit networking backbone. ALL remotes route through here.
-- Never create a raw RemoteEvent or RemoteFunction outside this module.

local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger   = require(script.Parent.Logger)
local Validate = require(script.Parent.Validate)
local Constants = require(script.Parent.Parent.Config.Constants)

local IS_SERVER = RunService:IsServer()

-- ── Token Bucket ────────────────────────────────────────────────────────────────

type Bucket = { tokens: number, lastRefill: number }
local buckets: { [string]: Bucket } = {}

local function bucketKey(eventName: string, userId: number): string
	return eventName .. "|" .. tostring(userId)
end

local function consumeToken(eventName: string, userId: number, rate: number, burst: number): boolean
	local key = bucketKey(eventName, userId)
	local now = os.clock()
	local b   = buckets[key]
	if b == nil then
		buckets[key] = { tokens = burst - 1, lastRefill = now }
		return true
	end
	b.tokens    = math.min(burst, b.tokens + (now - b.lastRefill) * rate)
	b.lastRefill = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

local function purgeBucketsForUser(userId: number)
	local suffix = "|" .. tostring(userId)
	local dead: { string } = {}
	for key in buckets do
		if string.sub(key, -#suffix) == suffix then
			table.insert(dead, key)
		end
	end
	for _, k in dead do buckets[k] = nil end
end

-- ── Remotes Folder ──────────────────────────────────────────────────────────────

local remotesFolder: Folder
if IS_SERVER then
	local ex = ReplicatedStorage:FindFirstChild("Remotes")
	if ex and ex:IsA("Folder") then
		remotesFolder = ex :: Folder
	else
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name   = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		purgeBucketsForUser(player.UserId)
	end)
else
	local found = ReplicatedStorage:WaitForChild("Remotes", 15)
	if found == nil or not found:IsA("Folder") then
		error("[Net] Remotes folder not found within 15 s — server init may have failed")
	end
	remotesFolder = found :: Folder
end

-- ── Types ─────────────────────────────────────────────────────────────────────

export type Validator    = (...any) -> (boolean, string?)
export type ServerHandler = (player: Player, ...any) -> ()
type EventOpts           = { rate: number? }
type FunctionOpts        = { rate: number?, timeout: number? }

local eventHandlers:     { [string]: ServerHandler }            = {}
local registeredEvents:  { [string]: RemoteEvent }              = {}
local registeredFunctions: { [string]: RemoteFunction }         = {}

local Net = {}

-- ── Server API ─────────────────────────────────────────────────────────────────

function Net.registerEvent(name: string, validator: Validator, opts: EventOpts?)
	assert(IS_SERVER,               "Net.registerEvent is server-only")
	assert(registeredEvents[name] == nil, "Event already registered: " .. name)

	local rate  = (opts and opts.rate) or Constants.DEFAULT_REMOTE_RATE
	local burst = Constants.BURST

	local remote = Instance.new("RemoteEvent")
	remote.Name   = name
	remote.Parent = remotesFolder
	registeredEvents[name] = remote

	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		local packed = table.pack(...)
		-- 1. Rate limit
		if not consumeToken(name, player.UserId, rate, burst) then
			Logger.warn("Net", "Rate limit hit: " .. name .. " from " .. player.Name)
			return
		end
		-- 2. Validate arguments
		local ok, err = validator(table.unpack(packed, 1, packed.n))
		if not ok then
			Logger.warn("Net",
				"Validation failed: " .. name .. " from " .. player.Name .. " — " .. tostring(err))
			return
		end
		-- 3. Dispatch to registered handler
		local handler = eventHandlers[name]
		if handler then
			Logger.try("Net/" .. name, function()
				handler(player, table.unpack(packed, 1, packed.n))
			end)
		else
			Logger.warn("Net", "No handler for event: " .. name)
		end
	end)

	Logger.info("Net", "Event registered: " .. name)
end

function Net.onEvent(name: string, handler: ServerHandler)
	assert(IS_SERVER, "Net.onEvent is server-only")
	eventHandlers[name] = handler
end

function Net.fireClient(name: string, player: Player, ...: any)
	assert(IS_SERVER, "Net.fireClient is server-only")
	local remote = registeredEvents[name]
	assert(remote, "No registered event: " .. name)
	remote:FireClient(player, ...)
end

function Net.fireAllClients(name: string, ...: any)
	assert(IS_SERVER, "Net.fireAllClients is server-only")
	local remote = registeredEvents[name]
	assert(remote, "No registered event: " .. name)
	remote:FireAllClients(...)
end

function Net.registerFunction(
	name:      string,
	validator: Validator,
	handler:   (player: Player, ...any) -> ...any,
	opts:      FunctionOpts?
)
	assert(IS_SERVER,                   "Net.registerFunction is server-only")
	assert(registeredFunctions[name] == nil, "Function already registered: " .. name)

	local rate  = (opts and opts.rate) or Constants.DEFAULT_REMOTE_RATE
	local burst = Constants.BURST

	local remote = Instance.new("RemoteFunction")
	remote.Name   = name
	remote.Parent = remotesFolder
	registeredFunctions[name] = remote

	remote.OnServerInvoke = function(player: Player, ...: any): ...any
		local packed = table.pack(...)
		if not consumeToken(name, player.UserId, rate, burst) then
			Logger.warn("Net", "Rate limit hit for function: " .. name .. " from " .. player.Name)
			return nil
		end
		local ok, err = validator(table.unpack(packed, 1, packed.n))
		if not ok then
			Logger.warn("Net",
				"Validation failed for function: " .. name .. " from " .. player.Name .. " — " .. tostring(err))
			return nil
		end
		return handler(player, table.unpack(packed, 1, packed.n))
	end

	Logger.info("Net", "Function registered: " .. name)
end

-- Server-only: create a RemoteEvent used only for server→client fires.
-- Use when there is no incoming client handler needed.
function Net.registerClientEvent(name: string)
	assert(IS_SERVER, "Net.registerClientEvent is server-only")
	assert(registeredEvents[name] == nil, "Event already registered: " .. name)
	local remote = Instance.new("RemoteEvent")
	remote.Name   = name
	remote.Parent = remotesFolder
	registeredEvents[name] = remote
	Logger.info("Net", "Client event registered: " .. name)
end

-- ── Client API ────────────────────────────────────────────────────────────────

function Net.onClientEvent(name: string, handler: (...any) -> ())
	assert(not IS_SERVER, "Net.onClientEvent is client-only")
	local remote = remotesFolder:WaitForChild(name, 10) :: RemoteEvent
	if remote == nil then Logger.error("Net", "Remote not found: " .. name) return end
	remote.OnClientEvent:Connect(handler)
end

function Net.fireServer(name: string, ...: any)
	assert(not IS_SERVER, "Net.fireServer is client-only")
	local remote = remotesFolder:WaitForChild(name, 10) :: RemoteEvent
	if remote == nil then Logger.error("Net", "Remote not found: " .. name) return end
	remote:FireServer(...)
end

function Net.invokeServer(name: string, ...: any): ...any
	assert(not IS_SERVER, "Net.invokeServer is client-only")
	local remote = remotesFolder:WaitForChild(name, 10) :: RemoteFunction
	if remote == nil then Logger.error("Net", "RemoteFunction not found: " .. name) return nil end
	return remote:InvokeServer(...)
end

return Net
