--!strict
-- ModuleScript: StarterPlayer.StarterPlayerScripts.Main.Controllers.FeelController
-- Layer 4 — Game Feel & Impact. Listens for the server's "CombatFeel" cue and turns
-- it into LOCAL juice: hitstop, camera shake + punch, execution slow-mo, stylized
-- blood, hit markers, sound. Purely cosmetic — never touches the server sim, never
-- blocks input beyond a tiny hitstop. All effects are guarded + self-cleaning.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local Lighting          = game:GetService("Lighting")
local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net        = require(ReplicatedStorage.Framework.Net)
local Logger     = require(ReplicatedStorage.Framework.Logger)
local FeelConfig = require(ReplicatedStorage.Config.FeelConfig)

local SCOPE  = "FeelController"
local player = Players.LocalPlayer

local FeelController = {}

-- master hooks (accessibility / "reduce effects")
local intensity    = 1.0
local bloodEnabled = true

-- ── anim time control (hitstop + slow-mo) ───────────────────────────────
local frozen       = false
local slowScale    = 1.0
local modifying    = false
local hitstopToken = 0
local slowToken    = 0

local function getTracks(): { AnimationTrack }
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator == nil then return {} end
	return (animator :: Animator):GetPlayingAnimationTracks()
end

local function applyHitstop(duration: number)
	if intensity <= 0 then return end
	local d = duration * intensity
	if d <= 0 then return end
	hitstopToken += 1
	local my = hitstopToken
	frozen = true
	task.delay(d, function()
		if my == hitstopToken then frozen = false end
	end)
end

local function doSlowmo()
	if intensity <= 0 then return end
	Logger.try(SCOPE, function()
		local cfg = FeelConfig.executionSlowmo
		slowToken += 1
		local my = slowToken
		local cam = workspace.CurrentCamera
		local baseFov = cam and cam.FieldOfView or 70
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "FeelExecCC"
		cc.Parent = Lighting
		if cam then
			TweenService:Create(cam, TweenInfo.new(cfg.easeIn), { FieldOfView = baseFov - cfg.fovKick }):Play()
		end
		TweenService:Create(cc, TweenInfo.new(cfg.easeIn), { Saturation = -cfg.desat }):Play()
		task.spawn(function()
			local t0 = os.clock()
			while my == slowToken do
				local e = os.clock() - t0
				if e >= cfg.easeIn then break end
				slowScale = 1 + (cfg.timeScale - 1) * (e / cfg.easeIn)
				RunService.Heartbeat:Wait()
			end
			if my ~= slowToken then return end
			slowScale = cfg.timeScale
			task.wait(cfg.duration)
			if my ~= slowToken then return end
			if cam then
				TweenService:Create(cam, TweenInfo.new(cfg.easeOut), { FieldOfView = baseFov }):Play()
			end
			TweenService:Create(cc, TweenInfo.new(cfg.easeOut), { Saturation = 0 }):Play()
			local t1 = os.clock()
			while my == slowToken do
				local e = os.clock() - t1
				if e >= cfg.easeOut then break end
				slowScale = cfg.timeScale + (1 - cfg.timeScale) * (e / cfg.easeOut)
				RunService.Heartbeat:Wait()
			end
			if my == slowToken then slowScale = 1 end
			task.delay(0.2, function() if cc.Parent then cc:Destroy() end end)
		end)
	end)
end

-- apply current freeze/slow to local anim tracks each frame
RunService.Heartbeat:Connect(function()
	Logger.try(SCOPE, function()
		local spd = frozen and 0 or slowScale
		if spd ~= 1 then
			for _, tr in getTracks() do tr:AdjustSpeed(spd) end
			modifying = true
		elseif modifying then
			for _, tr in getTracks() do tr:AdjustSpeed(1) end
			modifying = false
		end
	end)
end)

-- ── camera shake + punch (spring, applied after the camera each render) ─────────
type Shake = { mag: number, roughness: number, fadeIn: number, fadeOut: number, age: number, seed: number }
local shakes: { Shake } = {}

local punchPos    = Vector3.zero
local punchPosVel = Vector3.zero
local punchRot    = Vector3.zero
local punchRotVel = Vector3.zero
local SPRING_STIFF = 170
local SPRING_DAMP  = 22

local function springV(v: Vector3, vel: Vector3, dt: number): (Vector3, Vector3)
	local force = v * (-SPRING_STIFF) - vel * SPRING_DAMP
	vel = vel + force * dt
	v = v + vel * dt
	return v, vel
end

local function shake(preset: any, scale: number)
	if preset == nil then return end
	local mag = preset.magnitude * scale * intensity
	if mag <= 0 then return end
	table.insert(shakes, {
		mag = mag, roughness = preset.roughness,
		fadeIn = preset.fadeIn, fadeOut = preset.fadeOut,
		age = 0, seed = math.random() * 1000,
	})
end

local function punch(preset: any, _dir: Vector3, scale: number)
	if preset == nil or intensity <= 0 then return end
	local s = scale * intensity
	punchPosVel += Vector3.new(0, 0, preset.pos * s * 6)      -- kick backward (recoil)
	punchRotVel += Vector3.new(-preset.pitch * s * 8, 0, 0)   -- nose up, springs back
end

RunService:BindToRenderStep("FeelCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	Logger.try(SCOPE, function()
		local cam = workspace.CurrentCamera
		if cam == nil then return end
		local sPos, sRot = Vector3.zero, Vector3.zero
		local i = 1
		while i <= #shakes do
			local sh = shakes[i]
			sh.age += dt
			local amp
			if sh.fadeIn > 0 and sh.age < sh.fadeIn then
				amp = sh.age / sh.fadeIn
			else
				local t = sh.age - sh.fadeIn
				if t >= sh.fadeOut then
					table.remove(shakes, i)
					continue
				end
				amp = 1 - t / sh.fadeOut
			end
			local f = sh.age * sh.roughness
			local nx = math.noise(sh.seed, f)
			local ny = math.noise(sh.seed + 5.2, f)
			local nz = math.noise(sh.seed + 9.7, f)
			sRot += Vector3.new(nx, ny, nz) * sh.mag * amp * 0.05
			sPos += Vector3.new(nx, ny, 0) * sh.mag * amp * 0.12
			i += 1
		end
		punchPos, punchPosVel = springV(punchPos, punchPosVel, dt)
		punchRot, punchRotVel = springV(punchRot, punchRotVel, dt)
		local pos = sPos + punchPos
		local rot = sRot + punchRot
		cam.CFrame = cam.CFrame * CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z)
	end)
end)

-- ── blood VFX (stylized, brief — not realistic gore) ────────────────────────
local function bloodSpray(pos: Vector3, dir: Vector3, count: number)
	if not bloodEnabled or intensity <= 0 then return end
	count = math.floor(count * intensity)
	if count <= 0 then return end
	Logger.try(SCOPE, function()
		local part = Instance.new("Part")
		part.Anchored = true; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
		part.Transparency = 1; part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.CFrame = CFrame.lookAt(pos, pos + dir)
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(FeelConfig.blood.color)
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.LightEmission = 0.2
		e.Lifetime = NumberRange.new(FeelConfig.blood.lifetime * 0.6, FeelConfig.blood.lifetime)
		e.Speed = NumberRange.new(FeelConfig.blood.speed * 0.5, FeelConfig.blood.speed)
		e.SpreadAngle = Vector2.new(28, 28)
		e.Rate = 0
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Acceleration = Vector3.new(0, -45, 0)
		e.EmissionDirection = Enum.NormalId.Front
		e.Parent = part
		part.Parent = workspace
		e:Emit(count)
		Debris:AddItem(part, 2)
	end)
end

local function bloodPool(pos: Vector3)
	if not bloodEnabled or intensity <= 0 then return end
	Logger.try(SCOPE, function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local char = player.Character
		params.FilterDescendantsInstances = char and { char } or {}
		local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), params)
		local y = hit and hit.Position.Y or pos.Y
		local part = Instance.new("Part")
		part.Anchored = true; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
		part.Size = Vector3.new(5.5, 0.06, 5.5)
		part.CFrame = CFrame.new(pos.X, y + 0.04, pos.Z)
		part.Color = FeelConfig.blood.color
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 1
		local corner = Instance.new("SpecialMesh")
		corner.MeshType = Enum.MeshType.Cylinder
		corner.Scale = Vector3.new(0.12, 1, 1)
		part.Parent = workspace
		TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 0.2 }):Play()
		task.delay(FeelConfig.blood.poolLifetime - 1, function()
			if part.Parent then TweenService:Create(part, TweenInfo.new(1), { Transparency = 1 }):Play() end
		end)
		Debris:AddItem(part, FeelConfig.blood.poolLifetime + 1)
	end)
end

-- ── hit marker (attacker-only) ─────────────────────────────────────────
local markerGui: ScreenGui?
local markerBars: { Frame } = {}
local function buildMarker()
	if markerGui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "FeelMarker"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 8
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromOffset(48, 48); holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.AnchorPoint = Vector2.new(0.5, 0.5); holder.BackgroundTransparency = 1; holder.Parent = g
	markerBars = {}
	for _, rot in { 45, -45 } do
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5); b.Position = UDim2.fromScale(0.5, 0.5)
		b.Size = UDim2.fromOffset(18, 3); b.Rotation = rot; b.BorderSizePixel = 0
		b.BackgroundTransparency = 1; b.Parent = holder
		table.insert(markerBars, b)
	end
	g.Parent = player:WaitForChild("PlayerGui"); markerGui = g
end
local function showMarker(styleName: string)
	buildMarker()
	local st = FeelConfig.hitMarker[styleName] or FeelConfig.hitMarker.normal
	for _, b in markerBars do
		b.BackgroundColor3 = st.color
		b.Size = UDim2.fromOffset(st.size, 3)
		b.BackgroundTransparency = 0
		TweenService:Create(b, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	end
end

-- ── sound ─────────────────────────────────────────────────────────
local function playSound(id: string, pos: Vector3, is3d: boolean)
	if id == nil or id == "" then return end
	Logger.try(SCOPE, function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = 1
		if is3d then
			local p = Instance.new("Part")
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
			p.Transparency = 1; p.Size = Vector3.new(0.2, 0.2, 0.2); p.CFrame = CFrame.new(pos)
			s.RollOffMaxDistance = 80; s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.Parent = p; p.Parent = workspace; s:Play()
			Debris:AddItem(p, 4)
		else
			s.Parent = SoundService; s:Play(); Debris:AddItem(s, 4)
		end
	end)
end

-- ── helpers ─────────────────────────────────────────────────────
local function userHRPpos(userId: number): Vector3?
	local pl = Players:GetPlayerByUserId(userId)
	local ch = pl and pl.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	return hrp and (hrp :: BasePart).Position or nil
end

local function witnessScale(pos: Vector3): number
	local cam = workspace.CurrentCamera
	local origin = cam and cam.CFrame.Position
	if origin == nil then return 0.4 end
	local d = (origin - pos).Magnitude
	return math.clamp(1 - d / FeelConfig.WITNESS_RADIUS, 0, 1) * 0.6
end

-- ── dispatch ────────────────────────────────────────────────────
local function onFeel(raw: any)
	Logger.try(SCOPE, function()
		local p = raw :: { kind: string, attackerId: number, targetId: number?, position: Vector3, severity: string, isParticipant: boolean }
		local kind = p.kind
		local isP  = p.isParticipant == true
		local pos  = p.position or Vector3.zero
		local sev  = p.severity or "light"
		local isAttacker = p.attackerId == player.UserId
		local scale = isP and 1 or witnessScale(pos)
		if scale <= 0 then return end

		local aPos = userHRPpos(p.attackerId)
		local dir = Vector3.yAxis
		if aPos then
			local v = pos - aPos
			if v.Magnitude > 0.05 then dir = v.Unit end
		end

		if kind == "hit" or kind == "block" then
			local heavy = sev == "heavy"
			local presetName = (kind == "block") and "block" or (heavy and "heavyHit" or "lightHit")
			if isP then applyHitstop(heavy and FeelConfig.hitstop.heavyHit or FeelConfig.hitstop.lightHit) end
			shake(FeelConfig.shake[presetName], scale)
			punch(FeelConfig.punch[presetName], dir, scale)
			local bsev = (kind == "block") and "chip" or (heavy and "heavy" or "light")
			bloodSpray(pos, dir, FeelConfig.blood.spray[bsev])
			if isAttacker then
				showMarker(heavy and "heavy" or "normal")
				playSound(FeelConfig.sounds[heavy and "heavy" or "hit"], pos, false)
			else
				playSound(FeelConfig.sounds.hit, pos, true)
			end
		elseif kind == "parry" then
			if isP then applyHitstop(FeelConfig.hitstop.parry) end
			shake(FeelConfig.shake.parry, scale)
			punch(FeelConfig.punch.parry, dir, scale)
			if isAttacker then showMarker("parry") end
			playSound(FeelConfig.sounds.parry, pos, not isP)
		elseif kind == "down" then
			shake(FeelConfig.shake.heavyHit, scale * 0.8)
			punch(FeelConfig.punch.heavyHit, dir, scale * 0.8)
			bloodSpray(pos, dir, FeelConfig.blood.spray.heavy)
			playSound(FeelConfig.sounds.heavy, pos, not isP)
		elseif kind == "kill" then
			if isP then applyHitstop(FeelConfig.hitstop.kill) end
			shake(FeelConfig.shake.kill, scale)
			punch(FeelConfig.punch.kill, dir, scale)
			bloodSpray(pos, dir, FeelConfig.blood.spray.kill)
			if FeelConfig.blood.poolOnKill then bloodPool(pos) end
			if isAttacker then showMarker("kill") end
			playSound(FeelConfig.sounds.kill, pos, not isP)
		elseif kind == "execute" then
			shake(FeelConfig.shake.execute, scale)
			punch(FeelConfig.punch.execute, dir, scale)
			bloodSpray(pos, dir, FeelConfig.blood.spray.execute)
			if FeelConfig.blood.poolOnKill then bloodPool(pos) end
			playSound(FeelConfig.sounds.execute, pos, not isP)
			if isAttacker then showMarker("kill") end
			if isP then doSlowmo() end
		elseif kind == "spare" then
			shake(FeelConfig.shake.block, scale * 0.5)
			playSound(FeelConfig.sounds.block, pos, not isP)
		end
	end)
end

-- ── public API ──────────────────────────────────────────────────
-- Master intensity for accessibility / "reduce effects" (0 = off, 1 = full).
function FeelController.setIntensity(v: number)
	intensity = math.clamp(v, 0, 1)
	Logger.info(SCOPE, "intensity set to " .. tostring(intensity))
end

function FeelController.setBloodEnabled(on: boolean)
	bloodEnabled = on and true or false
	Logger.info(SCOPE, "blood " .. (bloodEnabled and "on" or "off"))
end

-- Step 4 marker convention: real swing anims carry a KeyframeMarker named "Impact".
-- Call this with the swing track + a callback to TIME local feedback to the actual
-- frame; if the anim has no "Impact" marker, fall back to a fixed delay.
function FeelController.bindImpactMarker(track: AnimationTrack, onImpact: () -> ())
	Logger.try(SCOPE, function()
		local fired = false
		local function fire() if not fired then fired = true; onImpact() end end
		local conn = track:GetMarkerReachedSignal("Impact"):Connect(fire)
		task.delay(FeelConfig.swingFallbackDelay, fire)  -- placeholder-anim fallback
		track.Stopped:Once(function() if conn then conn:Disconnect() end end)
	end)
end

function FeelController:Init()
	Net.onClientEvent("CombatFeel", onFeel)
end

function FeelController:Start()
	buildMarker()

	-- Accessibility/debug: mirror player attributes into the master hooks so settings
	-- (or the verification harness) can adjust effects live without a remote.
	local function readAttrs()
		local i = player:GetAttribute("FeelIntensity")
		if typeof(i) == "number" then FeelController.setIntensity(i) end
		local b = player:GetAttribute("FeelBlood")
		if typeof(b) == "boolean" then FeelController.setBloodEnabled(b) end
	end
	player:GetAttributeChangedSignal("FeelIntensity"):Connect(readAttrs)
	player:GetAttributeChangedSignal("FeelBlood"):Connect(readAttrs)
	readAttrs()

	Logger.info(SCOPE, "online")
end

return FeelController
