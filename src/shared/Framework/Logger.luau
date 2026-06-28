--!strict
-- ModuleScript: ReplicatedStorage.Framework.Logger
-- Structured logging with per-scope prefixes and a safe pcall wrapper.

local Logger = {}

type LogData = any?

local function fmt(level: string, scope: string, msg: string, data: LogData): string
	local base = string.format("[%s][%s] %s", scope, level, msg)
	if data ~= nil then
		base = base .. " | " .. tostring(data)
	end
	return base
end

function Logger.info(scope: string, msg: string, data: LogData)
	print(fmt("INFO", scope, msg, data))
end

function Logger.warn(scope: string, msg: string, data: LogData)
	warn(fmt("WARN", scope, msg, data))
end

function Logger.error(scope: string, msg: string, data: LogData)
	warn(fmt("ERROR", scope, msg, data))
end

-- Wraps fn in pcall, logs the stack trace on failure, returns success.
-- Use this everywhere instead of bare pcall.
function Logger.try(scope: string, fn: () -> ()): boolean
	local ok, err = pcall(fn)
	if not ok then
		Logger.error(scope, "pcall failed: " .. tostring(err))
	end
	return ok
end

return Logger
