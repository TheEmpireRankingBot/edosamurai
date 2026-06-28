--!strict
-- ModuleScript: ReplicatedStorage.Framework.Loader
-- Two-phase service/controller loader.
-- Init phase: wire dependencies only (no cross-service calls).
-- Start phase: safe to call other services.
-- Any Init failure halts the game loudly — never start half-initialised.

local Logger = require(script.Parent.Logger)

type Service = {
	Init:  ((self: Service) -> ())?,
	Start: ((self: Service) -> ())?,
	[string]: any,
}

type Entry = { name: string, module: Service }

local Loader = {}
local registry: { [string]: Service } = {}

function Loader.load(folder: Instance)
	local entries: { Entry } = {}

	-- Require phase: load every ModuleScript in the folder
	for _, child in folder:GetChildren() do
		if not child:IsA("ModuleScript") then continue end
		local name = child.Name
		local ok = Logger.try("Loader", function()
			local m = require(child :: ModuleScript) :: Service
			registry[name] = m
			table.insert(entries, { name = name, module = m })
		end)
		if not ok then
			error("[Loader] FATAL: require failed for '" .. name .. "' — halting", 2)
		end
	end

	-- Init phase: wire dependencies (order = load order)
	for _, entry in entries do
		if entry.module.Init then
			local ok = Logger.try("Loader/" .. entry.name, function()
				entry.module:Init()
			end)
			if not ok then
				error("[Loader] FATAL: Init() failed for '" .. entry.name .. "' — halting", 2)
			end
		end
	end

	-- Start phase: safe to call other services
	for _, entry in entries do
		if entry.module.Start then
			Logger.try("Loader/" .. entry.name, function()
				entry.module:Start()
			end)
		end
		Logger.info("Loader", entry.name .. " online")
	end
end

-- Retrieve a service by name. Only valid after Loader.load() has run.
function Loader.get(name: string): Service
	local m = registry[name]
	assert(m ~= nil, "[Loader] Service '" .. name .. "' not found — did you load it first?")
	return m
end

return Loader
