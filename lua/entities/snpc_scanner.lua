--[[-------------------------------------------------------------------------
	City Scanner - Half-Life 2 npc_cscanner (+ npc_basescanner) recreated as a physics SNPC.
	The Weapon Scanner (snpc_wpnscanner) is a variant of this.

	Ported from Valve's npc_basescanner.cpp / npc_scanner.cpp:
	  * Flight: accel 250 (aligned) / 128 (turning), vertical 400, decay 0.15, max speed 250 (500 with an enemy),
	    a little bob, banking, 64 units minimum clearance from the ground.
	  * Patrol: wanders around the map at low speed with a sweeping spotlight.
	  * Enemy: flies to a photo position (96 units away, 32 up), stops, and takes a picture (flash + sound, a
	    player looking at it is blinded). Non-player targets are sometimes inspected with the spotlight instead.
	  * Flash attack: every 8-12 s, within 350 units and facing the enemy: red pre-flash for 1 s, then a white
	    flash that blinds the target (screen fade for players).
	  * Death: if the enemy is well below it (120+ up, 360+ away) it dive-bombs at 2500 u/s toward it
	    (25 damage on hit), otherwise it breaks apart. Either way it explodes (64 / 64) and sometimes drops
	    a battery. Smoke trail below 75% health. After a gravity-gun punt its engine is out for 2 s.

	Not ported: inspecting hint nodes / sounds, squad support requests, the Strider-scout variant, map I/O.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "base_physics_snpc"
ENT.Type      = "ai"
ENT.PrintName = "City Scanner"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

-- body
ENT.Model          = "models/combine_scanner.mdl"
ENT.SpawnHealth    = 30
ENT.HullSize       = 14
ENT.NPCClass       = CLASS_SCANNER
ENT.HackedNPCClass = CLASS_PLAYER_ALLY
ENT.PhysMass       = 0

-- flight (Valve's SCANNER_* / MoveToTarget values)
ENT.MaxSpeed       = 250       -- SCANNER_MAX_SPEED (doubled while it has an enemy)
ENT.CombatSpeedScale = 2
ENT.MaxVertSpeed   = 300
ENT.AccelAligned   = 250
ENT.AccelTurning   = 128
ENT.AccelVertical  = 400
ENT.VelDecay       = 0.15
ENT.NoiseScale     = 3
ENT.BankAngle      = 25
ENT.MinGroundDist  = 64

-- perception
ENT.SightRange     = 2500
ENT.SightFOV       = 300
ENT.ForgetTime     = 15

-- damage / death
ENT.GibDamage      = 0         -- never "crashes" in the manhack sense; see StartDying
ENT.GibOnCrash     = true
ENT.ClientCorpse   = false
ENT.DeathSmoke     = true
ENT.GibModels      = { "models/gibs/scanner_gib01.mdl", "models/gibs/scanner_gib02.mdl",
                       "models/gibs/scanner_gib04.mdl", "models/gibs/scanner_gib05.mdl" }
ENT.GibCount       = 4
ENT.GibSpeedMin    = 250
ENT.GibSpeedMax    = 500
ENT.BatteryChance  = 0.3
ENT.CanDive        = true
ENT.DiveSpeed      = 900
ENT.DiveDamage     = 25        -- sk_scanner_dmg_dive
ENT.ExplosionDamage = 64
ENT.ExplosionRadius = 64

-- scanner behaviour
ENT.SoundPrefix    = "NPC_CScanner"
ENT.IsClaw         = false
ENT.AttackNearDist = 150       -- SCANNER_ATTACK_NEAR_DIST
ENT.AttackFarDist  = 300       -- SCANNER_ATTACK_FAR_DIST
ENT.AttackRange    = 350       -- SCANNER_ATTACK_RANGE
ENT.AttackMinDelay = 8
ENT.AttackMaxDelay = 12
ENT.PhotoNear      = 64
ENT.PhotoFar       = 128
ENT.PhotoDelayMin  = 5
ENT.PhotoDelayMax  = 10
ENT.FlashColor       = Color(255, 255, 255)
ENT.HackedFlashColor = Color(140, 255, 170)
ENT.SpotColor        = Color(255, 255, 255)
ENT.HackedSpotColor  = Color(140, 255, 170)

list.Set("MachineMayhem", "snpc_scanner", {
	Name = "City Scanner", Class = "snpc_scanner",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})

--=========================================================================
-- CLIENT: flash sprite + spotlight beam
--=========================================================================
if CLIENT then
	ENT.RenderGroup = RENDERGROUP_BOTH

	-- own additive materials so the sprites have no black background
	local function AddMat(name, tex)
		local src = Material(tex)
		local t = src and src:GetTexture("$basetexture")
		if t then tex = t:GetName() end
		return CreateMaterial(name, "UnlitGeneric", {
			["$basetexture"] = tex, ["$additive"] = 1, ["$vertexcolor"] = 1,
			["$vertexalpha"] = 1, ["$nocull"] = 1,
		})
	end
	local flare = AddMat("pm_scn_flare_a", "sprites/light_glow02")
	local halo  = AddMat("pm_scn_halo_a", "sprites/light_glow02")
	local beam  = AddMat("pm_scn_beam_c", "sprites/glow_test02")

	-- glow_test02 is a ready-made cone (bright apex at the top, widening downward): draw it on one straight,
	-- camera-facing strip of constant width, top edge at the scanner
	local function DrawCone(from, to, width, col)
		local dir = to - from
		local len = dir:Length()
		if len < 1 then return end
		dir = dir / len
		local right = dir:Cross(EyePos() - (from + to) * 0.5)
		if right:LengthSqr() < 0.0001 then return end
		right:Normalize()
		local h = width * 0.5
		render.SetMaterial(beam)
		mesh.Begin(MATERIAL_QUADS, 1)
		local function V(p, u, v)
			mesh.Position(p) mesh.TexCoord(0, u, v)
			mesh.Color(col.r, col.g, col.b, col.a)
			mesh.AdvanceVertex()
		end
		V(from - right * h, 0, 0)
		V(from + right * h, 1, 0)
		V(to + right * h, 1, 1)
		V(to - right * h, 0, 1)
		mesh.End()
	end

	function ENT:Draw()
		self:DrawModel()
	end

	function ENT:DrawTranslucent()
		self:DrawModel()
		local now = CurTime()
		local id = self:LookupAttachment("light")
		local att = id and id > 0 and self:GetAttachment(id)
		local origin = att and att.Pos or self:WorldSpaceCenter()

		-- camera flash / pre-flash
		if now < self:GetNWFloat("PhysFlashUntil", 0) then
			local c = self:GetNWVector("PhysFlashCol", Vector(255, 255, 255))
			local s = self:GetNWFloat("PhysFlashScale", 1)
			render.SetMaterial(flare)
			render.DrawSprite(origin, 70 * s, 70 * s, Color(c.x, c.y, c.z, 255))
			render.SetMaterial(halo)
			render.DrawSprite(origin, 120 * s, 120 * s, Color(c.x, c.y, c.z, 200))
		end

		-- spotlight
		if self:GetNWBool("PhysSpot", false) then
			local target = self:GetNWVector("PhysSpotEnd", origin)
			self.SpotDraw = self.SpotDraw and LerpVector(math.min(1, FrameTime() * 10), self.SpotDraw, target) or target
			local c = self:GetNWVector("PhysSpotCol", Vector(255, 255, 255))
			local dist = origin:Distance(self.SpotDraw)
			local w = math.Clamp(dist * 0.18, 40, 130)
			DrawCone(origin, self.SpotDraw, w, Color(c.x, c.y, c.z, 200))
			render.SetMaterial(halo)
			-- halo at the start of the beam, like the flash
			render.DrawSprite(origin, 70, 70, Color(c.x, c.y, c.z, 200))

			local d = DynamicLight(self:EntIndex())
			if d then
				d.pos = self.SpotDraw
				d.r, d.g, d.b = c.x, c.y, c.z
				d.brightness = 1.2
				d.size = 160
				d.decay = 400
				d.dietime = now + 0.1
			end
		else
			self.SpotDraw = nil
		end
	end
end

if not SERVER then return end

--=========================================================================
-- SERVER
--=========================================================================

local function BaseFn(name)
	local b = scripted_ents.GetStored("base_physics_snpc")
	return b and b.t and b.t[name]
end

function ENT:Snd(name, level, pitch)
	if self.Silent then return end
	self:EmitSound(self.SoundPrefix .. "." .. name, level or 75, pitch or 100)
end

function ENT:OnSpawned()
	local now = CurTime()
	self.NextAttack    = now + math.Rand(self.AttackMinDelay, self.AttackMaxDelay) * 0.5
	self.NextPhoto     = now + 2
	self.InspectMode   = "photo"       -- or "spot"
	self.InspectUntil  = 0
	self.FlashState    = nil
	self.FlashTime     = 0
	self.PatrolGoal    = nil
	self.NextPatrol    = 0
	self.BobBase       = math.Rand(0, 6)
	self.SpotCur       = nil
	self.SpotOffUntil  = 0
	self.NextSpotNW    = 0
	self.NextIdleSound = now + math.Rand(3, 10)
	self.NextHead      = 0
	self.DynamoAng     = 0
	self.Dead          = false
	self.WantDive      = false
	self.Exploded      = false
	self.AnimSeq       = nil

	self:SetNWBool("PhysSpot", false)
	self:SetNWFloat("PhysFlashUntil", 0)

	-- engine loop
	self.EngSnd = CreateSound(self, self.SoundPrefix .. ".FlyLoop")
	if self.EngSnd then self.EngSnd:PlayEx(0.25, 80) end

	self:PlayIdle()
	self:OnScannerSpawned()
end

function ENT:OnScannerSpawned() end

-- Idle animation (SNPC animation belongs to the engine's activity system, so set it every tick).
function ENT:IdleActivity() return ACT_IDLE end
function ENT:PlayIdle()
	local act = self:IdleActivity()
	self:ResetIdealActivity(act)
	self:SetActivity(act)
	local seq = self:SelectWeightedSequence(act)
	if not seq or seq < 0 then seq = self:LookupSequence("idle") end
	if seq and seq >= 0 then
		self.AnimSeq = seq
		self:ResetSequence(seq)
	end
	self.AnimAct = act
end

function ENT:GetMaxSpeed()
	if self.Diving then return -1 end
	if self.EngineScale then return self.MaxSpeed * self.EngineScale end
	return IsValid(self:GetFoe()) and self.MaxSpeed * self.CombatSpeedScale or self.MaxSpeed
end

function ENT:OnTargetAcquired(ent)
	local now = CurTime()
	self:Snd("Alert")
	-- people get photographed, other things are sometimes inspected with the spotlight
	self.InspectMode = (not ent:IsPlayer() and math.random(0, 3) == 0) and "spot" or "photo"
	self.InspectUntil = now + (self.InspectMode == "spot" and 5 or 9999)
	self.NextPhoto = now + 1
end

--=========================================================================
-- Movement
--=========================================================================

-- Goal point near `goalPos`: `idealHeight` above it, `idealRange` back toward `startPos`, kept off the ground.
function ENT:IdealGoal(goalPos, startPos, idealRange, idealHeight)
	local dir = goalPos - startPos
	dir.z = 0
	if dir:LengthSqr() < 1 then dir = self:GetForward() dir.z = 0 end
	dir:Normalize()
	local ideal = goalPos + Vector(0, 0, idealHeight) - dir * idealRange

	local h = Vector(8, 8, 8)
	local min = self:GetMinGroundDist()
	local tr = util.TraceHull({
		start = ideal, endpos = ideal - Vector(0, 0, min), mins = -h, maxs = h,
		mask = MASK_NPCSOLID_BRUSHONLY, filter = self,
	})
	if tr.Hit then ideal.z = ideal.z + min * (1 - tr.Fraction) end
	return ideal
end

function ENT:GetMinGroundDist() return self.MinGroundDist end

function ENT:UpdateMovement(dt)
	local now = CurTime()
	if self.Held then return end
	local foe = self:GetFoe()
	self.TurnRate = IsValid(foe) and 800 or 350

	if IsValid(foe) then
		self:CombatMove(dt, foe)
	else
		self:PatrolMove(dt)
	end

	-- a little vertical/horizontal bob (Valve: +/-10% in speed) is done by the base's noise
end

-- Head, tail and dynamo pose parameters (cosmetic).
function ENT:UpdatePoses(dt)
	local now = CurTime()
	if now < self.NextHead then return end
	self.NextHead = now + 0.05
	local vel = self.CurVel
	local max = math.max(self:GetMaxSpeed(), 1)
	self.DynamoAng = (self.DynamoAng - (vel:Length() / max) * 60 * 0.05 * 10) % 360
	self:SetPoseParameter("dynamo_wheel", self.DynamoAng)
	self:SetPoseParameter("tail_control", math.Remap(math.Clamp(vel.z, -150, 250), -150, 250, -25, 80))

	local watch = self:GetFoe()
	if IsValid(watch) then
		local eye = self:GetPos() + Vector(0, 0, 10)
		local ang = self:WorldToLocalAngles((watch:EyePos() - eye):Angle())
		local cur = self:GetPoseParameter("head_horizontal") or 0
		local curV = self:GetPoseParameter("head_vertical") or 0
		self:SetPoseParameter("head_horizontal", math.Approach(cur, math.Clamp(math.NormalizeAngle(ang.y), -45, 45), 50 * 0.05 * 5))
		self:SetPoseParameter("head_vertical", math.Approach(curV, math.Clamp(-math.NormalizeAngle(ang.p), -45, 45), 50 * 0.05 * 5))
	else
		self:SetPoseParameter("head_horizontal", math.Approach(self:GetPoseParameter("head_horizontal") or 0, 0, 10 * 0.05 * 5))
		self:SetPoseParameter("head_vertical", math.Approach(self:GetPoseParameter("head_vertical") or 0, 0, 10 * 0.05 * 5))
	end
end

-- Wander around slowly (SCHED_SCANNER_PATROL).
function ENT:PatrolMove(dt)
	local now = CurTime()
	local pos = self:GetPos()
	if not self.PatrolGoal or now >= self.NextPatrol or pos:DistToSqr(self.PatrolGoal) < 48 * 48 then
		self.PatrolGoal = self:PickPatrolGoal()
		self.NextPatrol = now + 8
	end
	if not self.PatrolGoal then self:Decelerate(dt, 3) return end
	self:MoveToTarget(dt, self:SteerAround(self.PatrolGoal))
end

function ENT:PickPatrolGoal()
	local pos = self:GetPos()
	for _ = 1, 8 do
		local dir = Angle(0, math.Rand(0, 360), 0):Forward()
		local dist = math.Rand(300, 1800)
		local tr = util.TraceLine({ start = pos, endpos = pos + dir * dist, mask = MASK_NPCSOLID_BRUSHONLY, filter = self })
		if tr.Fraction > 0.35 then
			local p = tr.HitPos - dir * 80
			local fl = util.TraceLine({ start = p + Vector(0, 0, 40), endpos = p - Vector(0, 0, 700), mask = MASK_NPCSOLID_BRUSHONLY, filter = self })
			if fl.Hit then return fl.HitPos + Vector(0, 0, math.Rand(100, 230)) end
		end
	end
	return pos + Vector(0, 0, math.Rand(-20, 40))
end

-- Enemy in view: photograph it, blind it, hover above it for the spotlight.
function ENT:CombatMove(dt, foe)
	local now = CurTime()
	local pos = self:GetPos()
	local target = self.FoeVisible and foe:WorldSpaceCenter() or (self:GetChasePos() or foe:WorldSpaceCenter())
	local to2D = Vector(target.x - pos.x, target.y - pos.y, 0)
	local d2 = to2D:Length()

	-- hovering still during the flash sequence
	if self.FlashState then
		self:Decelerate(dt, 4)
		return
	end

	-- time for a flash attack?
	if self:WantsFlashAttack(d2) then
		local goal = self:IdealGoal(target, pos, self:GetGoalDistance(), 128)
		self:MoveToTarget(dt, self:SteerAround(goal, foe))
		local fwd = self:GetForward()
		fwd.z = 0
		fwd:Normalize()
		local facing = d2 > 1 and fwd:Dot(to2D / d2) or 1
		if d2 < self.AttackRange and facing > 0.7 and self.FoeVisible then self:StartFlashAttack(foe) end
		return
	end

	if self.InspectMode == "spot" and now < self.InspectUntil then
		-- hover above it with the spotlight on it
		local goal = self:IdealGoal(target, pos, 60, 130)
		self:MoveToTarget(dt, self:SteerAround(goal, foe))
		return
	end

	-- photograph position: 96 units away, 32 up (midpoint of the 64..128 photo range)
	local standoff = (self.PhotoNear + self.PhotoFar) * 0.5
	local goal = self:IdealGoal(target, pos, standoff, 32)
	self:MoveToTarget(dt, self:SteerAround(goal, foe))

	if self.FoeVisible and now >= self.NextPhoto and d2 > self.PhotoNear and d2 < self.PhotoFar
		and self:GetVelocity():LengthSqr() < 64 * 64 then
		local fwd = self:GetForward()
		fwd.y = fwd.y
		local yawErr = math.abs(math.NormalizeAngle(self:GetAngles().y - to2D:Angle().y))
		if yawErr < 4 then self:TakePhoto(foe) end
	end
end

function ENT:GetGoalDistance()
	return self.AttackNearDist + (self.AttackFarDist - self.AttackNearDist) * 0.5
end

function ENT:WantsFlashAttack(d2)
	return CurTime() >= self.NextAttack and d2 < self.AttackRange * 2
end

--=========================================================================
-- Photo + flash attack
--=========================================================================

function ENT:SetFlash(scale, col, dur)
	self:SetNWFloat("PhysFlashUntil", CurTime() + dur)
	self:SetNWFloat("PhysFlashScale", scale)
	self:SetNWVector("PhysFlashCol", Vector(col.r, col.g, col.b))
end

function ENT:FlashColorNow()
	return self.Hacked and self.HackedFlashColor or self.FlashColor
end

function ENT:TakePhoto(foe)
	local now = CurTime()
	self.NextPhoto = now + math.Rand(self.PhotoDelayMin, self.PhotoDelayMax)
	self:Snd("TakePhoto")
	self:SetFlash(1.4, self:FlashColorNow(), 0.12)
	self.SpotOffUntil = now + 0.5
	self:BlindFlashTarget(foe)
end

function ENT:BlindFlashTarget(target, strength)
	if not IsValid(target) or not target:IsPlayer() then return end
	-- only a player looking at us is blinded
	local toMe = (self:WorldSpaceCenter() - target:EyePos()):GetNormalized()
	local dot = target:GetAimVector():Dot(toMe)
	if dot <= 0.5 then return end
	local c = self:FlashColorNow()
	target:ScreenFade(SCREENFADE.IN, Color(c.r, c.g, c.b, math.Clamp(240 * dot * (strength or 1), 0, 240)), 3, 0.5)
end

function ENT:StartFlashAttack(foe)
	local now = CurTime()
	self.FlashState = "pre"
	self.FlashTime = now + 1
	self.FlashFoe = foe
	self.SpotOffUntil = now + 1.5
	self:SetFlash(0.5, Color(255, 0, 0), 1)
	self:Snd("AttackFlash", 80, 90)
end

function ENT:UpdateFlash()
	if not self.FlashState then return end
	local now = CurTime()
	local foe = self.FlashFoe
	if not IsValid(foe) or self.Crashing then
		self.FlashState = nil
		return
	end
	if self.FlashState == "pre" and now >= self.FlashTime then
		self.FlashState = "flash"
		self.FlashTime = now + 0.3
		local c = self:FlashColorNow()
		self:SetFlash(1.8, c, 0.25)
		self:Snd("AttackFlash")
		local ed = EffectData()
		ed:SetOrigin(self:GetPos())
		-- (dynamic light is drawn by the client sprite; also light up the room briefly)
		local lamp = ents.Create("light_dynamic")
		if IsValid(lamp) then
			lamp:SetKeyValue("_light", ("%d %d %d 200"):format(c.r, c.g, c.b))
			lamp:SetKeyValue("distance", "300")
			lamp:SetKeyValue("brightness", "4")
			lamp:SetPos(self:GetPos())
			lamp:Spawn()
			lamp:Fire("TurnOn")
			SafeRemoveEntityDelayed(lamp, 0.2)
		end
		self:BlindFlashTarget(foe, 1)
		self:OnFlashed(foe)
	elseif self.FlashState == "flash" and now >= self.FlashTime then
		self.FlashState = nil
		self.NextAttack = now + math.Rand(self.AttackMinDelay, self.AttackMaxDelay)
		self.SpotOffUntil = now + 1
	end
end

function ENT:OnFlashed(foe) end -- hook for variants

--=========================================================================
-- Spotlight (drawn on the client; the server decides where it points)
--=========================================================================

function ENT:SpotlightWanted()
	if self.Crashing or self.Held then return false end
	if CurTime() < self.SpotOffUntil then return false end
	if self.FlashState then return false end
	local foe = self:GetFoe()
	if IsValid(foe) then return self.InspectMode == "spot" and CurTime() < self.InspectUntil end
	return true -- patrol
end

function ENT:UpdateSpotlight(dt)
	local now = CurTime()
	local on = self:SpotlightWanted()
	if not on then
		if self:GetNWBool("PhysSpot", false) then self:SetNWBool("PhysSpot", false) end
		self.SpotCur = nil
		return
	end

	local origin = self:GetPos() + Vector(0, 0, 8)
	local aim
	local foe = self:GetFoe()
	if IsValid(foe) then
		local p = foe:GetPos()
		local eyes = foe:EyePos()
		aim = LerpVector(0.75, p, eyes)
	else
		-- sweep ahead and down
		local t = now * 0.9 + self.BobBase
		local dir = self:GetForward() * 1 + Vector(0, 0, -0.9) + self:GetRight() * math.sin(t) * 0.8 * 2.5 * 0.4
		dir:Normalize()
		local tr = util.TraceLine({ start = origin, endpos = origin + dir * 2024, mask = MASK_SOLID_BRUSHONLY, filter = self })
		aim = tr.HitPos
	end
	self.SpotCur = self.SpotCur and LerpVector(math.min(1, dt * 5), self.SpotCur, aim) or aim

	if now >= self.NextSpotNW then
		self.NextSpotNW = now + 0.1
		local c = self.Hacked and self.HackedSpotColor or self.SpotColor
		self:SetNWBool("PhysSpot", true)
		self:SetNWVector("PhysSpotEnd", self.SpotCur)
		self:SetNWVector("PhysSpotCol", Vector(c.r, c.g, c.b))
	end
end

--=========================================================================
-- Per tick
--=========================================================================

function ENT:OnThinkAlive(dt)
	local now = CurTime()
	-- keep the idle animation alive
	if self.AnimSeq and self:GetSequence() ~= self.AnimSeq then self:ResetSequence(self.AnimSeq) end

	self:UpdatePoses(dt)
	self:UpdateFlash()
	self:UpdateSpotlight(dt)
	self:OnScannerThink(dt)

	-- engine loop follows speed
	if self.EngSnd and now >= (self.NextEngSnd or 0) then
		self.NextEngSnd = now + 0.1
		local f = math.Clamp(self.CurVel:Length() / math.max(self.MaxSpeed, 1), 0, 1)
		self.EngSnd:ChangePitch(math.min(255, 80 + 20 * f), 0.1)
		self.EngSnd:ChangeVolume(0.25 + 0.75 * f, 0.1)
	end

	-- idle chatter
	if not self.Silent and now >= self.NextIdleSound then
		self.NextIdleSound = now + math.Rand(3, 8)
		if math.random(0, 3) == 0 then self:Snd(IsValid(self:GetFoe()) and "Combat" or "Idle") end
	end
end

function ENT:OnScannerThink(dt) end -- hook for variants

function ENT:OnDamaged(dmg)
	if self:Health() < self:GetMaxHealth() * 0.75 then self:CreateSmokeTrail() end
	self:Snd("Pain")
	self.SpotOffUntil = CurTime() + 2 -- "spotlight is destroyed on damage, and recreated after 2 s"
end

-- Idle / combat chatter can be looping sirens: a sound started with EmitSound keeps looping after its entity is
-- gone unless it is stopped explicitly, so stop them (and the raw files behind them) whenever the scanner dies.
ENT.ChatterNames = { "Idle", "Combat", "Alert", "Pain", "TakePhoto", "AttackFlash", "DiveBomb", "Shoot", "Die" }
ENT.ChatterFiles = {
	"npc/scanner/scanner_siren1.wav", "npc/scanner/scanner_siren2.wav", "npc/scanner/scanner_alert1.wav",
	"npc/scanner/combat_scan_loop1.wav", "npc/scanner/combat_scan_loop2.wav", "npc/scanner/combat_scan_loop4.wav",
	"npc/scanner/combat_scan_loop5.wav", "npc/scanner/combat_scan_loop6.wav", "npc/scanner/combat_scan1.wav",
	"npc/scanner/combat_scan2.wav", "npc/scanner/combat_scan3.wav", "npc/scanner/combat_scan4.wav",
	"npc/scanner/combat_scan5.wav", "npc/scanner/scanner_scan_loop1.wav", "npc/scanner/scanner_scan_loop2.wav",
}
function ENT:StopChatter(all)
	for _, n in ipairs(self.ChatterNames) do
		if all or (n ~= "Die" and n ~= "DiveBomb" and n ~= "Pain") then self:StopSound(self.SoundPrefix .. "." .. n) end
	end
	for _, f in ipairs(self.ChatterFiles) do self:StopSound(f) end
end
function ENT:StopLoops()
	if self.EngSnd then self.EngSnd:Stop() end
	self:StopChatter(false)
end

function ENT:OnRemoved()
	self:StopLoops()
	self:StopChatter(true)
	self:DestroySmokeTrail()
	self:OnScannerRemoved()
end
function ENT:OnScannerRemoved() end

--=========================================================================
-- Death: dive bomb or break apart, then explode
--=========================================================================

function ENT:ShouldGib(dmg) return not self.WantDive end

function ENT:StartDying(dmg)
	if self.Crashing then return end
	local foe = self:GetFoe()
	local lkp = self.EnemyLKP or (IsValid(foe) and foe:WorldSpaceCenter())
	self.WantDive = false

	if self.CanDive and lkp and IsValid(foe) and not dmg:IsDamageType(DMG_DISSOLVE) then
		local delta = self:GetPos() - foe:GetPos()
		if delta.z > 120 and delta:Length() > 360 then
			self.WantDive = true
			local dir = (lkp - self:GetPos()):GetNormalized()
			self.DiveDir = dir
			self.DiveRoll = math.Rand(20, 420) * (math.random(0, 1) == 0 and -1 or 1)
			self.DiveBounces = 0
		end
	end
	self:Snd("Die")
	self:StopLoops()
	self:SetNWBool("PhysSpot", false)
	BaseFn("StartDying")(self, dmg)
	if self.WantDive and self.Crashing then
		self.Diving = true
		self.DiveStart = CurTime()
		self:Snd("DiveBomb", 85)
	end
end

function ENT:CrashThink(dt)
	if not self.Diving then return BaseFn("CrashThink")(self, dt) end
	if self.Gibbed then return end
	local phys = self:GetPhysicsObject()
	if not IsValid(phys) or CurTime() - self.DiveStart > 6 then self:Gib() return end
	phys:Wake()
	phys:EnableGravity(false)
	local pos = self:GetPos()
	local vel = self.DiveDir * self.DiveSpeed
	local h = self.HullMaxs * 0.8
	local tr = util.TraceHull({
		start = pos, endpos = pos + vel * dt + self.DiveDir * 12,
		mins = -h, maxs = h, filter = self, mask = MASK_SOLID,
	})
	if tr.Hit then
		local ent = tr.Entity
		if IsValid(ent) and not ent:IsWorld() and not ent.IsPhysicsSNPC and ent:GetClass() ~= "item_battery" then
			local d = DamageInfo()
			d:SetAttacker(self) d:SetInflictor(self)
			d:SetDamage(self.DiveDamage)
			d:SetDamageType(DMG_CLUB)
			d:SetDamagePosition(tr.HitPos)
			d:SetDamageForce(self.DiveDir * 3000)
			ent:TakeDamageInfo(d)
			self:Gib()
			return
		end
		-- bounce off the world
		self.DiveBounces = self.DiveBounces + 1
		if self.DiveBounces >= 3 then self:Gib() return end
		self.DiveDir = (self.DiveDir - 2 * self.DiveDir:Dot(tr.HitNormal) * tr.HitNormal):GetNormalized()
		local ed = EffectData()
		ed:SetOrigin(tr.HitPos) ed:SetNormal(tr.HitNormal) ed:SetMagnitude(2) ed:SetScale(1) ed:SetRadius(2)
		util.Effect("ElectricSpark", ed)
		self:Snd("Shoot")
		vel = self.DiveDir * self.DiveSpeed
	end
	phys:SetVelocity(vel)
	phys:AddAngleVelocity(phys:WorldToLocalVector(self:GetForward() * self.DiveRoll * dt * 10))
	self.CurVel = vel
	self:CrashEffects(dt)
end

-- the explosion and the drops, whichever way it breaks apart
function ENT:OnGibbed()
	if self.Exploded then return end
	self.Exploded = true
	self:StopLoops()
	local pos = self:WorldSpaceCenter()

	for _ = 1, 4 do
		local ed = EffectData()
		ed:SetOrigin(pos + VectorRand() * 12)
		ed:SetMagnitude(2) ed:SetScale(1) ed:SetRadius(2)
		util.Effect("ElectricSpark", ed)
	end
	local ed = EffectData()
	ed:SetOrigin(pos) ed:SetScale(1) ed:SetMagnitude(1)
	util.Effect("Explosion", ed)
	util.BlastDamage(self, self, pos, self.ExplosionRadius, self.ExplosionDamage)

	if math.Rand(0, 1) < self.BatteryChance then
		local b = ents.Create("item_battery")
		if IsValid(b) then
			b:SetPos(pos)
			b:Spawn()
		end
	end
	self:OnScannerDeath()
end
function ENT:OnScannerDeath() end
