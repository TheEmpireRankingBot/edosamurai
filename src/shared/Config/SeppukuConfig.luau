--!strict
-- ModuleScript: ReplicatedStorage.Config.SeppukuConfig
-- All seppuku / lineage inheritance tunables live here.

local SeppukuConfig = {}

SeppukuConfig.SEPPUKU_INHERITANCE_RATE = 0.75

-- Five unsanctioned aggression flags means the player has repeatedly chosen violence,
-- not merely clipped someone once. This is the disgrace threshold for seppuku prompts.
SeppukuConfig.DISGRACE_NOTORIETY_THRESHOLD = 5

-- A recent real attacker blocks voluntary/disgrace seppuku so players cannot use it
-- to escape an active fight. Duel-loss seppuku is checked separately while downed.
SeppukuConfig.ACTIVE_ATTACKER_WINDOW = 10
SeppukuConfig.ACTIVE_ATTACKER_RADIUS = 35

-- Placeholder client hook duration. No production animation asset is required yet.
SeppukuConfig.SEPPUKU_ANIM_WINDUP = 1.2

SeppukuConfig.RequestSources = { "voluntary" } :: { string }

return SeppukuConfig
