--!strict
-- ModuleScript: ReplicatedStorage.Config.FeelConfig
-- Layer 4 — all game-feel tunables in one place. Server reads only WITNESS_RADIUS;
-- everything else is consumed by the client FeelController. Big effects on big
-- moments (kills/executions/parries), small on chip hits.

export type ShakePreset = { magnitude: number, roughness: number, fadeIn: number, fadeOut: number }
export type PunchPreset = { pos: number, pitch: number }
export type MarkerStyle = { color: Color3, size: number }

local FeelConfig = {}

-- How far witnesses (non-participants) still receive cosmetic cues from the server.
FeelConfig.WITNESS_RADIUS = 60

-- ── Hitstop (seconds the local impact frame freezes) ──────────────────────────
FeelConfig.hitstop = {
	lightHit = 0.04,
	heavyHit = 0.08,
	parry    = 0.12,
	kill     = 0.18,
	execute  = 0.0,   -- slow-mo handles the execute beat instead of a freeze
}

-- ── Camera shake presets ──────────────────────────────────────────────────────
FeelConfig.shake = {
	lightHit = { magnitude = 0.55, roughness = 8,  fadeIn = 0.02, fadeOut = 0.25 },
	heavyHit = { magnitude = 1.40, roughness = 10, fadeIn = 0.02, fadeOut = 0.40 },
	parry    = { magnitude = 1.00, roughness = 15, fadeIn = 0.00, fadeOut = 0.30 },
	kill     = { magnitude = 2.40, roughness = 9,  fadeIn = 0.02, fadeOut = 0.60 },
	execute  = { magnitude = 2.00, roughness = 6,  fadeIn = 0.05, fadeOut = 0.90 },
	block    = { magnitude = 0.40, roughness = 8,  fadeIn = 0.00, fadeOut = 0.20 },
} :: { [string]: ShakePreset }

-- ── Execution slow-mo (LOCAL anim speed + camera/post only) ───────────────────
FeelConfig.executionSlowmo = {
	timeScale = 0.35,  -- anim tracks slowed to this
	duration  = 1.4,   -- held seconds at slow speed
	easeIn    = 0.15,
	easeOut   = 0.5,
	fovKick   = 8,     -- degrees of zoom-in during the beat
	desat     = 0.6,   -- ColorCorrection saturation drop (0..1)
}

-- ── Blood (stylized, bright, brief — NOT realistic gore) ──────────────────────
FeelConfig.blood = {
	-- spray particle burst count per severity
	spray   = { chip = 6, light = 12, heavy = 24, kill = 44, execute = 75 },
	poolOnKill = true,        -- fading pool decal under the body on kill/execute
	color      = Color3.fromRGB(150, 20, 18),
	lifetime   = 0.45,        -- particle lifetime (short)
	speed      = 20,          -- spray speed away from attacker
	poolLifetime = 6,
}

-- ── Camera punch (directional kick away from impact, springs back) ────────────
FeelConfig.punch = {
	lightHit = { pos = 0.15, pitch = 0.02 },
	heavyHit = { pos = 0.50, pitch = 0.06 },
	parry    = { pos = 0.30, pitch = 0.05 },
	kill     = { pos = 0.90, pitch = 0.10 },
	execute  = { pos = 1.20, pitch = 0.12 },
	block    = { pos = 0.10, pitch = 0.01 },
} :: { [string]: PunchPreset }

-- ── Hit-marker styles (attacker-only on-screen marker) ────────────────────────
FeelConfig.hitMarker = {
	normal = { color = Color3.fromRGB(235, 235, 235), size = 16 },
	heavy  = { color = Color3.fromRGB(255, 205, 150), size = 22 },
	parry  = { color = Color3.fromRGB(235, 200, 90),  size = 24 }, -- gold
	kill   = { color = Color3.fromRGB(205, 40, 35),   size = 28 }, -- red
} :: { [string]: MarkerStyle }

-- ── Sounds (PLACEHOLDERS — shipped rbxasset built-ins so they always load; swap for
-- final owned SFX later. All plays are pcall-guarded, so a bad id never errors.) ─
FeelConfig.sounds = {
	hit     = "rbxasset://sounds/electronicpingshort.wav",  -- flesh hit (placeholder)
	heavy   = "rbxasset://sounds/electronicpingshort.wav",  -- heavy thud (placeholder)
	parry   = "rbxasset://sounds/electronicpingshort.wav",  -- steel "ting" (placeholder)
	kill    = "rbxasset://sounds/electronicpingshort.wav",  -- thud (placeholder)
	execute = "rbxasset://sounds/electronicpingshort.wav",  -- low boom (placeholder)
	block   = "rbxasset://sounds/electronicpingshort.wav",
} :: { [string]: string }

-- When a swing animation has no "Impact" KeyframeMarker, time feedback this many
-- seconds after the swing starts (see Step 4 / CLAUDE.md marker convention).
FeelConfig.swingFallbackDelay = 0.2

return FeelConfig
