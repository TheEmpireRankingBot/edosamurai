--!strict
-- ModuleScript: ReplicatedStorage.Framework.Validate
-- Runtime type guards for remote arguments.
-- Note: the `t` library (osyris/t) is a production-ready drop-in alternative.

export type Guard = (v: any) -> (boolean, string?)

local Validate = {}

function Validate.string(v: any): (boolean, string?)
	if type(v) == "string" then return true, nil end
	return false, "expected string, got " .. type(v)
end

function Validate.number(v: any): (boolean, string?)
	if type(v) == "number" then return true, nil end
	return false, "expected number, got " .. type(v)
end

function Validate.integer(v: any): (boolean, string?)
	if type(v) ~= "number" then
		return false, "expected integer, got " .. type(v)
	end
	local n = v :: number
	if n ~= n then return false, "NaN is not a valid integer" end
	if n == math.huge or n == -math.huge then return false, "infinity is not a valid integer" end
	if math.floor(n) ~= n then return false, "expected integer, got float (" .. tostring(n) .. ")" end
	return true, nil
end

function Validate.positiveInteger(v: any): (boolean, string?)
	local ok, err = Validate.integer(v)
	if not ok then return false, err end
	if (v :: number) <= 0 then
		return false, "expected positive integer, got " .. tostring(v)
	end
	return true, nil
end

function Validate.boolean(v: any): (boolean, string?)
	if type(v) == "boolean" then return true, nil end
	return false, "expected boolean, got " .. type(v)
end

function Validate.table(v: any): (boolean, string?)
	if type(v) == "table" then return true, nil end
	return false, "expected table, got " .. type(v)
end

function Validate.vector(v: any): (boolean, string?)
	if typeof(v) == "Vector3" then return true, nil end
	return false, "expected Vector3, got " .. typeof(v)
end

function Validate.instanceOf(className: string): Guard
	return function(v: any): (boolean, string?)
		if typeof(v) == "Instance" and (v :: Instance):IsA(className) then
			return true, nil
		end
		return false, "expected Instance:" .. className .. ", got " .. typeof(v)
	end
end

function Validate.player(v: any): (boolean, string?)
	return Validate.instanceOf("Player")(v)
end

function Validate.shape(schema: { [string]: Guard }): Guard
	return function(v: any): (boolean, string?)
		if type(v) ~= "table" then
			return false, "shape: expected table, got " .. type(v)
		end
		local t = v :: { [string]: any }
		for field, guard in schema do
			local ok, err = guard(t[field])
			if not ok then
				return false, "field '" .. field .. "': " .. (err or "invalid")
			end
		end
		return true, nil
	end
end

function Validate.literal(allowed: { any }): Guard
	return function(v: any): (boolean, string?)
		for _, a in allowed do
			if v == a then return true, nil end
		end
		return false, "'" .. tostring(v) .. "' not in allowed set"
	end
end

return Validate
