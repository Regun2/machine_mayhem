--[[-------------------------------------------------------------------------
	sv_flight.lua  -  physics flight model

	AI code never moves the entity directly. It edits self.CurVel (the DESIRED
	velocity) via MoveToTarget / Decelerate / ForceVel. FinishMovement() then
	limits it and the physics "motor" nudges the real VPhysics object toward it,
	so collisions, knockback and tumbling all come from the physics engine.

	The steering maths (MoveInDirection, decay, banking, speed limits, noise)
	is a direct port of Valve's CAI_BaseFlyingBot as used by npc_manhack.
---------------------------------------------------------------------------]]

local THINK_REF = 0.1 -- Valve's AI think period; per-think constants are scaled by dt / THINK_REF

-- hull = the PhysBox: the traces' hull, the engine's collision bounds and the surrounding bounds
function ENT:ApplyBoxHull()
	local mn, mx = self.PhysBox[1], self.PhysBox[2]
	self.HullMins, self.HullMaxs = Vector(mn), Vector(mx)
	self.HullSize = math.max(-mn.x, -mn.y, -mn.z, mx.x, mx.y, mx.z)
	-- the engine multiplies collision bounds by the model scale: divide it out so they come out as asked
	local sc = self:GetModelScale() or 1
	if sc <= 0 then sc = 1 end
	self:SetCollisionBounds(mn / sc, mx / sc)
	self:SetSurroundingBounds(mn / sc, mx / sc)
	self:NetHull()
end

-- (debug) publish the hull to clients so physsnpc_debug_hull 1 can draw it
function ENT:NetHull()
	self:SetNWVector("PhysHullMins", self.HullMins)
	self:SetNWVector("PhysHullMaxs", self.HullMaxs)
end

-- aim at an NPC and run physsnpc_hull_dump: prints what the server thinks its hull / bounds / physics are
concommand.Add("physsnpc_hull_dump", function(ply)
	if not IsValid(ply) then return end
	local e = ply:GetEyeTrace().Entity
	if not IsValid(e) or not e.IsPhysicsSNPC then ply:PrintMessage(HUD_PRINTCONSOLE, "[physsnpc] aim at one of the NPCs first\n") return end
	local function P(...) ply:PrintMessage(HUD_PRINTCONSOLE, string.format(...) .. "\n") end
	local cmn, cmx = e:GetCollisionBounds()
	local smn, smx = e:GetSurroundingBounds()
	local phys = e:GetPhysicsObject()
	local pmn, pmx
	if IsValid(phys) then pmn, pmx = phys:GetAABB() end
	P("[physsnpc] %s #%d", e:GetClass(), e:EntIndex())
	P("  PhysBox        = %s", e.PhysBox and (tostring(e.PhysBox[1]) .. " .. " .. tostring(e.PhysBox[2])) or "none")
	P("  HullMins/Maxs  = %s .. %s  (HullSize %s)", tostring(e.HullMins), tostring(e.HullMaxs), tostring(e.HullSize))
	P("  CollisionBounds= %s .. %s", tostring(cmn), tostring(cmx))
	P("  Surrounding    = %s .. %s", tostring(smn), tostring(smx))
	P("  Physics AABB   = %s .. %s", tostring(pmn), tostring(pmx))
	P("  solid=%d  solidflags=%d  movetype=%d  group=%d", e:GetSolid(), e:GetSolidFlags(), e:GetMoveType(), e:GetCollisionGroup())
end)

function ENT:InitPhysicsFlight()
	local h = self.HullSize
	self.HullMins = Vector(-h, -h, -h)
	self.HullMaxs = Vector(h, h, h)

	local usedModelPhys, phys
	if self.PhysBox then
		-- a box of our own as the collision body (instead of the model's): the world, players and the
		-- physgun all use it (custom collisions make traces hit the box too, not the model's hitboxes)
		local mn, mx = self.PhysBox[1], self.PhysBox[2]
		local v = {
			Vector(mn.x, mn.y, mn.z), Vector(mx.x, mn.y, mn.z), Vector(mx.x, mx.y, mn.z), Vector(mn.x, mx.y, mn.z),
			Vector(mn.x, mn.y, mx.z), Vector(mx.x, mn.y, mx.z), Vector(mx.x, mx.y, mx.z), Vector(mn.x, mx.y, mx.z),
		}
		usedModelPhys = self:PhysicsInitConvex(v)
		phys = self:GetPhysicsObject()
		if usedModelPhys and IsValid(phys) then
			self:SetSolid(SOLID_VPHYSICS)
			self:SetCollisionGroup(COLLISION_GROUP_NONE)
			self:EnableCustomCollisions(true)
			-- the hull (traces, hit box, grabbing) is the same box as the collision body
			self:ApplyBoxHull()
			-- the engine resets an NPC's bounds a moment after spawning (hull type): apply them again a few times
			for _, t in ipairs({ 0, 0.1, 0.4, 1 }) do
				timer.Simple(t, function() if IsValid(self) then self:ApplyBoxHull() end end)
			end
		end
	elseif self.PhysSphereRadius then
		-- bigger / simpler collision than the model's own: a sphere of this radius
		self:PhysicsInitSphere(self.PhysSphereRadius, self.PhysMaterial or "metal")
		phys = self:GetPhysicsObject()
		usedModelPhys = IsValid(phys)
	else
		usedModelPhys = self:PhysicsInit(SOLID_VPHYSICS)
		phys = self:GetPhysicsObject()
	end
	if not usedModelPhys or not IsValid(phys) then
		-- The model has no collision mesh, fall back to a sphere.
		self:PhysicsInitSphere(h, self.PhysMaterial or "metal")
		phys = self:GetPhysicsObject()
	elseif not self.PhysSphereRadius and not self.PhysBox then
		self:SetSolid(SOLID_VPHYSICS)
	end
	self:SetMoveType(MOVETYPE_VPHYSICS)

	if IsValid(phys) then
		if self.PhysMaterial then phys:SetMaterial(self.PhysMaterial) end
		if self.PhysMass and self.PhysMass > 0 then phys:SetMass(self.PhysMass) end
		phys:SetDamping(self.LinearDamping, self.AngularDamping)
		phys:EnableGravity(self.Locomotion == "ground")
		phys:Wake()
	end
	self:InitGround()

	self.CurVel        = Vector(0, 0, 0) -- desired velocity
	self.ForceVel      = Vector(0, 0, 0) -- one-shot velocity added next tick (knockback, loiter pulses)
	self.BankTarget    = Vector(0, 0, 0) -- x = pitch, z = roll (degrees)
	self.BankCur       = Vector(0, 0, 0)
	self.NoiseMod      = Vector(0, 0, math.Rand(1.7, 2.3)) -- bob up/down like Valve's default
	self.CurNoiseScale = self.NoiseScale
	self.EngineStallTime = 0
	self.EnginePowerScale = self:GetMaxEnginePower()
	self.MotorScale    = 1
	self.WantYaw       = self:GetAngles().y
	self.FaceYawTarget = nil
	self.PrevBasis     = nil
	self.Detour        = nil   -- committed direction around an obstacle
	self.DetourUntil   = 0
	self.ForceDetourUntil = 0
	self.StuckTime     = 0
	self.SurfacePush   = Vector(0, 0, 0)
	self.TightUntil    = 0
	self.Trail         = {}
	self.Waypoint      = nil
	self.NextWaypoint  = 0
	self.NextCrumb     = 0
	self.NextAvoid     = CurTime() + math.Rand(0, 0.07)
	self.NextGround    = CurTime() + math.Rand(0, 0.08)
	self.GroundFrac    = 1
	self.AvoidPush     = nil
	self.SteerCache    = nil
	self:NetHull()
end

--=========================================================================
-- Velocity helpers (direct ports)
--=========================================================================

function ENT:GetCurrentVelocity() return self.CurVel end
function ENT:SetCurrentVelocity(v) self.CurVel = v end
function ENT:IsStalled() return CurTime() < self.EngineStallTime end

-- Add a force that is meant to be applied every tick (scaled so it does not depend on tickrate).
function ENT:AddContinuousForce(vec, dt)
	self.ForceVel = self.ForceVel + vec * (dt / THINK_REF)
end

function ENT:MoveInDirection(dt, dir, accelXY, accelZ, decay)
	local d = decay ^ dt
	accelXY = accelXY * dt
	accelZ  = accelZ * dt
	local v = self.CurVel
	v.x = d * v.x + accelXY * dir.x
	v.y = d * v.y + accelXY * dir.y
	v.z = d * v.z + accelZ * dir.z
end

-- rate = how fast velocity dies away, per second (9.5 ~ stops in a fraction of a second)
function ENT:Decelerate(dt, rate)
	self.CurVel = self.CurVel * math.exp(-rate * dt)
	self.BankTarget = Vector(0, 0, 0)
end

function ENT:AddNoise(dt, scale)
	if scale <= 0 then return end
	local k = dt / THINK_REF
	local t = CurTime()
	local m = self.NoiseMod
	local v = self.CurVel
	if m.x ~= 0 then v.x = v.x + scale * math.sin(m.x * t + m.x) * k end
	if m.y ~= 0 then v.y = v.y + scale * math.sin(m.y * t + m.y) * k end
	if m.z ~= 0 then v.z = v.z + scale * math.sin(m.z * t + m.z) * k end
end

function ENT:LimitSpeed(zLimit, maxSpeed)
	local v = self.CurVel
	local speed = v:Length()
	if maxSpeed and maxSpeed > 0 and speed > maxSpeed then
		v = v * (maxSpeed / speed)
	end
	if zLimit and zLimit > 0 then
		v.z = math.Clamp(v.z, -zLimit, zLimit)
	end
	self.CurVel = v
end

-- Keeps the SNPC from scraping the floor (Valve's MaintainGroundHeight).
function ENT:MaintainGroundHeight(dt)
	local zspeed = self.CurVel.z
	if zspeed > 32 then return end
	local now = CurTime()
	if now >= self.NextGround then
		self.NextGround = now + 0.08 * self:LoadScale()
		local pos = self:GetPos()
		local tr = util.TraceHull({
			start = pos, endpos = pos - Vector(0, 0, 52),
			mins = self.HullMins, maxs = self.HullMaxs,
			filter = self, mask = MASK_NPCSOLID_BRUSHONLY,
		})
		self.GroundFrac = tr.Fraction
	end
	if self.GroundFrac ~= 1 then
		local adj = math.max(16, -zspeed * 0.5)
		self:AddContinuousForce(Vector(0, 0, adj * (1 - self.GroundFrac)), dt)
	end
end

--[[-------------------------------------------------------------------------
	MoveToTarget(dt, targetPos, burstDir, burstZAccel)
	Port of CNPC_Manhack::MoveToTarget. Steers CurVel toward targetPos.
	If burstDir is given the SNPC goes straight along that direction instead
	(manhack "charge").
---------------------------------------------------------------------------]]
function ENT:MoveToTarget(dt, target, burstDir, burstZAccel)
	if self:IsStalled() or self.Crashing then return end

	local pos = self:GetPos()
	local dir, dist, accel
	local zaccel = self.AccelVertical

	if burstDir then
		dir = burstDir
		dist = math.huge
		accel = self.BurstAccel or 400
		zaccel = math.min(500, burstZAccel or 500)
	else
		dir = target - pos
		dist = dir:Length()
		if dist > 0.001 then dir:Normalize() end
		local curDir = self.CurVel:GetNormalized()
		accel = (dir:Dot(curDir) > 0.25) and self.AccelAligned or self.AccelTurning
	end

	-- do not overshoot the goal within one step (Valve thinks at ~10 Hz, so never use a smaller
	-- reference step than that or steering becomes far more aggressive at high tickrates)
	local maxStep = dist / math.max(dt, THINK_REF)
	if accel > maxStep then accel = maxStep end
	if zaccel > maxStep then zaccel = maxStep end

	accel  = accel * self.EnginePowerScale
	zaccel = zaccel * self.EnginePowerScale

	self:MoveInDirection(dt, dir, accel, zaccel, self.VelDecay)

	-- banking targets (relative to the body's current heading)
	local fwd, right = self:GetForward(), self:GetRight()
	self.BankTarget = Vector(self.BankAngle * dir:Dot(fwd), 0, self.BankAngle * dir:Dot(right))
end

--=========================================================================
-- Navigation (no navmesh for flyers, so: feelers + committed detours + wall repulsion)
--=========================================================================

ENT.AvoidLook     = 320   -- how far ahead the path is checked
ENT.AvoidRange    = 40    -- walls / ceilings closer than this push us away (at full speed)
ENT.AvoidStrength = 450   -- that push, in units/s^2 at point blank

-- Is the straight line from `from` (default: our position) along `dir` free of world geometry
-- for `len` units? In tight spaces (vents...) a slimmer hull is used so we can squeeze through.
function ENT:IsPathClear(dir, len, from)
	local pos = from or self:GetPos()
	local h = self.HullMaxs * ((self.TightUntil or 0) > CurTime() and 0.45 or 0.85)
	local tr = util.TraceHull({
		start = pos, endpos = pos + dir * len,
		mins = -h, maxs = h,
		mask = MASK_NPCSOLID_BRUSHONLY, filter = self,
	})
	return not (tr.Hit or tr.StartSolid), tr.StartSolid and 0 or tr.Fraction
end

function ENT:IsPathClearTo(point)
	local to = point - self:GetPos()
	local d = to:Length()
	if d < 1 then return true end
	return (self:IsPathClear(to / d, d))
end

--=========================================================================
-- Breadcrumb trail: the enemy walked somewhere we can follow. When the straight line to the enemy
-- is blocked (inside a building, around a corner...) we fly to the newest crumb we can reach in a
-- straight line, which leads us through the same doors and corridors instead of over the roof.
--=========================================================================

function ENT:RecordTrail(foe)
	local now = CurTime()
	if now < (self.NextCrumb or 0) then return end
	self.NextCrumb = now + 0.2
	local p = foe:GetPos()
	p.z = p.z + math.Clamp(foe:OBBMaxs().z * 0.6, 16, 48)
	local tr = self.Trail
	local last = tr[#tr]
	if last and last:DistToSqr(p) < 70 * 70 then return end
	tr[#tr + 1] = p
	if #tr > 48 then table.remove(tr, 1) end
end

function ENT:FindTrailWaypoint()
	local tr, pos = self.Trail, self:GetPos()
	for i = #tr, 1, -1 do
		local c = tr[i]
		if self:IsPathClearTo(c) then
			if pos:DistToSqr(c) < 70 * 70 then
				for _ = 1, i do table.remove(tr, 1) end -- reached it (and everything before it)
				return nil
			end
			return c
		end
	end
	return nil
end

local PITCHES = { 0, -35, -70, 35 }          -- negative = up
local YAWS    = { 0, 40, -40, 80, -80, 130, -130, 180 }

--[[-------------------------------------------------------------------------
	SteerAround(target [, ignore]) -> a point to steer toward instead of `target`
	  1. straight line clear -> target
	  2. chasing the enemy: follow its breadcrumb trail
	  3. otherwise sample directions around the blocked line, score them with a 2-step lookahead
	     (can we see the target again from where that direction leads?), and COMMIT to the winner
	     for a short time so we do not jitter in front of the obstacle.
---------------------------------------------------------------------------]]
function ENT:SteerAroundRaw(target, ignore)
	local now = CurTime()
	local pos = self:GetPos()

	-- recently stuck: follow the escape direction first
	if self.Detour and now < self.ForceDetourUntil then return pos + self.Detour * 240 end

	local to = target - pos
	local dist = to:Length()
	if dist < 1 then return target end
	local dir = to / dist
	local look = math.min(dist, self.AvoidLook)

	if self:IsPathClear(dir, look) then
		self.Detour = nil
		self.Waypoint = nil
		return target
	end

	-- follow the enemy's trail
	if IsValid(ignore) and ignore == self:GetFoe() and #self.Trail > 0 then
		if now >= self.NextWaypoint then
			self.NextWaypoint = now + 0.2
			self.Waypoint = self:FindTrailWaypoint()
		end
		if self.Waypoint then return self.Waypoint end
	end

	-- keep the detour we already chose while it is still clear
	if self.Detour and now < self.DetourUntil and self:IsPathClear(self.Detour, look) then
		return pos + self.Detour * 240
	end

	local base = dir:Angle()
	local best, bestScore
	for _, po in ipairs(PITCHES) do
		for _, yo in ipairs(YAWS) do
			local d = Angle(base.p + po, base.y + yo, 0):Forward()
			local _, frac = self:IsPathClear(d, look)
			local score = frac * 2 + d:Dot(dir) - math.abs(d.z) * 0.15
			if frac > 0.9 then
				-- after this step, can we head for the target again?
				local p1 = pos + d * look
				local toT = target - p1
				local l = toT:Length()
				if l > 1 and self:IsPathClear(toT / l, math.min(l, look), p1) then score = score + 1.5 end
			end
			-- do not climb away from a target that is at our level or below (that is how you end up on the roof)
			if d.z > 0.2 and target.z < pos.z + 30 then score = score - 1.5 * d.z end
			if not bestScore or score > bestScore then best, bestScore = d, score end
		end
	end

	self.Detour = best
	self.DetourUntil = now + 0.5
	return pos + best * 240
end

-- Steering is re-planned a few times per second, not every tick (the plan stays valid for a moment).
function ENT:SteerAround(target, ignore)
	local now = CurTime()
	local c = self.SteerCache
	if c and now < c.exp and c.ignore == ignore and c.target:DistToSqr(target) < 80 * 80 then
		if c.clear then return target end
		return c.point
	end
	local p = self:SteerAroundRaw(target, ignore)
	if now < self.ForceDetourUntil then
		self.SteerCache = nil
	else
		self.SteerCache = {
			exp = now + 0.1 * self:LoadScale(), ignore = ignore, target = Vector(target),
			clear = (p == target), point = p,
		}
	end
	return p
end

-- Push away from nearby walls and the ceiling (the floor is MaintainGroundHeight's job).
-- Gentle when slow and switched almost off in tight spaces, so we can go through vents.
local AVOID_DIRS = {
	{ Vector(1, 0, 0), 1 }, { Vector(-1, 0, 0), 1 }, { Vector(0, 1, 0), 2 }, { Vector(0, -1, 0), 2 },
	{ Vector(0, 0, 1), 3 }, { Vector(0, 0, -1), 3 },
}
function ENT:AvoidSurfaces(dt)
	local now = CurTime()
	local scale = math.Clamp(self.CurVel:Length() / 300, 0.25, 1)

	if now >= self.NextAvoid then
		self.NextAvoid = now + 0.07 * self:LoadScale()
		local pos = self:GetPos()
		local range = self.HullSize + self.AvoidRange * scale
		local push = Vector(0, 0, 0)
		local axisHits = { 0, 0, 0 }
		for i, e in ipairs(AVOID_DIRS) do
			local d, axis = e[1], e[2]
			local tr = util.TraceLine({ start = pos, endpos = pos + d * range, mask = MASK_NPCSOLID_BRUSHONLY, filter = self })
			if tr.Hit then
				axisHits[axis] = axisHits[axis] + 1
				if i ~= 6 then push = push - d * (1 - tr.Fraction) end -- (floor: only counts for "tight")
			end
		end
		-- walls on both sides of the same axis: we are in a corridor / vent
		for axis = 1, 3 do
			if axisHits[axis] >= 2 then self.TightUntil = now + 0.5 end
		end
		self.AvoidPush = push
		self.SurfacePush = push
	end

	local push = self.AvoidPush
	if push and push:LengthSqr() > 0 then
		local tight = (self.TightUntil or 0) > now
		self.CurVel = self.CurVel + push * (self.AvoidStrength * scale * (tight and 0.1 or 1) * dt)
	end
end

-- Wants to move but is not getting anywhere (wedged against geometry): back out sideways/up.
function ENT:CheckStuck(dt, phys)
	local want = self.CurVel:Length()
	if want > 150 and phys:GetVelocity():Length() < want * 0.25 and not self:IsStalled() then
		self.StuckTime = self.StuckTime + dt
	else
		self.StuckTime = 0
	end
	if self.StuckTime < 0.5 then return end

	local now = CurTime()
	local n = self.SurfacePush
	if n:LengthSqr() < 0.01 then n = VectorRand() end
	n = n:GetNormalized()
	self.Detour = (n + Vector(0, 0, 0.4) + VectorRand() * 0.3):GetNormalized()
	self.DetourUntil = now + 0.8
	self.ForceDetourUntil = now + 0.6
	self.CurVel = self.Detour * 160
	self.StuckTime = 0
	self.SteerCache = nil
end

--=========================================================================
-- Per-tick pipeline end: apply forced velocity, noise, limits, motor
--=========================================================================

function ENT:FinishMovement(dt)
	if self.Locomotion == "ground" then return self:FinishGround(dt) end
	if self.Locomotion == "static" then self.Contacts = {} return end -- turrets: no flight / rolling motor
	self:ProcessContacts(dt)

	local phys = self:GetPhysicsObject()
	if not IsValid(phys) or self:IsFlightDisabled() then return end
	phys:Wake()

	-- engine power recovers after being reduced (water etc.)
	local maxp = self:GetMaxEnginePower()
	if self.EnginePowerScale < maxp and self:WaterLevel() == 0 then
		self.EnginePowerScale = math.min(maxp, self.EnginePowerScale + 0.05 * (dt / THINK_REF))
	end

	-- forced velocity + noise + limits
	self.CurVel = self.CurVel + self.ForceVel
	self.ForceVel = Vector(0, 0, 0)
	self:AvoidSurfaces(dt)
	self:CheckStuck(dt, phys)
	self:AddNoise(dt, self.CurNoiseScale)
	self:LimitSpeed(self.MaxVertSpeed, self:GetMaxSpeed())

	if self:WaterLevel() > 0 then
		-- may lift out of water, never dive deeper
		self.EnginePowerScale = math.min(self.EnginePowerScale, 0.75)
		self.CurVel.z = math.max(self.CurVel.z, 0)
	end

	-- yaw target: face the enemy, otherwise face the way we are flying
	local chase = self:GetChasePos()
	if chase then
		self.FaceYawTarget = (chase - self:GetPos()):Angle().y
	elseif self.CurVel:Length2D() > 30 then
		self.FaceYawTarget = self.CurVel:Angle().y
	end
	if self.FaceYawTarget then
		self.WantYaw = math.ApproachAngle(self.WantYaw, self.FaceYawTarget, self.TurnRate * dt)
	end

	self:BladeTrace(dt) -- sv_combat.lua: slices things in the flight path

	if self:IsStalled() then
		-- engine out: only vertical control, body tumbles on its own
		phys:AddAngleVelocity(VectorRand() * 300 * dt)
		self.PrevBasis = nil
	else
		self.BankCur = self.BankCur + (self.BankTarget - self.BankCur) * math.min(1, 8 * dt)
		self:ApplyOrientation(dt, phys)
	end
	self:ApplyMotor(dt, phys)
end

-- Pushes the real physics velocity toward CurVel.
function ENT:ApplyMotor(dt, phys)
	local vel = phys:GetVelocity()
	local dv = self.CurVel - vel

	if self:IsStalled() then
		dv.x, dv.y = 0, 0
	end

	local maxdv = self.MotorAccel * dt * math.max(0.15, self.MotorScale)
	local len = dv:Length()
	if len > maxdv then dv = dv * (maxdv / len) end

	phys:AddVelocity(dv)
end

--[[-------------------------------------------------------------------------
	Orientation controller.
	Error is computed as a world-space rotation vector between the current and
	the desired basis; angular velocity is estimated from the previous tick so
	we never depend on which frame GetAngleVelocity uses. The correction is
	converted into the object's local frame for AddAngleVelocity.
---------------------------------------------------------------------------]]
function ENT:ApplyOrientation(dt, phys)
	local cur = phys:GetAngles()
	local des = Angle(self.BankCur.x, self.WantYaw, self.BankCur.z)

	local f, r, u = cur:Forward(), cur:Right(), cur:Up()
	local fd, rd, ud = des:Forward(), des:Right(), des:Up()

	local err = (f:Cross(fd) + r:Cross(rd) + u:Cross(ud)) * 0.5 -- radians

	local w = Vector(0, 0, 0) -- current angular velocity, rad/s, world
	local pb = self.PrevBasis
	if pb then
		w = (pb[1]:Cross(f) + pb[2]:Cross(r) + pb[3]:Cross(u)) * (0.5 / dt)
	end
	self.PrevBasis = { f, r, u }

	local want = err * self.OrientGain
	local dw = (want - w) * math.min(1, self.OrientDamping * dt)

	phys:AddAngleVelocity(phys:WorldToLocalVector(dw * 57.29578))
end

--=========================================================================
-- Bump: called on physics contact with something we do not slice
-- (port of CNPC_Manhack::Bump's velocity deflection)
--=========================================================================
function ENT:DeflectVelocity(normal, speed)
	local n = Vector(normal)
	if self.Crashing then n.z = math.min(n.z, 0) end
	self.CurVel = self.CurVel + n * speed * 0.5
end

--=========================================================================
-- Dying flight: accelerate erratically until something is hit
--=========================================================================
function ENT:CrashThink(dt)
	if self.Gibbed then return end
	self:ProcessContacts(dt)
	if self.PendingGib then self:CrashEnd() return end

	local phys = self:GetPhysicsObject()
	if not IsValid(phys) then self:CrashEnd() return end

	if CurTime() > (self.CrashStart or 0) + self.CrashFailsafe then
		self:CrashEnd()
		return
	end

	phys:Wake()
	local v = self.CurVel
	v = v + v * (1.5 * dt)         -- "accelerate faster and faster when dying"
	v.z = v.z - self.CrashGravity * dt -- no lift any more: fall
	v = v + self.ForceVel
	self.ForceVel = Vector(0, 0, 0)
	self.CurVel = v
	self:AddNoise(dt, 3)
	self:LimitSpeed(0, self.MaxSpeed * 2)

	phys:AddAngleVelocity(VectorRand() * 600 * dt)
	self:CrashEffects(dt) -- sv_combat.lua (sparks)

	self:BladeTrace(dt)
	self:ApplyMotor(dt, phys)
end
