--!strict
-- ModuleScript: ServerScriptService.Services.CombatService
-- Server-authoritative melee combat. Clients only REQUEST; the server decides.
--
-- The soul of the game lives in enterDowned -> resolveDownedChoice: sparing grants
-- Gi, executing grants Shura. The Shura damageBonus is a TEMPTATION (power now,
-- corruption later) read from MoralityService. DuelService is the anti-griefing gate.

local Players    = game:GetService("Players")
local RunService  = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader       = require(ReplicatedStorage.Framework.Loader)
local Logger       = require(ReplicatedStorage.Framework.Logger)
local Net          = require(ReplicatedStorage.Framework.Net)
local Validate     = require(ReplicatedStorage.Framework.Validate)
local CombatConfig  = require(ReplicatedStorage.Config.CombatConfig)
local FeelConfig    = require(ReplicatedStorage.Config.FeelConfig)
local SeppukuConfig = require(ReplicatedStorage.Config.SeppukuConfig)

local SCOPE = "CombatService"

local CombatService = {}

-- tiny signal so other services (e.g. PriestService) can react to lethal events
local function newSignal(): any
	local listeners: { (...any) -> () } = {}
	local sig = {}
	function sig:Connect(fn: (...any) -> ())
		table.insert(listeners, fn)
	end
	function sig:Fire(...: any)
		for _, fn in listeners do task.spawn(fn, ...) end
	end
	return sig
end

-- Fires (kind: "down"|"kill", victim, attacker, position) for kegare / live-ops hooks.
CombatService.onLethalEvent = newSignal()

local dataService:     any
local duelService:     any
local factionService:  any
local moralityService: any
local priestService:   any

export type CombatState = {
	health:          number,
	stamina:         number,
	isBlocking:      boolean,
	blockStartTime:  number,
	isDodging:       boolean,
	dodgeEndsAt:     number,
	lastDodgeAt:     number,
	isDowned:        boolean,
	downedBy:        Player?,
	downedAt:        number,
	downToken:       number,
	lastDamagedBy:   Player?,
	lastDamagedAt:   number,
	isStaggered:     boolean,
	staggerEndsAt:   number,
	isDead:          boolean,
	lastSwingAt:     number,
	lastActionAt:    number,
	baseWalkSpeed:   number,
	baseJumpPower:   number,
	baseJumpHeight:  number,
	lastStaminaPush: number,
}

local states:         { [number]: CombatState } = {}
local pendingRespawn: { [number]: boolean }     = {}

-- ── Local helpers ───────────────────────────────────────────────────────
local function getHRP(player: Player): BasePart?
	local char = player.Character
	return (char and char:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	return (char and char:FindFirstChildOfClass("Humanoid")) :: Humanoid?
end

-- Mirror server-authoritative health onto the Humanoid for the health bar / ragdoll.
-- Never lets the Humanoid hit 0 from melee (that is what the downed state is for) —
-- only CombatService.kill sets Humanoid.Health = 0.
local function mirrorHealth(player: Player)
	local s   = states[player.UserId]
	local hum = getHumanoid(player)
	if s == nil or hum == nil then return end
	if s.isDead then return end
	if s.isDowned then
		hum.Health = math.min(hum.MaxHealth, 1)
	else
		hum.Health = math.clamp(s.health, 1, CombatConfig.MAX_HEALTH)
	end
end

-- ── Layer 4: game-feel cue broadcast (cosmetic only; never affects the sim) ──
-- Fires "CombatFeel" to attacker, target, and witnesses within WITNESS_RADIUS.
-- Participants may receive input-affecting cues (hitstop/slow-mo); witnesses are
-- flagged isParticipant=false and get shake/VFX/sound only.
function CombatService._emitFeel(kind: string, attacker: Player, target: Player?, position: Vector3, severity: string)
	for _, p in Players:GetPlayers() do
		local isParticipant = (p == attacker) or (target ~= nil and p == target)
		local include = isParticipant
		if not include then
			local phrp = getHRP(p)
			if phrp ~= nil and (phrp.Position - position).Magnitude <= FeelConfig.WITNESS_RADIUS then
				include = true
			end
		end
		if include then
			Net.fireClient("CombatFeel", p, {
				kind          = kind,
				attackerId    = attacker.UserId,
				targetId      = target ~= nil and target.UserId or nil,
				position      = position,
				severity      = severity,
				isParticipant = isParticipant,
			})
		end
	end
end

-- ── Queries ──────────────────────────────────────────────────────────
function CombatService.getState(player: Player): CombatState?
	return states[player.UserId]
end

function CombatService.isAlive(player: Player): boolean
	local s = states[player.UserId]
	return s ~= nil and not s.isDowned and not s.isDead and s.health > 0
end

function CombatService.isDowned(player: Player): boolean
	local s = states[player.UserId]
	return s ~= nil and s.isDowned
end

function CombatService.getDownedBy(player: Player): Player?
	local s = states[player.UserId]
	return if s ~= nil then s.downedBy else nil
end

function CombatService.hasActiveAttacker(player: Player): boolean
	local s = states[player.UserId]
	if s == nil or s.isDead then return false end
	local attacker = if s.isDowned then s.downedBy else s.lastDamagedBy
	local damagedAt = if s.isDowned then s.downedAt else s.lastDamagedAt
	if attacker == nil or attacker.Parent == nil then return false end
	if os.clock() - damagedAt > SeppukuConfig.ACTIVE_ATTACKER_WINDOW then return false end
	local attackerState = states[attacker.UserId]
	if attackerState == nil or attackerState.isDead then return false end
	local myHrp = getHRP(player)
	local attackerHrp = getHRP(attacker)
	if myHrp ~= nil and attackerHrp ~= nil
		and (myHrp.Position - attackerHrp.Position).Magnitude > SeppukuConfig.ACTIVE_ATTACKER_RADIUS then
		return false
	end
	return true
end

-- not staggered, not downed, swing cooldown elapsed, has stamina for the weapon
function CombatService.canAttack(attacker: Player): boolean
	local s = states[attacker.UserId]
	if s == nil then return false end
	if s.isDowned or s.isStaggered or s.isDead then return false end
	local equipped   = dataService.get(attacker, "equipped") :: any
	local weaponName = (equipped and equipped.weapon) or "Unarmed"
	local weapon     = CombatConfig.Weapons[weaponName]
	if weapon == nil then return false end
	if os.clock() - s.lastSwingAt < weapon.swingCooldown then return false end
	if s.stamina < weapon.staminaCost then return false end
	return true
end

-- ── Stamina push (throttled) ───────────────────────────────────────────
function CombatService._pushStamina(player: Player)
	local s = states[player.UserId]
	if s == nil then return end
	s.lastStaminaPush = os.clock()
	Net.fireClient("StaminaUpdate", player, { stamina = s.stamina, max = CombatConfig.MAX_STAMINA })
end

-- ── Counterplay state setters ─────────────────────────────────────────
function CombatService.setBlocking(player: Player, active: boolean)
	local s = states[player.UserId]
	if s == nil then return end
	if s.isDowned or s.isStaggered or s.isDead then
		s.isBlocking = false
		return
	end
	if active and not s.isBlocking then
		s.blockStartTime = os.clock()
	end
	s.isBlocking   = active
	s.lastActionAt = os.clock()
end

function CombatService.attemptDodge(player: Player)
	local s = states[player.UserId]
	if s == nil then return end
	if s.isDowned or s.isStaggered or s.isDead then return end
	local now = os.clock()
	if now - s.lastDodgeAt < CombatConfig.DODGE_COOLDOWN then return end
	if s.stamina < CombatConfig.DODGE_STAMINA then return end
	s.isDodging    = true
	s.dodgeEndsAt  = now + CombatConfig.DODGE_IFRAMES
	s.lastDodgeAt  = now
	s.stamina      = math.max(0, s.stamina - CombatConfig.DODGE_STAMINA)
	s.lastActionAt = now
	Net.fireClient("CombatFeedback", player, { event = "dodge", duration = CombatConfig.DODGE_IFRAMES })
	CombatService._pushStamina(player)
end

function CombatService._applyStagger(player: Player, duration: number)
	local s = states[player.UserId]
	if s == nil or s.isDead then return end
	s.isStaggered   = true
	s.staggerEndsAt = os.clock() + duration
	s.isBlocking    = false
	local hum = getHumanoid(player)
	if hum and not s.isDowned then
		hum.WalkSpeed = 0
	end
	Net.fireClient("CombatFeedback", player, { event = "staggered", duration = duration })
end

-- ── Gap-zone detection ──────────────────────────────────────────────
function CombatService._isGapHit(target: Player, hitPosition: Vector3): boolean
	local char = target.Character
	if char == nil then return false end
	for _, d in char:GetDescendants() do
		if d:IsA("Attachment") and d.Name == CombatConfig.GAP_ATTACHMENT_NAME then
			if ((d :: Attachment).WorldPosition - hitPosition).Magnitude <= CombatConfig.GAP_RADIUS then
				return true
			end
		end
	end
	return false
end

-- ── The exploit-critical path ────────────────────────────────────────
function CombatService.resolveHit(attacker: Player, target: Player, weaponType: string, hitPosition: Vector3)
	if attacker == target then return end
	local aState = states[attacker.UserId]
	local tState = states[target.UserId]
	if aState == nil or tState == nil then return end

	-- (1) liveness: both alive, attacker not downed/staggered
	if aState.isDowned or aState.isStaggered or aState.isDead then return end
	if not CombatService.isAlive(attacker) then return end
	if not CombatService.isAlive(target) then return end  -- cannot melee a downed/dead target

	local weapon = CombatConfig.Weapons[weaponType]
	if weapon == nil then
		Logger.warn(SCOPE, "Unknown weapon: " .. tostring(weaponType)) return
	end

	-- (3) equipped weapon must match the claimed weapon (anti-spoof)
	local aEquip = dataService.get(attacker, "equipped") :: any
	local equippedWeapon = (aEquip and aEquip.weapon) or "Unarmed"
	if equippedWeapon ~= weaponType then
		Logger.warn(SCOPE, string.format("%s weapon spoof: claims %s, has %s",
			attacker.Name, weaponType, tostring(equippedWeapon)))
		return
	end

	-- (4) swing cooldown + stamina
	if not CombatService.canAttack(attacker) then return end

	-- (2) distance / anti-reach exploit
	local aHRP = getHRP(attacker)
	local tHRP = getHRP(target)
	if aHRP == nil or tHRP == nil then return end
	local dist     = (aHRP.Position - tHRP.Position).Magnitude
	local maxReach = weapon.range + CombatConfig.RANGE_SLACK
	if dist > maxReach then
		Logger.warn(SCOPE, string.format("%s reach exploit rejected (%.1f > %.1f)",
			attacker.Name, dist, maxReach))
		return
	end

	-- context gate: safe zone / same-faction / duel rules (anti-griefing)
	if not duelService.canDamage(attacker, target) then
		Logger.warn(SCOPE, string.format("Hit rejected by canDamage: %s -> %s", attacker.Name, target.Name))
		return
	end

	-- COMMIT the swing: consume stamina + start cooldown (lands or not)
	local now = os.clock()
	aState.stamina      = math.max(0, aState.stamina - weapon.staminaCost)
	aState.lastSwingAt  = now
	aState.lastActionAt = now
	CombatService._pushStamina(attacker)

	-- dodge i-frames -> clean miss
	if tState.isDodging and now < tState.dodgeEndsAt then
		Net.fireClient("HitConfirmed", attacker, { result = "dodged", targetId = target.UserId })
		return
	end

	-- block / parry
	local blocked = false
	if tState.isBlocking then
		if now - tState.blockStartTime <= CombatConfig.PARRY_WINDOW then
			-- PARRY: full negate + stagger the attacker (riposte window)
			CombatService._applyStagger(attacker, CombatConfig.PARRY_STAGGER_DURATION)
			Logger.info(SCOPE, target.Name .. " PARRIED " .. attacker.Name)
			Net.fireClient("HitConfirmed", attacker, { result = "parried", targetId = target.UserId })
			Net.fireClient("CombatFeedback", target, { event = "parry" })
			CombatService._emitFeel("parry", attacker, target, hitPosition, "parry")
			return
		end
		blocked = true
	end

	-- accuracy penalty -> miss chance (the Shura temptation's cost)
	local mods    = moralityService.getCombatModifiers(attacker)
	local penalty = math.abs(mods.accuracyPenalty or 0)
	if priestService then
		penalty = math.max(0, penalty - priestService.getBuff(attacker, "accuracyOffset"))  -- Steady Hand omamori
	end
	if penalty > 0 and math.random() < penalty then
		Net.fireClient("HitConfirmed", attacker, { result = "miss", targetId = target.UserId })
		return
	end

	-- ── Damage calc: base -> armor -> block -> Shura bonus ──
	local damage = weapon.damage

	if not weapon.ignoresArmor then
		local tEquip   = dataService.get(target, "equipped") :: any
		local hasArmor = tEquip ~= nil and tEquip.armor ~= nil
		if hasArmor and not CombatService._isGapHit(target, hitPosition) then
			damage *= (1 - CombatConfig.ARMOR_DAMAGE_REDUCTION)
		end
	end

	if blocked then
		damage *= (1 - CombatConfig.BLOCK_DAMAGE_REDUCTION)
		tState.stamina      = math.max(0, tState.stamina - CombatConfig.BLOCK_STAMINA_PER_HIT)
		tState.lastActionAt = now
		CombatService._pushStamina(target)
		if tState.stamina <= 0 then
			CombatService._applyStagger(target, CombatConfig.STAGGER_DURATION)
			Net.fireClient("CombatFeedback", target, { event = "guardBreak" })
		end
	end

	damage *= (1 + (mods.damageBonus or 0))  -- Shura: power now, corruption later
	if priestService then
		local resist = priestService.getBuff(target, "damageResist")  -- Warding omamori
		if resist > 0 then damage *= (1 - resist) end
	end
	damage = math.floor(damage + 0.5)

	tState.health = math.max(0, tState.health - damage)
	tState.lastDamagedBy = attacker
	tState.lastDamagedAt = now
	Logger.info(SCOPE, string.format("%s hit %s for %d (hp=%d)",
		attacker.Name, target.Name, damage, tState.health))

	-- unsanctioned wilderness aggression -> notoriety/bounty stub (throttled in DuelService)
	duelService.flagAggression(attacker, target)

	Net.fireClient("HitConfirmed", attacker, { result = "hit", damage = damage, targetId = target.UserId })
	Net.fireClient("CombatFeedback", target, { event = "hurt", health = tState.health, blocked = blocked })

	if tState.health <= 0 then
		CombatService.enterDowned(target, attacker)
	else
		mirrorHealth(target)
		local sev = "light"
		if not blocked and (weapon.ignoresArmor or weapon.damage >= 50 or CombatService._isGapHit(target, hitPosition)) then
			sev = "heavy"
		end
		CombatService._emitFeel(blocked and "block" or "hit", attacker, target, hitPosition, sev)
	end
end

-- ── Downed ──────────────────────────────────────────────────────────
function CombatService.enterDowned(victim: Player, attacker: Player)
	local s = states[victim.UserId]
	if s == nil or s.isDowned or s.isDead then return end
	s.isDowned    = true
	s.downedBy    = attacker
	s.downedAt    = os.clock()
	s.health      = 0
	s.isBlocking  = false
	s.downToken  += 1
	local token   = s.downToken

	local hum = getHumanoid(victim)
	if hum then
		hum.WalkSpeed  = CombatConfig.CRAWL_SPEED
		hum.JumpPower  = 0
		hum.JumpHeight = 0
	end
	mirrorHealth(victim)

	Logger.info(SCOPE, attacker.Name .. " downed " .. victim.Name)
	Net.fireClient("ShowDownedPrompt", attacker, {
		victimId   = victim.UserId,
		victimName = victim.Name,
		duration   = CombatConfig.DOWNED_DURATION,
	})
	Net.fireClient("EnterDownedState", victim, {
		attackerId = attacker.UserId,
		duration   = CombatConfig.DOWNED_DURATION,
	})
	local dhrp = getHRP(victim)
	local dPos = dhrp ~= nil and dhrp.Position or Vector3.zero
	CombatService._emitFeel("down", attacker, victim, dPos, "heavy")
	CombatService.onLethalEvent:Fire("down", victim, attacker, dPos)

	-- Auto-spare (default to mercy) if the attacker fails to choose in time.
	-- Indecision is not honor: no Gi is granted; any duel ends as a yield.
	task.delay(CombatConfig.DOWNED_DURATION, function()
		local cur = states[victim.UserId]
		if cur and cur.isDowned and cur.downToken == token then
			Logger.info(SCOPE, "Auto-spare (timeout): " .. victim.Name)
			CombatService._revive(victim)
			if duelService.areDueling(attacker, victim) then
				duelService.endDuelBetween(attacker, victim, "yield")
			end
		end
	end)
end

function CombatService._revive(victim: Player)
	local s = states[victim.UserId]
	if s == nil then return end
	s.isDowned = false
	s.downedBy = nil
	s.isDead   = false
	s.health   = CombatConfig.SPARE_RECOVERY_HEALTH
	local hum = getHumanoid(victim)
	if hum then
		hum.WalkSpeed  = s.baseWalkSpeed
		hum.JumpPower  = s.baseJumpPower
		hum.JumpHeight = s.baseJumpHeight
	end
	mirrorHealth(victim)
	Net.fireClient("ExitDownedState", victim, { health = s.health })
end

function CombatService.resolveDownedChoice(attacker: Player, victim: Player, choice: string)
	local s = states[victim.UserId]
	if s == nil or not s.isDowned then return end
	if s.downedBy ~= attacker then
		Logger.warn(SCOPE, attacker.Name .. " tried to resolve a down they did not cause") return
	end
	if os.clock() - s.downedAt > CombatConfig.DOWNED_DURATION then
		Logger.warn(SCOPE, "Downed window expired for " .. victim.Name) return
	end
	s.downToken += 1  -- invalidate the auto-spare timer

	if choice == "execute" then
		local ehrp = getHRP(victim)
		CombatService._emitFeel("execute", attacker, victim, ehrp ~= nil and ehrp.Position or Vector3.zero, "kill")
		local wasDuel = duelService.areDueling(attacker, victim)
		CombatService.kill(victim, attacker, { wasHelpless = true, wasDuel = wasDuel })
		moralityService.applyKill(attacker, victim, {
			wasHelpless = true,
			wasFleeing  = false,
			wasDuel     = wasDuel,
			wasInTown   = duelService.inSafeZone(victim),
		})
	elseif choice == "spare" then
		Logger.info(SCOPE, attacker.Name .. " SPARED " .. victim.Name)
		local shrp = getHRP(victim)
		CombatService._emitFeel("spare", attacker, victim, shrp ~= nil and shrp.Position or Vector3.zero, "light")
		CombatService._revive(victim)
		moralityService.applyGi(attacker, "spareDowned")
		if duelService.areDueling(attacker, victim) then
			duelService.endDuelBetween(attacker, victim, "yield")
		end
	end
end

-- ── Kill / jisei / respawn ───────────────────────────────────────────
export type KillCtx = { wasHelpless: boolean, wasDuel: boolean? }

function CombatService.kill(victim: Player, killer: Player, ctx: KillCtx)
	local s = states[victim.UserId]
	if s == nil or s.isDead then return end
	s.isDowned = false
	s.isDead   = true
	s.health   = 0

	-- non-execute kill gets its own cue; executions already emitted "execute"
	if not ctx.wasHelpless then
		local khrp = getHRP(victim)
		CombatService._emitFeel("kill", killer, victim, khrp ~= nil and khrp.Position or Vector3.zero, "kill")
	end

	-- Stats: single writer. totalKills always; honorableKills if it was a sanctioned duel.
	local stats = (dataService.get(killer, "stats") :: any) or {}
	stats.totalKills = (stats.totalKills or 0) + 1
	if ctx.wasDuel then
		stats.honorableKills = (stats.honorableKills or 0) + 1
	end
	dataService.set(killer, "stats", stats)

	CombatService._broadcastJisei(victim)
	local lhrp = getHRP(victim)
	CombatService.onLethalEvent:Fire("kill", victim, killer, lhrp ~= nil and lhrp.Position or Vector3.zero)

	-- An execution is a kill, never an honorable win.
	if duelService.areDueling(killer, victim) then
		duelService.endDuelBetween(killer, victim, "death")
	end

	-- Schedule respawn at faction spawn (Players.RespawnTime = RESPAWN_DELAY).
	pendingRespawn[victim.UserId] = true
	local hum = getHumanoid(victim)
	if hum then
		hum.Health = 0  -- engine respawns after RESPAWN_DELAY -> CharacterAdded teleports to spawn
	end
	Logger.info(SCOPE, string.format("%s KILLED %s (duel=%s)",
		killer.Name, victim.Name, tostring(ctx.wasDuel == true)))
end

-- Lightweight weapon select. A full equipment system is a later layer; this lets the
-- combat loop be played/tested now. equipped.armor is left for that future layer / tests.
function CombatService.equipWeapon(player: Player, weaponName: string)
	if CombatConfig.Weapons[weaponName] == nil then return end
	local equipped = (dataService.get(player, "equipped") :: any) or {}
	equipped.weapon = weaponName
	dataService.set(player, "equipped", equipped)
	Net.fireClient("CombatLoadout", player, { weapon = weaponName })
	Logger.info(SCOPE, player.Name .. " equipped " .. weaponName)
end

function CombatService.performCleanDeath(victim: Player, reason: string)
	local s = states[victim.UserId]
	if s == nil or s.isDead then return end
	s.isDowned = false
	s.downedBy = nil
	s.downToken += 1
	s.isDead = true
	s.health = 0
	s.isBlocking = false

	local hrp = getHRP(victim)
	local pos = hrp ~= nil and hrp.Position or Vector3.zero
	CombatService._broadcastJisei(victim)
	CombatService.onLethalEvent:Fire(reason, victim, victim, pos)
	pendingRespawn[victim.UserId] = true

	local hum = getHumanoid(victim)
	if hum then
		hum.WalkSpeed = s.baseWalkSpeed
		hum.JumpPower = s.baseJumpPower
		hum.JumpHeight = s.baseJumpHeight
		hum.Health = 0
	end
	Net.fireClient("ExitDownedState", victim, { health = 0 })
	Logger.info(SCOPE, string.format("%s clean death (%s)", victim.Name, reason))
end

function CombatService._broadcastJisei(victim: Player)
	local poem = (dataService.get(victim, "jiseiPoem") :: string?) or ""
	if poem == "" then poem = CombatConfig.DEFAULT_JISEI end
	local hrp    = getHRP(victim)
	local origin = hrp and hrp.Position
	for _, p in Players:GetPlayers() do
		local include = (p == victim)  -- the dying player always sees their own poem
		if not include and origin then
			local phrp = getHRP(p)
			if phrp and (phrp.Position - origin).Magnitude <= CombatConfig.JISEI_RADIUS then
				include = true
			end
		end
		if include then
			Net.fireClient("ShowJiseiPoem", p, { poem = poem, victimName = victim.Name })
		end
	end
end

-- ── Helpers used by remotes ──────────────────────────────────────────
function CombatService._findVictimDownedBy(attacker: Player): Player?
	for userId, s in states do
		if s.isDowned and s.downedBy == attacker then
			return Players:GetPlayerByUserId(userId)
		end
	end
	return nil
end

function CombatService._sanitizeJisei(raw: string): string
	-- Drop control characters except newline (10); clamp to the max length.
	local cleaned = string.gsub(raw, "[%z\1-\9\11-\31\127]", "")
	return string.sub(cleaned, 1, CombatConfig.JISEI_MAX_CHARS)
end

-- ── Character lifecycle ──────────────────────────────────────────────
function CombatService._onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum == nil then
		Logger.warn(SCOPE, "No Humanoid for " .. player.Name) return
	end
	hum.MaxHealth = CombatConfig.MAX_HEALTH
	hum.Health    = CombatConfig.MAX_HEALTH

	states[player.UserId] = {
		health = CombatConfig.MAX_HEALTH,
		stamina = CombatConfig.MAX_STAMINA,
		isBlocking = false, blockStartTime = 0,
		isDodging = false, dodgeEndsAt = 0, lastDodgeAt = 0,
		isDowned = false, downedBy = nil, downedAt = 0, downToken = 0,
		lastDamagedBy = nil, lastDamagedAt = 0,
		isStaggered = false, staggerEndsAt = 0,
		isDead = false,
		lastSwingAt = 0, lastActionAt = 0,
		baseWalkSpeed = hum.WalkSpeed,
		baseJumpPower = hum.JumpPower,
		baseJumpHeight = hum.JumpHeight,
		lastStaminaPush = 0,
	}

	-- Place at faction spawn ONLY when we scheduled this respawn (post-death).
	if pendingRespawn[player.UserId] then
		pendingRespawn[player.UserId] = nil
		task.defer(function()
			factionService.teleportToFactionSpawn(player)
		end)
	end

	-- Non-execute deaths (falls, etc.) still respawn at faction spawn next time.
	hum.Died:Connect(function()
		local s = states[player.UserId]
		if s and not s.isDead then
			s.isDead = true
			pendingRespawn[player.UserId] = true
		end
	end)

	CombatService._pushStamina(player)

	-- Tell the client its current weapon so RequestMeleeHit sends a matching weaponType.
	local equipped   = dataService.get(player, "equipped") :: any
	local weaponName = (equipped and equipped.weapon) or "Unarmed"
	Net.fireClient("CombatLoadout", player, { weapon = weaponName })
end

-- ── Heartbeat: stagger/dodge expiry + stamina regen ──────────────────────────
function CombatService._heartbeat(dt: number)
	local now = os.clock()
	for userId, s in states do
		if s.isStaggered and now >= s.staggerEndsAt then
			s.isStaggered = false
			local player = Players:GetPlayerByUserId(userId)
			if player and not s.isDowned and not s.isDead then
				local hum = getHumanoid(player)
				if hum then hum.WalkSpeed = s.baseWalkSpeed end
			end
		end

		if s.isDodging and now >= s.dodgeEndsAt then
			s.isDodging = false
		end

		if not s.isBlocking and not s.isDowned and not s.isDead
			and s.stamina < CombatConfig.MAX_STAMINA
			and now - s.lastActionAt >= CombatConfig.STAMINA_REGEN_DELAY then
			local regen = CombatConfig.STAMINA_REGEN
			if priestService then
				local vp = Players:GetPlayerByUserId(userId)
				if vp then regen *= (1 + priestService.getBuff(vp, "staminaRegen")) end  -- Vigor omamori
			end
			s.stamina = math.min(CombatConfig.MAX_STAMINA, s.stamina + regen * dt)
			if now - s.lastStaminaPush >= 0.25 then
				local player = Players:GetPlayerByUserId(userId)
				if player then CombatService._pushStamina(player) end
			end
		end
	end
end

-- ── Lifecycle ──────────────────────────────────────────────────────
function CombatService:Init()
	dataService     = Loader.get("DataService")
	duelService     = Loader.get("DuelService")
	factionService  = Loader.get("FactionService")
	moralityService = Loader.get("MoralityService")
	priestService   = Loader.get("PriestService")
end

function CombatService:Start()
	Players.RespawnTime = CombatConfig.RESPAWN_DELAY

	-- Server -> client display events
	Net.registerClientEvent("HitConfirmed")
	Net.registerClientEvent("CombatFeedback")
	Net.registerClientEvent("StaminaUpdate")
	Net.registerClientEvent("ShowDownedPrompt")
	Net.registerClientEvent("EnterDownedState")
	Net.registerClientEvent("ExitDownedState")
	Net.registerClientEvent("ShowJiseiPoem")
	Net.registerClientEvent("CombatLoadout")
	Net.registerClientEvent("CombatFeel")

	-- Client -> server remotes (Net rate-limits + Validates every call)
	Net.registerEvent("RequestMeleeHit", Validate.shape({
		targetId    = Validate.integer,
		weaponType  = Validate.literal(CombatConfig.WeaponNames),
		hitPosition = Validate.vector,
	}))
	Net.onEvent("RequestMeleeHit", function(player: Player, payload: any)
		local p = payload :: { targetId: number, weaponType: string, hitPosition: Vector3 }
		local target = Players:GetPlayerByUserId(p.targetId)
		if target then
			CombatService.resolveHit(player, target, p.weaponType, p.hitPosition)
		end
	end)

	Net.registerEvent("RequestBlock", Validate.shape({ active = Validate.boolean }))
	Net.onEvent("RequestBlock", function(player: Player, payload: any)
		CombatService.setBlocking(player, (payload :: any).active)
	end)

	Net.registerEvent("RequestDodge", Validate.shape({}))
	Net.onEvent("RequestDodge", function(player: Player)
		CombatService.attemptDodge(player)
	end)

	Net.registerEvent("RequestExecuteOrSpare", Validate.shape({
		choice = Validate.literal({ "execute", "spare" }),
	}))
	Net.onEvent("RequestExecuteOrSpare", function(player: Player, payload: any)
		local choice = (payload :: any).choice :: string
		local victim = CombatService._findVictimDownedBy(player)
		if victim then
			CombatService.resolveDownedChoice(player, victim, choice)
		else
			Logger.warn(SCOPE, player.Name .. " sent execute/spare with no downed victim")
		end
	end)

	Net.registerEvent("RequestEquipWeapon", Validate.shape({
		weapon = Validate.literal(CombatConfig.WeaponNames),
	}))
	Net.onEvent("RequestEquipWeapon", function(player: Player, payload: any)
		CombatService.equipWeapon(player, (payload :: any).weapon)
	end)

	Net.registerEvent("RequestSetJisei", Validate.shape({ poem = Validate.string }))
	Net.onEvent("RequestSetJisei", function(player: Player, payload: any)
		local clean = CombatService._sanitizeJisei((payload :: any).poem :: string)
		dataService.set(player, "jiseiPoem", clean)
		Logger.info(SCOPE, player.Name .. " set jisei (" .. tostring(#clean) .. " chars)")
	end)

	-- Character lifecycle wiring
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char: Model)
			CombatService._onCharacter(player, char)
		end)
		if player.Character then
			task.spawn(CombatService._onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do hook(player) end

	Players.PlayerRemoving:Connect(function(player: Player)
		states[player.UserId] = nil
		pendingRespawn[player.UserId] = nil
	end)

	RunService.Heartbeat:Connect(CombatService._heartbeat)
end

return CombatService
