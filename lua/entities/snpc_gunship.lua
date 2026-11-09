--[[-------------------------------------------------------------------------
	Gunship - a physics-driven recreation of the Combine gunship (boss).
	  * full size; its own flight: heavy and floaty like the real one (momentum, tilts / banks into its acceleration, no air nodes),
	    circles the target at range; head (flex_horz / flex_vert) and fins (fin_accel / fin_sway) move through pose parameters
	  * main cannon: a 0.5 s wind-up, then a burst of 15 AR2 rounds from the "muzzle" attachment (not at targets < 350 away)
	  * belly cannon: when the target is close underneath it hovers above it, charges for 3 s (blue flare + glow at the
	    "BellyGun" attachment) and blasts a 256 unit radius (150 damage, shoves physics props away)
	  * shoots down rpg missiles that head for it
	  * bullets do nothing to it, explosions hurt: ~4 of them from full health; nothing can pick it up
	  * when destroyed it burns and explodes a few times while falling, then breaks apart on the ground
	Never replaces a map gunship unless "physsnpc_replace_gunship" is on.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_scanner"
ENT.PrintName = "Gunship"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.IsBoss       = true
ENT.SwarmEnabled = false
ENT.Model        = "models/gunship.mdl"
ENT.ModelScale   = 1
ENT.SpawnHealth  = 1500
ENT.PhysMass     = 2500
ENT.AllowGravGun = false
ENT.SoundPrefix  = "NPC_CombineGunship"
ENT.CanDive      = false
ENT.GibDamage    = 0
ENT.BatteryChance = 0

ENT.MaxSpeed         = 900       -- (1056 in the original)
ENT.CombatSpeedScale = 1
ENT.MaxVertSpeed     = 350
ENT.FlightAccel      = 380       -- units/s^2 (the original: 500)
ENT.MinGroundDist    = 260
ENT.CrashGravity     = 350
ENT.TurnRate         = 65
ENT.BankAngle        = 30
ENT.SightRange       = 6000
ENT.SightFOV         = 270
ENT.ForgetTime       = 8

ENT.StandOff       = 1800    -- horizontal distance it likes to keep while shooting
ENT.StandHeight    = 400     -- height above the target
ENT.BlastScale     = 3.75    -- explosion damage multiplier
ENT.BlastMinFrac   = 0.28    -- a real blast (80+) takes between this and
ENT.BlastMaxFrac   = 0.40    -- this share of full health: 3 to 4 explosions kill it
ENT.OtherScale     = 0.3     -- everything that is neither a bullet nor an explosion
ENT.BurstSize      = 15      -- sk_gunship_burst_size
ENT.BurstDelay     = 2.0     -- m_flBurstDelay (shortens as it gets hurt)
ENT.StitchMin      = 512     -- GUNSHIP_STITCH_MIN
ENT.StitchDist     = 768     -- sk_gunship_burst_dist
ENT.StitchSpeed    = 800     -- BASE_STITCH_VELOCITY
ENT.MaxBurstHits   = 5       -- GUNSHIP_MAX_HITS_PER_BURST
ENT.MinBlast       = 50      -- blasts weaker than this are ignored (GUNSHIP_MIN_DAMAGE_THRESHOLD)
ENT.ShotDamage     = 40      -- CombineCannon vs NPCs / vehicles
ENT.ShotDamagePlayer = 3     -- ...vs the player (1 once it has landed 5 hits in a burst)
ENT.BellyRange     = 650     -- horizontal range at which it goes for the belly blast
ENT.BellyHeight    = 512     -- hovers this high above the target while charging
ENT.BellyCharge    = 3
ENT.BellyCooldown  = 7
ENT.BellyRadius    = 256
ENT.BellyDamage    = 150
ENT.ExplosionDamage = 160
ENT.ExplosionRadius = 350
ENT.GibModels = { "models/gibs/gunship_gibs_headsection.mdl", "models/gibs/gunship_gibs_midsection.mdl",
                  "models/gibs/gunship_gibs_tailsection.mdl", "models/gibs/gunship_gibs_nosegun.mdl",
                  "models/gibs/metal_gib1.mdl", "models/gibs/metal_gib2.mdl", "models/gibs/metal_gib3.mdl" }
ENT.GibCount      = 7
ENT.GibSpeedMin   = 900
ENT.GibSpeedMax   = 1800
ENT.GibSpin       = 900

list.Set("MachineMayhem", "snpc_gunship", {
	Name = "Gunship", Class = "snpc_gunship", Group = "Bosses",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 96,
})

--=========================================================================
-- CLIENT: belly cannon charge
--=========================================================================
if CLIENT then
	ENT.RenderGroup = RENDERGROUP_BOTH
	local flare = Material("effects/blueblackflash")
	local beam  = Material("sprites/bluelaser1")

	function ENT:Draw() self:DrawModel() end

	function ENT:DrawTranslucent()
		self:DrawModel()
		local start = self:GetNWFloat("GsChargeStart", 0)
		if start <= 0 then return end
		local t = CurTime() - start
		if t < 0 or t > 3.6 then return end
		local id = self:LookupAttachment("BellyGun")
		local att = id and id > 0 and self:GetAttachment(id)
		local pos = att and att.Pos or self:GetPos()
		local sc = self:GetModelScale() or 1
		local f = math.Clamp(t / 2.9, 0, 1)
		local fade = t > 3.0 and math.Clamp(1 - (t - 3.0) / 0.6, 0, 1) or 1
		local a = math.floor(255 * math.min(1, t / 0.5) * fade)
		render.SetMaterial(flare)
		local s = 128 * sc * 3 * f * f
		render.DrawSprite(pos, s, s, Color(a, a, a, 255))
		if t > 2.0 then
			local w = 32 * sc * math.Clamp((t - 2.0) / 0.8, 0, 1) * (t > 2.9 and 4 or 1)
			render.SetMaterial(beam)
			local hit = self:GetNWVector("GsBellyHit", pos - Vector(0, 0, 900))
			render.DrawBeam(pos, hit, w, 0, 1, Color(a, a, a, 255))
		end
		local d = DynamicLight(self:EntIndex())
		if d then
			d.pos = pos
			d.r, d.g, d.b = 40, 60, 255
			d.brightness = 3 * f
			d.size = 400 * f
			d.decay = 1000
			d.dietime = CurTime() + 0.1
		end
	end
end

if not SERVER then return end

local scannerBase
local function SB(name)
	scannerBase = scannerBase or scripted_ents.Get("snpc_scanner")
	return scannerBase[name]
end

-- the collision body follows the model (scaled), a bit slimmer than its bounds
function ENT:InitPhysicsFlight()
	local mn, mx = self:GetModelBounds()
	local sc = self.ModelScale or 1
	if mn and mx and (mx - mn):Length() > 1 then
		self.PhysBox = { mn * sc * 0.6, mx * sc * 0.6 }
	else
		self.PhysBox = { Vector(-110, -35, -35), Vector(110, 35, 35) }
	end
	SB("InitPhysicsFlight")(self)
end

-- no photos, flashes or spotlight
function ENT:SpotlightWanted() return false end
function ENT:WantsFlashAttack() return false end
function ENT:TakePhoto() self.NextPhoto = CurTime() + 9999 end
function ENT:UpdateFlash() end
function ENT:UpdateSpotlight() end
function ENT:IdleActivity() return ACT_IDLE end

function ENT:Snd(name, level, pitch)
	if self.Silent then return end
	if name == "Pain" or name == "Die" then self:EmitSound(self.SoundPrefix .. "." .. (name == "Die" and "DyingSound" or "Pain"), level or 85, pitch or 100) end
end

-- the tail blades: "prop_turn" is the sequence that spins them, so it is the one it plays, alive and dying
function ENT:PlayIdle()
	local seq = self:LookupSequence("prop_turn")
	if seq and seq >= 0 then
		self.AnimSeq = seq
		if self:GetSequence() ~= seq then self:ResetSequence(seq) end
	else
		SB("PlayIdle")(self)
	end
end

-- looping is done by hand (the cycle follows the clock), so it never sticks at the start of the animation
function ENT:SpinBlades()
	local seq = self.AnimSeq
	if not seq or seq < 0 then return end
	if self:GetSequence() ~= seq then self:ResetSequence(seq) end
	local dur = self:SequenceDuration(seq)
	if not dur or dur <= 0 then dur = 1 end
	self:SetPlaybackRate(0)
	self:SetCycle((CurTime() / dur) % 1)
end

function ENT:OnScannerSpawned()
	if self.Hacked then self:SetSubMaterial(1, "models/gunship/gunship_hacked") end
	if self.EngSnd then self.EngSnd:Stop() end
	self.EngSnd = CreateSound(self, "NPC_CombineGunship.RotorSound")
	if self.EngSnd and not self.Silent then self.EngSnd:PlayEx(0.8, 100) end
	self:ResetPoses()
	self.IsFiring, self.PreFire = false, false
	self.BurstLeft, self.BurstHits = 0, 0
	self.NextAttack = CurTime() + 2
	self.AttackPos, self.AttackVel = nil, nil
	self.NextBelly = CurTime() + 4
	self.NextPing = CurTime() + 3
	self.Belly = nil
	self:SetNWFloat("GsChargeStart", 0)
end

function ENT:OnScannerRemoved()
	if self.EngSnd then self.EngSnd:Stop() end
	if self.CannonSnd then self.CannonSnd:Stop() end
	self:StopSound("NPC_CombineGunship.CannonSound")
	self:StopSound("NPC_CombineGunship.DyingSound")
end

function ENT:GetMaxSpeed()
	return self.MaxSpeed
end

-- Like the original's OnTakeDamage_Alive: only explosions (50+) and plain generic damage count. Bullets bounce off (a third
-- of them ricochet as tracers); everything else is ignored. A counted hit plays the pain sound, shoves it, and knocks
-- off a spray of metal chunks.
local CHUNKS = { "models/gibs/metal_gib1.mdl", "models/gibs/metal_gib2.mdl", "models/gibs/metal_gib3.mdl",
                 "models/gibs/metal_gib4.mdl", "models/gibs/metal_gib5.mdl" }
function ENT:DumpMetal(dir)
	local base = self:GetPos()
	local vel = (self.CurVel or vector_origin) + (-dir * 200)
	for _ = 1, 10 do
		local g = ents.Create("prop_physics")
		if IsValid(g) then
			g:SetModel(CHUNKS[math.random(#CHUNKS)])
			g:SetPos(base + VectorRand() * 40)
			g:SetAngles(AngleRand())
			g:Spawn()
			g:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
			local ph = g:GetPhysicsObject()
			if IsValid(ph) then
				ph:Wake()
				ph:SetVelocity(vel + VectorRand() * 400)
				ph:AddAngleVelocity(VectorRand() * 300)
			end
			SafeRemoveEntityDelayed(g, 2.5)
		end
	end
end

function ENT:ModifyDamage(dmg)
	if dmg:GetAttacker() == self or self.Crashing then dmg:SetDamage(0) return end
	local t = dmg:GetDamageType()
	if t ~= DMG_GENERIC then
		if bit.band(t, DMG_BLAST) == 0 then
			if dmg:IsBulletDamage() and math.random(0, 2) == 0 then
				local p = dmg:GetDamagePosition()
				local d = dmg:GetDamageForce():GetNormalized()
				local ed = EffectData()
				ed:SetStart(p) ed:SetOrigin(p - d * 1024 + VectorRand() * 300) ed:SetScale(3500)
				util.Effect("Tracer", ed)
			end
			dmg:SetDamage(0)
			return
		end
		if dmg:GetDamage() < self.MinBlast then dmg:SetDamage(0) return end
		local raw = dmg:GetDamage()
		local scaled = raw * self.BlastScale
		if raw >= 80 then
			local mx = self:GetMaxHealth()
			scaled = math.Clamp(scaled, mx * self.BlastMinFrac, mx * self.BlastMaxFrac)
		end
		dmg:SetDamage(scaled)
	end
	local dir = dmg:GetDamageForce()
	dir = dir:LengthSqr() > 0 and dir:GetNormalized() or VectorRand()
	-- (one blast can arrive as several damage events: a repeated EmitSound restarts the sound, which sounded cut off)
	if not self.Silent and CurTime() >= (self.NextPain or 0) then
		self.NextPain = CurTime() + 1.2
		self:EmitSound("NPC_CombineGunship.Pain", 90, 100, 1, CHAN_VOICE)
	end
	if not self.Belly or not self.Belly.charging then self.CurVel = self.CurVel + dir * 200 end
	self:DumpMetal(dir)
end

local function Attach(self, name)
	local id = self:LookupAttachment(name)
	local att = id and id > 0 and self:GetAttachment(id)
	if att then return att.Pos, att.Ang:Forward() end
	return self:WorldSpaceCenter(), self:GetForward()
end

--=========================================================================
-- Flight (the real one's Flight(): accelerate toward a goal with momentum, tilt and bank into the acceleration)
--=========================================================================
function ENT:FlyTo(dt, goal, speedScale, hold)
	local pos = self:GetPos()
	local to = goal - pos
	local dist = to:Length()
	local maxSpeed = self.MaxSpeed * (speedScale or 1)
	local want = vector_origin
	if dist > 8 then
		-- slow down on approach so it settles over the goal instead of orbiting it
		want = (to / dist) * math.min(maxSpeed, dist * 0.45)
	end
	local v = self.CurVel
	local dv = want - v
	if not hold then
		-- heavy: shedding speed is slower than gaining it
		local sp = v:Length()
		if sp > 80 then
			local vn = v / sp
			local along = dv:Dot(vn)
			if along < 0 then dv = dv - vn * along * 0.65 end
		end
	end
	local acc = self.FlightAccel * (hold and 1.6 or 1)
	local maxDv = acc * dt
	local len = dv:Length()
	if len > maxDv then dv = dv * (maxDv / len) end
	local nv = v + dv
	nv.z = math.Clamp(nv.z, -self.MaxVertSpeed, self.MaxVertSpeed)
	-- sway: a slow figure-of-eight, like the heavy rocking of the real thing
	local t = CurTime() + (self.BobBase or 0)
	nv.x = nv.x + math.sin(t * 0.7) * 6 * dt * 10
	nv.y = nv.y + math.cos(t * 0.55) * 6 * dt * 10
	nv.z = nv.z + math.sin(t * 0.9) * 4 * dt * 10
	self.CurVel = nv
	self.GsAccel = dv / math.max(dt, 0.001)

	-- tilt into the acceleration (nose down when speeding up, rolls into turns)
	local fwd, right = self:GetForward(), self:GetRight()
	local a = self.GsAccel
	local k = self.BankAngle / math.max(self.FlightAccel, 1)
	self.BankTarget = Vector(math.Clamp(a:Dot(fwd) * k * 1.4, -45, 45), 0, math.Clamp(a:Dot(right) * k * 1.4, -45, 45))
end

function ENT:UpdateMovement(dt)
	if self.Held or self.Crashing then return end
	local foe = self:GetFoe()
	self.TurnRate = IsValid(foe) and 65 or 40
	if self.MissileBurst then self.TurnRate = 220 end
	if IsValid(foe) then self:CombatMove(dt, foe) else self:PatrolMove(dt) end
	self:LimitSpeed(self.MaxVertSpeed, self.MaxSpeed)
end

function ENT:PickPatrolGoal()
	local pos = self:GetPos()
	for _ = 1, 8 do
		local dir = Angle(0, math.Rand(0, 360), 0):Forward()
		local dist = math.Rand(800, 3000)
		local tr = util.TraceLine({ start = pos, endpos = pos + dir * dist, mask = MASK_NPCSOLID_BRUSHONLY, filter = self })
		if tr.Fraction > 0.5 then
			local p = tr.HitPos - dir * 300
			local fl = util.TraceLine({ start = p + Vector(0, 0, 100), endpos = p - Vector(0, 0, 1500), mask = MASK_NPCSOLID_BRUSHONLY, filter = self })
			if fl.Hit then return fl.HitPos + Vector(0, 0, math.Rand(450, 800)) end
		end
	end
	return pos
end

function ENT:PatrolMove(dt)
	local now = CurTime()
	local pos = self:GetPos()
	if not self.PatrolGoal or now >= self.NextPatrol or pos:DistToSqr(self.PatrolGoal) < 200 * 200 then
		self.PatrolGoal = self:PickPatrolGoal()
		self.NextPatrol = now + 14
	end
	self:FlyTo(dt, self:SteerAround(self.PatrolGoal), 0.5)
end

-- Orbit, after Hunter's Glee's gunship: it never aims at a point on the circle, it aims at a "carrot" ahead of itself at an
-- angle off the line to the target (60 degrees: spirals in, 90 = tangent). Too far out = turn in more, too close = turn
-- out. The heading keeps 40% of the way it is already going. Walls / lost line of sight flip the orbit direction and pull
-- the radius in; open ground lets it grow back.
ENT.OrbitBaseAngle  = 60
ENT.OrbitCorrection = 30
ENT.OrbitBand       = 200
ENT.OrbitMomentum   = 0.4
ENT.CarrotDist      = 1400
ENT.CarrotInterval  = 0.7
local BOBS = { { height = 150, period = 24 }, { height = 150, period = 9 } }

local function FlatDir(from, to)
	local d = to - from
	d.z = 0
	if d:LengthSqr() < 1 then return Vector(1, 0, 0) end
	d:Normalize()
	return d
end

function ENT:OrbitCarrot(center, canSee)
	local pos = self:GetPos()
	local st = self.Orbit
	local toC = FlatDir(pos, center)
	local dist = Vector(center.x - pos.x, center.y - pos.y, 0):Length()
	local radius = self.StandOff * st.radiusMul
	local ang = self.OrbitBaseAngle
	if math.abs(dist - radius) > self.OrbitBand then
		ang = ang + (dist > radius and -self.OrbitCorrection or self.OrbitCorrection)
	end
	local vel = self.CurVel
	local momentum = vel:Length2D() < 100 and self:GetForward() or Vector(vel.x, vel.y, 0):GetNormalized()
	momentum.z = 0

	local function heading(dir)
		local r = Vector(toC)
		r:Rotate(Angle(0, ang * dir, 0))
		local h = momentum * self.OrbitMomentum + r * (1 - self.OrbitMomentum)
		h:Normalize()
		return h, r
	end
	local h, r = heading(st.dir)
	local carrot = pos + h * self.CarrotDist
	local clear = self:IsPathClear(h, self.CarrotDist) and util.IsInWorld(carrot)
	local seen = util.TraceLine({ start = center, endpos = pos + h * 2000, mask = MASK_SOLID_BRUSHONLY }).Fraction >= 0.99
	local outcome = "clear"
	if clear and (seen or not canSee) then
		st.radiusMul = math.min(1, st.radiusMul * (canSee and 1.05 or 1))
	elseif clear then
		st.dir = -st.dir
		h = heading(st.dir)
		st.radiusMul = math.max(0.4, st.radiusMul * 0.85)
	else
		st.dir = -st.dir
		h = heading(st.dir)
		st.radiusMul = math.max(0.4, st.radiusMul * 0.9)
	end
	return h
end

local function BobHeight()
	local t, h = CurTime(), 0
	for _, b in ipairs(BOBS) do
		if t % b.period < b.period / 2 then h = h + b.height end
	end
	return h
end

-- An enemy below it, in plain sight and not far: it dives to run them down (a crushing hit when it reaches them), then
-- pulls away and does not try again for a while.
ENT.RamRange = 1700
ENT.RamDrop = 150
ENT.RamDamage = 400

function ENT:RamMove(dt, foe, now)
	local pos = self:GetPos()
	local c = foe:WorldSpaceCenter()
	local r = self.Ram
	if not r then
		if now < (self.NextRam or 0) or not self.FoeVisible then return false end
		if c.z > pos.z - self.RamDrop or pos:Distance(c) > self.RamRange then return false end
		r = { start = now }
		self.Ram = r
	end
	local d = pos:Distance(c)
	local reach = (self.HullMaxs and self.HullMaxs:Length2D() or 150) + 90
	if now - r.start > 4.5 or not self.FoeVisible or d > self.RamRange * 1.4 or foe:Health() <= 0 then
		self.Ram = nil
		self.NextRam = now + math.Rand(8, 14)
		return false
	end
	if d < reach then
		local dmg = DamageInfo()
		dmg:SetAttacker(self) dmg:SetInflictor(self)
		dmg:SetDamage(self.RamDamage) dmg:SetDamageType(DMG_CRUSH)
		dmg:SetDamagePosition(c) dmg:SetDamageForce((c - pos):GetNormalized() * 40000)
		foe:TakeDamageInfo(dmg)
		self:EmitSound("physics/metal/metal_large_debris2.wav", 100, 80)
		self.Ram = nil
		self.NextRam = now + math.Rand(8, 14)
		self.CurVel = self.CurVel * -0.3 + Vector(0, 0, 250) -- bounces off, up and away
		return false
	end
	self.TurnRate = 80
	self:FlyTo(dt, c, 1.35)
	return true
end

function ENT:CombatMove(dt, foe)
	local now = CurTime()
	local pos = self:GetPos()
	local target = self.FoeVisible and foe:WorldSpaceCenter() or (self:GetChasePos() or foe:WorldSpaceCenter())

	if self.Belly then
		-- belly blast: get right over the target, high up, then hold still while it charges
		local ground = util.TraceLine({ start = target, endpos = target - Vector(0, 0, 2000), mask = MASK_NPCSOLID_BRUSHONLY, filter = { self, foe } })
		local gz = ground.Hit and ground.HitPos.z or target.z
		local goal = Vector(target.x, target.y, math.max(gz, target.z) + self.BellyHeight)
		local flat = Vector(goal.x - pos.x, goal.y - pos.y, 0):Length()
		self.Belly.inPlace = flat < 140 and math.abs(goal.z - pos.z) < 140
		self:FlyTo(dt, self:SteerAround(goal, foe), self.Belly.charging and 0.15 or 0.9, self.Belly.charging)
		return
	end

	if self:RamMove(dt, foe, now) then return end

	self.Orbit = self.Orbit or { dir = math.random() < 0.5 and 1 or -1, radiusMul = 1, nextCarrot = 0 }
	local st = self.Orbit
	local center = target + foe:GetVelocity() * 1.0
	if now >= st.nextCarrot or not st.heading then
		st.nextCarrot = now + self.CarrotInterval
		st.heading = self:OrbitCarrot(center, self.FoeVisible)
	end
	local carrot = pos + st.heading * self.CarrotDist
	-- altitude: above the target, stepping up and down like Glee's square-wave bobs
	local gtr = util.TraceLine({ start = target, endpos = target - Vector(0, 0, 8000), mask = MASK_SOLID_BRUSHONLY, filter = { self, foe } })
	local baseZ = gtr.Hit and gtr.HitPos.z or math.min(target.z, pos.z)
	if foe.IsPhysicsSNPC or foe:GetClass() == "npc_combinegunship" or foe:GetClass() == "npc_helicopter" then
		-- an aerial target: stand off at the same height band over the ground, not above wherever it is
		baseZ = math.min(baseZ, target.z)
	end
	carrot.z = math.min(math.max(target.z, baseZ) + self.StandHeight, baseZ + self.StandHeight + 250) + BobHeight()
	self:FlyTo(dt, self:SteerAround(carrot, foe), 1)
end

--=========================================================================
-- Pose parameters: head (flex_horz / flex_vert) follows the target, fins (fin_accel / fin_sway) follow the acceleration
--=========================================================================
-- The pose values are kept here (not read back from the entity: GetPoseParameter can return a 0..1 value, which made
-- the head / fins flip to an extreme every other tick) and every parameter is clamped to its real range.
local function PoseRange(self, name)
	local idx = self:LookupPoseParameter(name)
	if not idx or idx < 0 then return end
	local lo, hi = self:GetPoseParameterRange(idx)
	return lo or -90, hi or 90
end

local function SetPose(self, name, val)
	local lo, hi = PoseRange(self, name)
	if not lo then return 0 end
	val = math.Clamp(val, lo, hi)
	self.PoseVals[name] = val
	self:SetPoseParameter(name, val)
	return val
end

function ENT:ResetPoses()
	self.PoseVals = {}
	for _, n in ipairs({ "flex_horz", "flex_vert", "fin_accel", "fin_sway", "pitch", "yaw", "weapon_pitch", "weapon_yaw" }) do
		SetPose(self, n, 0)
	end
	self.GunAng = Angle(0, 0, 0)
	self.LastAngYaw, self.LastAngPitch = nil, nil
end

local function Spline(x)
	local t = math.Clamp((x + 60) / 120, 0, 1)
	return (t * t * (3 - 2 * t)) * 2 - 1
end

-- port of CNPC_CombineGunship::MoveHead / PoseGunTowardTargetDirection / the fin blends
function ENT:UpdatePoses(dt)
	if not self.PoseVals then self:ResetPoses() end
	dt = math.Clamp(dt or 0.05, 0.001, 0.2)
	local pv = self.PoseVals
	local ang = self:GetAngles()

	-- head
	local yaw, pitch = pv.flex_horz or 0, pv.flex_vert or 0
	local foe = self:GetFoe()
	if IsValid(self.MissileAim) and CurTime() < (self.MissileAimUntil or 0) then foe = self.MissileAim end
	local looking = false
	if IsValid(foe) then
		local att = self:LookupAttachment("muzzle")
		local a = att and att > 0 and self:GetAttachment(att)
		if a then
			local target = foe:WorldSpaceCenter()
			local d = target - a.Pos
			if self:GetForward():Dot(d:GetNormalized()) > 0.3 then
				local want = d:Angle()
				yaw = math.Approach(yaw, yaw + math.AngleDifference(want.y, a.Ang.y) * 0.9, 50 * dt)
				pitch = math.Approach(pitch, pitch + math.AngleDifference(want.p, a.Ang.p) * 0.9, 50 * dt)
				looking = true
			end
		end
	end
	if not looking then
		-- look where it's going: follow the body's rotation rate
		local ry = self.LastAngYaw and math.AngleDifference(ang.y, self.LastAngYaw) / dt or 0
		local rp = self.LastAngPitch and math.AngleDifference(ang.p, self.LastAngPitch) / dt or 0
		yaw = math.Approach(yaw, math.Clamp(ry, -30, 30), 20 * dt)
		pitch = math.Approach(pitch, math.Clamp(rp, -30, 30), 20 * dt)
	end
	self.LastAngYaw, self.LastAngPitch = ang.y, ang.p
	SetPose(self, "flex_vert", pitch)
	SetPose(self, "flex_horz", yaw)

	-- the gun swivels at 120 deg/s toward the target (or home)
	local g = self.GunAng
	local tp, ty = 0, 0
	if IsValid(foe) then
		local att = self:LookupAttachment("muzzle")
		local a = att and att > 0 and self:GetAttachment(att)
		local origin = a and a.Pos or self:GetPos()
		local la = self:WorldToLocalAngles((foe:WorldSpaceCenter() - origin):Angle())
		tp, ty = math.NormalizeAngle(la.p), math.NormalizeAngle(la.y)
	end
	g.p = math.Approach(g.p, tp, 120 * dt)
	g.y = math.Approach(g.y, ty, 120 * dt)
	SetPose(self, "weapon_pitch", -g.p)
	SetPose(self, "weapon_yaw", g.y)

	-- fins: how hard it is accelerating along / across its heading
	local a = self.GsAccel or vector_origin
	local vel = self.CurVel or vector_origin
	local vdir, adir = Vector(vel.x, vel.y, 0), Vector(a.x, a.y, 0)
	local force = adir:Length() * 0.2
	local velN = vdir:Length() > 1 and vdir:GetNormalized() or vector_origin
	local accN = adir:Length() > 1 and adir:GetNormalized() or vector_origin
	local right = self:GetRight()
	right.z = 0
	if right:LengthSqr() > 0 then right:Normalize() end
	local fa = Spline(force * velN:Dot(accN))
	local fs = Spline(force * velN:Dot(right))
	SetPose(self, "fin_accel", math.Approach(pv.fin_accel or 0, fa, 5 * dt))
	SetPose(self, "fin_sway", math.Approach(pv.fin_sway or 0, fs, 5 * dt))
end

--=========================================================================
-- Weapons
--=========================================================================
function ENT:StartBelly()
	self.Belly = { start = CurTime(), inPlace = false, charging = false }
	self.BellyAbort = CurTime() + 9
	self.NextBelly = CurTime() + self.BellyCooldown
end

-- the charge begins once it is hovering over the target
function ENT:BeginBellyCharge()
	local b = self.Belly
	b.charging, b.chargeStart = true, CurTime()
	self:SetNWFloat("GsChargeStart", CurTime())
	if not self.Silent then self:EmitSound("NPC_Strider.Charge", 100) end
	sound.EmitHint(SOUND_DANGER, self:GetPos() - Vector(0, 0, 300), 1024, 3, self)
end

-- the aimed point on the ground under the belly gun
function ENT:BellyHitPoint()
	local pos = Attach(self, "BellyGun")
	local tr = util.TraceLine({ start = pos, endpos = pos - Vector(0, 0, 3000), mask = MASK_SOLID, filter = self })
	return pos, tr
end

-- warning beam while charging: it punches whatever is underneath (1 damage + sparks)
function ENT:BellyWarning(now)
	if now < (self.NextWarn or 0) then return end
	self.NextWarn = now + 0.1
	local _, tr = self:BellyHitPoint()
	self:SetNWVector("GsBellyHit", tr.HitPos)
	local ed = EffectData()
	ed:SetOrigin(tr.HitPos) ed:SetNormal(tr.HitNormal) ed:SetMagnitude(2) ed:SetScale(1) ed:SetRadius(2)
	util.Effect("ElectricSpark", ed)
	if IsValid(tr.Entity) and tr.Entity ~= self then
		local d = DamageInfo()
		d:SetAttacker(self) d:SetInflictor(self) d:SetDamage(1) d:SetDamageType(DMG_ENERGYBEAM)
		d:SetDamagePosition(tr.HitPos)
		tr.Entity:TakeDamageInfo(d)
	end
end

function ENT:FireBelly()
	local pos, tr = self:BellyHitPoint()
	local hit = tr.HitPos
	self.Belly = nil
	self.NextBelly = CurTime() + self.BellyCooldown
	self.BellyHold = CurTime() + 1.2
	self:SetNWFloat("GsChargeStart", 0)
	if not self.Silent then self:EmitSound("NPC_Strider.Shoot", 105) end
	local ed = EffectData()
	ed:SetOrigin(hit) ed:SetNormal(tr.HitNormal) ed:SetScale(3) ed:SetMagnitude(3)
	util.Effect("AR2Explosion", ed)
	util.Effect("Explosion", ed)
	local ring = EffectData()
	ring:SetOrigin(hit + Vector(0, 0, 4)) ring:SetNormal(vector_up or Vector(0, 0, 1)) ring:SetScale(256) ring:SetMagnitude(256) ring:SetRadius(256)
	util.Effect("ThumperDust", ring)
	util.ScreenShake(hit, 16, 120, 1.5, 1200)
	-- vertical column: everything within the radius of the impact, plus a tall box above it
	util.BlastDamage(self, self, hit + Vector(0, 0, 8), self.BellyRadius, self.BellyDamage)
	for _, e in ipairs(ents.FindInSphere(hit + Vector(0, 0, 64), self.BellyRadius * 1.3)) do
		if IsValid(e) and e ~= self and not e:IsPlayer() and not e:IsNPC() then
			local ph = e:GetPhysicsObject()
			if IsValid(ph) then
				ph:Wake()
				local push = (e:WorldSpaceCenter() - hit)
				push.z = math.abs(push.z) + 40
				ph:ApplyForceCenter(push:GetNormalized() * math.min(ph:GetMass() * 450, 80000))
			end
		end
	end
end

-- cannon loop (the real one fades a looping sound in and out around each burst)
function ENT:CannonLoop(on)
	if on then
		if not self.CannonSnd then self.CannonSnd = CreateSound(self, "NPC_CombineGunship.CannonSound") end
		if self.CannonSnd and not self.CannonSnd:IsPlaying() and not self.Silent then self.CannonSnd:PlayEx(1, 100) end
	elseif self.CannonSnd then
		self.CannonSnd:FadeOut(0.15)
	end
end

-- shoots down missiles that are heading for it (rpg missiles, Glee's gunship missiles, ...)
local MissileClasses = { "rpg_missile", "apc_missile", "glee_gunshipmissile", "grenade_homer" }

-- a hit missile does not blow up on the spot: Valve's CMissile goes into its auger (spiralling, smoking) when it takes
-- DMG_MISSILEDEFENSE damage, and explodes after 1.5 s wherever it ends up
local function LoseControl(m, attacker)
	local p = m:GetPos()
	if m.Detonate then
		-- Glee's missile flies along its own forward every tick, so wobbling its angles sends it off course
		local e2 = EffectData()
		e2:SetOrigin(p)
		util.Effect("RPGShotDown", e2)
		local t0 = CurTime()
		local id = "physsnpc_lostmissile_" .. m:EntIndex()
		timer.Create(id, 0.04, 0, function()
			if not IsValid(m) or m:GetDetonated() or CurTime() - t0 > 1.3 then
				if IsValid(m) and not m:GetDetonated() then m:Detonate(m:GetPos(), true) end
				timer.Remove(id)
				return
			end
			m:SetAngles(m:GetAngles() + Angle(math.Rand(-9, 9), math.Rand(-14, 14), 0))
		end)
		return
	end
	local d = DamageInfo()
	d:SetAttacker(IsValid(attacker) and attacker or game.GetWorld()) d:SetInflictor(IsValid(attacker) and attacker or game.GetWorld())
	d:SetDamage(40) d:SetDamageType(DMG_MISSILEDEFENSE)
	d:SetDamagePosition(p)
	m:TakeDamageInfo(d)
end

function ENT:DefendMissiles(now)
	if now < (self.NextMissileCheck or 0) then return end
	self.NextMissileCheck = now + 0.1
	local c = self:WorldSpaceCenter()
	for _, class in ipairs(MissileClasses) do
		for _, m in ipairs(ents.FindByClass(class)) do
			if IsValid(m) and not m.PhysSNPCShot then
				local owner = m:GetOwner()
				local friendly = owner == self or (IsValid(owner) and owner.IsPhysicsSNPC and owner.Hacked == self.Hacked)
					or (IsValid(owner) and self.IsValidTarget and not self:IsValidTarget(owner) and owner ~= self)
				local mp = m:GetPos()
				local dist = mp:Distance(c)
				if not friendly and dist < 2200 then
					-- (some missiles carry no velocity of their own, so fall back to the way they point)
					local v = m:GetVelocity()
					local dir = v:Length() > 30 and v:GetNormalized() or m:GetForward()
					if dir:Dot((c - mp):GetNormalized()) > 0.8 then
						m.PhysSNPCShot = true
						self:ShootDownMissile(m, dist, dir)
					end
				end
			end
		end
	end
end

-- It turns to face the missile and shoots at it with its normal cannon (real bullets, muzzle flash, tracers, the cannon
-- loop): the first rounds land a little off, then the aim settles on it. Only fired while the missile is in front of
-- the gun (never backwards), and it dodges sideways meanwhile.
function ENT:ShootDownMissile(m, dist, dir)
	local now = CurTime()
	self.MissileAim = m
	self.MissileAimUntil = now + 1.2
	local side = dir:Cross(Vector(0, 0, 1))
	side:Normalize()
	if not self:IsPathClear(side, 500) then side = -side end
	self.CurVel = self.CurVel + side * 420 + Vector(0, 0, math.random(-120, 160))
	if self.Belly then m.PhysSNPCShot = nil return end -- busy with the belly cannon: it can only dodge
	self:AbortBurst()
	self.MissileBurst = { m = m, start = now, stop = now + 1.6, off = VectorRand() * 130, nextRound = now + 0.1, shots = 0 }
	self:CannonLoop(true)
end

function ENT:EndMissileBurst()
	local mb = self.MissileBurst
	self.MissileBurst = nil
	self:CannonLoop(false)
	if mb and mb.shots > 0 and not self.Silent then self:EmitSound("NPC_CombineGunship.CannonStopSound", 90) end
	self.NextAttack = CurTime() + 0.5
	if mb and IsValid(mb.m) and not mb.done then mb.m.PhysSNPCShot = nil end -- not down yet: it may try again
end

function ENT:UpdateMissileFire(now)
	local mb = self.MissileBurst
	if not mb then return false end
	local m = mb.m
	if not IsValid(m) or now > mb.stop or mb.done then self:EndMissileBurst() return false end
	self.NextAttack = now + 0.5
	if now < mb.nextRound then return true end
	local muzzle, mfwd = Attach(self, "muzzle")
	local mp = m:GetPos()
	local v = m:GetVelocity()
	local aim = mp + v * 0.05 + mb.off * math.max(0, 1 - (now - mb.start) / 0.4)
	local dirTo = (aim - muzzle)
	dirTo:Normalize()
	-- the gun only points so far: nothing is fired backwards, it waits for the missile to swing into the cone
	if dirTo:Dot(mfwd) < 0.8 then return true end
	mb.nextRound = now + 0.05
	mb.shots = mb.shots + 1
	local ed = EffectData()
	ed:SetEntity(self) ed:SetAttachment(self:LookupAttachment("muzzle")) ed:SetOrigin(muzzle)
	util.Effect("physsnpc_gunship_muzzle", ed)
	local me = self
	self:FireBullets({
		Attacker = self, Inflictor = self, Damage = 1, Force = 4, Num = 1,
		Src = muzzle, Dir = dirTo, Spread = vector_origin, Tracer = 0, AmmoType = "AR2", IgnoreEntity = self,
		Callback = function(att, tr, dmg)
			dmg:SetDamage(1)
			me:ShotFX(muzzle, tr)
			-- (the missile is small: a round passing close enough counts as the hit)
			if IsValid(m) and not mb.done and (tr.Entity == m or util.DistanceToLine(muzzle, tr.HitPos, m:GetPos()) < 45) then
				mb.done = true
				LoseControl(m, me)
			end
		end,
	})
	return true
end

-- the gun and the nose follow the missile while it is shooting at it
function ENT:GetChasePos()
	if self.MissileBurst and IsValid(self.MissileBurst.m) then return self.MissileBurst.m:GetPos() end
	return SB("GetChasePos")(self)
end

function ENT:OnScannerThink(dt)
	local now = CurTime()
	self:SpinBlades()
	if self.Held or self.Crashing then return end
	self:DefendMissiles(now)
	if self.MissileBurst and self:UpdateMissileFire(now) then return end

	if not self.Silent and now >= self.NextPing then
		self.NextPing = now + 3
		self:EmitSound(IsValid(self:GetFoe()) and "NPC_CombineGunship.SeeEnemy" or "NPC_CombineGunship.PatrolPing", 85)
	end

	local foe = self:GetFoe()
	if not IsValid(foe) then
		self.Belly = nil
		self:AbortBurst()
		self:SetNWFloat("GsChargeStart", 0)
		return
	end
	local pos = self:GetPos()
	local fc = foe:WorldSpaceCenter()
	local flat = Vector(fc.x - pos.x, fc.y - pos.y, 0):Length()

	-- belly blast: fly over the target, hover, charge (warning beam), blast
	local bl = self.Belly
	if bl then
		self:AbortBurst()
		if not bl.charging then
			if bl.inPlace then self:BeginBellyCharge() end
			if now > self.BellyAbort then self.Belly = nil end
		else
			self:BellyWarning(now)
			if now - bl.chargeStart >= self.BellyCharge then self:FireBelly() end
		end
		return -- no cannon meanwhile
	elseif now >= self.NextBelly and now >= (self.BellyHold or 0) and flat < self.BellyRange and fc.z < pos.z - 100 and self.FoeVisible then
		self:StartBelly()
		return
	end

	self:UpdateCannon(foe, now)
end

-- shared with FireBelly etc.
function ENT:AbortBurst()
	self.IsFiring, self.PreFire = false, false
	self.BurstLeft = 0
	self:CannonLoop(false)
end

function ENT:EnemyAimPos(foe)
	if foe:IsPlayer() and foe:InVehicle() then return foe:WorldSpaceCenter() end
	return foe.EyePos and foe:EyePos() or foe:WorldSpaceCenter()
end

-- StartCannonBurst: the stitch starts off to one side of where the target will be in 2 s, sweeping toward it
function ENT:StartCannonBurst(foe)
	self.BurstLeft, self.BurstHits = self.BurstSize, 0
	self.NextAttack = CurTime()
	self.IsFiring = true
	self:CannonLoop(true)
	local pred = foe:GetPos() + foe:GetVelocity() * 2
	pred.z = foe:GetPos().z + (foe:OBBMaxs().z * 0.7)
	local offDir = (self:WorldSpaceCenter() - pred)
	offDir:Normalize()
	local ang = offDir:Angle()
	local off = math.random(15, 30) * (math.random(0, 1) == 1 and -1 or 1)
	ang.y = ang.y + off
	ang.p, ang.r = 0, 0
	offDir = ang:Forward()
	local dist = Vector(foe:GetPos().x - self:GetPos().x, foe:GetPos().y - self:GetPos().y, 0):Length()
	local stitch = dist < (self.StitchDist + self.StitchMin) and self.StitchMin or self.StitchDist
	self.AttackPos = pred + offDir * stitch
	self.AttackPos.z = pred.z
	self.AttackVel = -offDir * self.StitchSpeed
	sound.EmitHint(SOUND_DANGER, pred, 512, 0.2, self)
end

function ENT:StopCannonBurst()
	local left = self.BurstLeft
	self.IsFiring, self.PreFire = false, false
	self.BurstLeft, self.BurstHits = 0, 0
	local perc = self:Health() / math.max(self:GetMaxHealth(), 1)
	local delay = math.Clamp(perc * self.BurstDelay, 0.5, self.BurstDelay)
	delay = delay * (1 - left / self.BurstSize)   -- cut short = no long wait
	self.NextAttack = CurTime() + delay
	self:CannonLoop(false)
	if not self.Silent then self:EmitSound("NPC_CombineGunship.CannonStopSound", 90) end
end

-- UpdateEnemyTarget: the aim point sweeps along a line, its heading turning toward the target by at most 6 deg
-- per round (30 for non-players)
function ENT:UpdateEnemyTarget(foe)
	local enemyPos = self:EnemyAimPos(foe)
	local ap, av = self.AttackPos or enemyPos, self.AttackVel or vector_origin
	local targetDir = enemyPos - ap
	targetDir:Normalize()
	local lastSpeed = av:Length()
	local avDir = lastSpeed > 0.001 and av / lastSpeed or targetDir
	local chase, last = targetDir:Angle(), avDir:Angle()
	local yawDiff = math.AngleDifference(last.y, chase.y)
	local maxYaw = foe:IsPlayer() and 6 or 30
	yawDiff = math.Clamp(yawDiff, -maxYaw, maxYaw)
	chase.p, chase.r = 0, 0
	local maxHits = self.BurstHits >= self.MaxBurstHits or (foe.Health and foe:Health() <= 0)
	if maxHits then
		chase.y = last.y
		lastSpeed = self.StitchSpeed
	else
		chase.y = math.NormalizeAngle(last.y - yawDiff)
	end
	if maxHits or ap:DistToSqr(enemyPos) > 64 * 64 then
		self.AttackVel = chase:Forward() * lastSpeed
		ap = ap + self.AttackVel * 0.1
		ap.z = enemyPos.z
		self.AttackPos = ap
	else
		self.AttackPos = enemyPos
	end
end

-- the tracer of one round (variants replace it)
function ENT:ShotFX(muzzle, tr)
	local te = EffectData()
	te:SetStart(muzzle) te:SetOrigin(tr.HitPos) te:SetScale(8000) te:SetFlags(1)
	util.Effect("physsnpc_gunship_tracer", te)
end

function ENT:FireCannonRound(foe)
	local muzzle, mfwd = Attach(self, "muzzle")
	local toEnemy = (self.AttackPos - muzzle)
	toEnemy:Normalize()
	local chk = (foe:GetPos() - muzzle)
	chk:Normalize()
	if chk:Dot(mfwd) < 0.8 then self:StopCannonBurst() return end

	local ed = EffectData()
	ed:SetEntity(self) ed:SetAttachment(self:LookupAttachment("muzzle")) ed:SetOrigin(muzzle)
	util.Effect("physsnpc_gunship_muzzle", ed)
	self.NextAttack = CurTime() + 0.05
	self.BurstLeft = self.BurstLeft - 1
	local me = self
	self:FireBullets({
		Attacker = self, Inflictor = self, Damage = self.ShotDamage, Force = 4, Num = 1,
		Src = muzzle, Dir = toEnemy, Spread = self.ShotSpread or vector_origin, Tracer = 0, AmmoType = "AR2", IgnoreEntity = self,
		Callback = function(att, tr, dmg)
			local e = tr.Entity
			if IsValid(e) and e:IsPlayer() then
				dmg:SetDamage(me.BurstHits >= me.MaxBurstHits and 1 or me.ShotDamagePlayer)
			end
			if IsValid(e) and e == foe then me.BurstHits = me.BurstHits + 1 end
			me:ShotFX(muzzle, tr)
		end,
	})
end

function ENT:UpdateCannon(foe, now)
	if self.IsFiring then
		if self.BurstLeft > 0 and now > self.NextAttack then
			self:UpdateEnemyTarget(foe)
			self:FireCannonRound(foe)
		elseif self.BurstLeft < 1 then
			self:StopCannonBurst()
		end
		return
	end
	-- not firing: just look at the enemy
	self.AttackPos = self:EnemyAimPos(foe)
	if now <= self.NextAttack then return end
	-- 0.5 s wind-up first
	if not self.PreFire then
		self.PreFire = true
		self.NextAttack = now + 0.5
		if not self.Silent then self:EmitSound("NPC_CombineGunship.CannonStartSound", 90) end
		return
	end
	if not self.FoeVisible then return end
	local pos = self:GetPos()
	local flat = Vector(foe:GetPos().x - pos.x, foe:GetPos().y - pos.y, 0):Length()
	if flat < self.StitchMin then return end
	local muzzle, mfwd = Attach(self, "muzzle")
	local to = (self.AttackPos - muzzle)
	to:Normalize()
	if to:Dot(mfwd) > 0.9 then self:StartCannonBurst(foe) end
end

-- the real smoke trail (env_smoketrail on the left exhaust): 48 / s, 24 -> 128 units, grey fading to black, thin;
-- thick and dark once it is going down
function ENT:CreateSmokeTrail(heavy)
	if IsValid(self.SmokeTrail) then
		if not heavy then return end
		self.SmokeTrail:Remove()
	end
	local s = ents.Create("env_smoketrail")
	if not IsValid(s) then return end
	s:SetKeyValue("spawnrate", "48")
	s:SetKeyValue("lifetime", "2.5")
	s:SetKeyValue("startcolor", "64 64 64")
	s:SetKeyValue("endcolor", "0 0 0")
	s:SetKeyValue("startsize", heavy and "64" or "24")
	s:SetKeyValue("endsize", "128")
	s:SetKeyValue("spawnradius", "4")
	s:SetKeyValue("minspeed", "8")
	s:SetKeyValue("maxspeed", "64")
	s:SetKeyValue("opacity", heavy and "0.5" or "0.2")
	local id = self:LookupAttachment("exhaustl")
	local att = id and id > 0 and self:GetAttachment(id)
	s:SetPos(att and att.Pos or self:GetPos())
	s:Spawn()
	s:Activate()
	s:SetParent(self, (id and id > 0) and id or -1)
	self.SmokeTrail = s
end

function ENT:OnDamaged(dmg)
	-- smoking from the first couple of hits on (the original starts as soon as it is hurt)
	if self:Health() < self:GetMaxHealth() * 0.7 then self:CreateSmokeTrail() end
end

-- the gunship-shaped gibs carry the hacked skin on a hacked gunship
function ENT:SpawnGibs(pos, baseVel)
	for i = 1, self.GibCount do
		local model = self.GibModels[((i - 1) % #self.GibModels) + 1]
		local g = ents.Create("prop_physics")
		if IsValid(g) then
			g:SetModel(model)
			g:SetPos(pos + VectorRand() * 30)
			g:SetAngles(AngleRand())
			g:Spawn()
			local gm = self.GibMaterial or (self.Hacked and "models/gunship/gunship_hacked")
			if gm and string.find(model, "gunship_gibs", 1, true) then g:SetMaterial(gm) end
			g:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
			local gp = g:GetPhysicsObject()
			if IsValid(gp) then
				gp:Wake()
				gp:SetVelocity(baseVel * 0.4 + VectorRand():GetNormalized() * math.Rand(self.GibSpeedMin, self.GibSpeedMax))
				gp:AddAngleVelocity(VectorRand() * math.Rand(self.GibSpin * 0.3, self.GibSpin))
			end
			if math.random(1, 3) == 1 then g:Ignite(math.Rand(4, 8)) end
			SafeRemoveEntityDelayed(g, self.GibLifetime + math.Rand(-2, 2))
		end
	end
end

-- it never breaks apart on the spot: it falls first
function ENT:ShouldGib() return false end

-- dying: it keeps its momentum, burns, and blows up a few times on the way down
function ENT:StartDying(dmg)
	self.Belly = nil
	self.MissileBurst = nil
	self:CannonLoop(false)
	self:AbortBurst()
	self:SetNWFloat("GsChargeStart", 0)
	self.DeathStart = CurTime()
	self.DeathMax = math.Rand(3, 4)
	self.NextDeathBlast = CurTime() + 0.2
	if not self.Silent then self:EmitSound("NPC_CombineGunship.DyingSound", 100) end
	SB("StartDying")(self, dmg)
	self:CreateSmokeTrail(true)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:Wake()
		phys:EnableGravity(false)
		phys:AddAngleVelocity(Vector(math.Rand(-10, 10), math.Rand(-8, 8), math.Rand(-45, 45)))
	end
	-- carries on the way it was going, sinking
	local v = Vector(self.CurVel)
	v.z = math.min(v.z, -60)
	self.CurVel = v
end

-- falling: it spins and noses over, burns, throws off chunks and blows up a few times on the way down
function ENT:CrashThink(dt)
	local now = CurTime()
	if self.Gibbed then return end
	self:SpinBlades()
	self:ProcessContacts(dt)
	if self.PendingGib then self:Gib() return end
	local phys = self:GetPhysicsObject()
	if not IsValid(phys) then self:Gib() return end
	phys:Wake()
	local age = now - (self.DeathStart or now)

	-- the spin winds up, the nose drops and it rolls
	self.DeathSpin = self.DeathSpin or (math.random(0, 1) == 1 and 1 or -1)
	local av = phys:GetAngleVelocity()
	local wantYaw = self.DeathSpin * math.Clamp(60 + age * 90, 0, 360)
	phys:AddAngleVelocity(Vector(self.DeathSpin * 8 * dt, 20 * dt * math.min(age, 2), (wantYaw - av.z) * math.min(1, 1.5 * dt)))

	if now >= (self.NextDeathBlast or 0) then
		self.NextDeathBlast = now + math.Rand(0.3, 0.75)
		local mn, mx = self:OBBMins(), self:OBBMaxs()
		local p = self:LocalToWorld(Vector(math.Rand(mn.x, mx.x) * 0.7, math.Rand(mn.y, mx.y) * 0.5, math.Rand(mn.z, mx.z) * 0.5))
		local ed = EffectData()
		ed:SetOrigin(p) ed:SetScale(2) ed:SetMagnitude(2)
		util.Effect("Explosion", ed)
		local e2 = EffectData()
		e2:SetOrigin(p) e2:SetScale(2)
		util.Effect("HelicopterMegaBomb", e2)
		util.BlastDamage(self, self, p, 160, 100)
		self:EmitSound("NPC_CombineGunship.Explode", 95, math.random(90, 120))
		self:DumpMetal(VectorRand())
		util.ScreenShake(p, 6, 40, 0.6, 1500)
	end
	if now >= (self.NextDeathSpark or 0) then
		self.NextDeathSpark = now + 0.12
		local ed = EffectData()
		ed:SetOrigin(self:WorldSpaceCenter() + VectorRand() * 90)
		ed:SetMagnitude(2) ed:SetScale(2) ed:SetRadius(3)
		util.Effect("ElectricSpark", ed)
	end

	-- last resort: if anyone is in reach below, it steers its wreck into them
	if now >= (self.NextDeathScan or 0) then
		self.NextDeathScan = now + 0.25
		self.DeathVictim = nil
		local pos0 = self:WorldSpaceCenter()
		local best = 2600 * 2600
		for _, e in ipairs(ents.FindInSphere(pos0, 2600)) do
			if IsValid(e) and e ~= self and (e:IsNPC() or e:IsPlayer()) and e:Health() > 0 and self:IsValidTarget(e) then
				local c = e:WorldSpaceCenter()
				local d2 = pos0:DistToSqr(c)
				if d2 < best and c.z < pos0.z + 250 and util.TraceLine({ start = pos0, endpos = c, mask = MASK_SOLID_BRUSHONLY }).Fraction >= 0.99 then
					best = d2
					self.DeathVictim = e
				end
			end
		end
	end
	local victim = self.DeathVictim
	if IsValid(victim) and victim:Health() > 0 then
		local c = victim:WorldSpaceCenter()
		local pos0 = self:WorldSpaceCenter()
		local dir = (c - pos0):GetNormalized()
		local cv = self.CurVel
		local spd = math.max(cv:Length(), 600)
		self.CurVel = LerpVector(math.min(1, 3 * dt), cv, dir * spd)
		if pos0:Distance(c) < ((self.HullMaxs and self.HullMaxs:Length2D() or 150) + 80) then
			local dmg = DamageInfo()
			dmg:SetAttacker(self) dmg:SetInflictor(self)
			dmg:SetDamage(self.RamDamage * 1.5) dmg:SetDamageType(DMG_CRUSH)
			dmg:SetDamagePosition(c) dmg:SetDamageForce(dir * 60000)
			victim:TakeDamageInfo(dmg)
			self:Gib()
			return
		end
	end

	local v = self.CurVel
	v.x, v.y = v.x * (1 - 0.15 * dt), v.y * (1 - 0.15 * dt)
	v.z = v.z - (self.CrashGravity or 300) * dt
	self.CurVel = v
	self:LimitSpeed(1000, 1000)
	self:CrashEffects(dt)
	self:ApplyMotor(dt, phys)

	-- touched down (or been falling for 12 s): it finally comes apart
	local tr = util.TraceHull({ start = self:GetPos(), endpos = self:GetPos() - Vector(0, 0, 70), mins = self.HullMins * 0.7, maxs = self.HullMaxs * 0.7, mask = MASK_NPCSOLID_BRUSHONLY, filter = self })
	if tr.Hit or age > (self.DeathMax or 3.5) then self:Gib() end
end

function ENT:OnScannerDeath()
	local pos = self:WorldSpaceCenter()
	-- the crash: a big blast and a ring of secondary ones, scorched ground
	local ed = EffectData()
	ed:SetOrigin(pos) ed:SetScale(5) ed:SetMagnitude(5)
	util.Effect("Explosion", ed)
	local e2 = EffectData()
	e2:SetOrigin(pos) e2:SetScale(4)
	util.Effect("HelicopterMegaBomb", e2)
	for i = 1, 7 do
		timer.Simple(i * 0.12, function()
			local e = EffectData()
			e:SetOrigin(pos + VectorRand() * 160)
			e:SetScale(3) e:SetMagnitude(3)
			util.Effect("Explosion", e)
		end)
	end
	util.BlastDamage(self, self, pos, 420, 220)
	util.Decal("Scorch", pos + Vector(0, 0, 20), pos - Vector(0, 0, 80), self)
	self:StopSound("NPC_CombineGunship.DyingSound")
	self:EmitSound("NPC_CombineGunship.Explode", 110)
	sound.Play("ambient/explosions/explode_4.wav", pos, 130, 90)
	util.ScreenShake(pos, 20, 120, 2, 2500)
end
