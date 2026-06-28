--!strict
-- ModuleScript: ReplicatedStorage.Config.Constants
-- All global tunables. No magic numbers anywhere in service code.

local Constants = {}

Constants.DEFAULT_REMOTE_RATE = 10   -- max remote calls/sec per player per event
Constants.BURST              = 20   -- token bucket burst capacity
Constants.MAX_MON            = 9_999_999  -- hard currency cap
Constants.AUTOSAVE_INTERVAL  = 300  -- profile auto-save interval (seconds)

return Constants
