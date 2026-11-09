--[[-------------------------------------------------------------------------
	sv_ground.lua  -  ground locomotion for ball-shaped / rolling SNPCs (Rollermine...)

	Set  ENT.Locomotion = "ground"  and the base does this for you:
	  * gravity stays ON (flyers have it off)
	  * FinishMovement runs FinishGround instead of the flight motor
	  * the AI steers by calling, from UpdateMovement:
	        self:SetRoll(dir, torqueFactor)   -- roll toward a horizontal direction (nil = stop)
	        self:GroundSteer(target, ignoreEnt) -> a point to roll toward (navmesh, trail, detours)
	        self:Hop(height)                  -- upward kick + random spin (Valve's CNPC_RollerMine::Hop)

	Rolling is Valve's CRollerController: a LOCAL ANGULAR ACCELERATION (RollAccel deg/s^2 times a
	torque factor) around the axis ground-normal x direction, so the ball really rolls and friction does
	the rest. A small counter-torque cancels sideways slip while turning.

	Ground navigation: if the map has a navmesh we run A* over it; without one (or when the straight line is
	clear anyway) we use hull-trace feelers, the enemy's breadcrumb trail and committed detours.
---------------------------------------------------------------------------]]

ENT.RollAccel    = 1200   -- Valve's m_flForwardSpeed: deg/s^2 of spin per unit of torque factor
ENT.MaxRollSpeed = 600    -- no more spin is added once the ball is this fast along the roll direction
ENT.BrakeRate    = 3      -- fraction of spin removed per second when told to stop
ENT.GroundRadius = nil    -- radius of the ball (nil = HullSize)
ENT.RollGain     = 6      -- how hard it corrects its velocity error (higher = snappier)
ENT.HopDelay     = 2      -- ROLLERMINE_HOP_DELAY

function ENT:InitGround()
	self.OnGround = false
	self.GroundNormal = Vector(0, 0, 1)
	self.NextGroundCheck = 0
	self.RollDir = nil
	self.RollFactor = 1
	self.GStuck = 0
	self.NextHop = 0
	self.GPath = nil
	self.GPathIdx = 1
	self.GPathGoal = nil
	self.NextGPath = 0
end

function ENT:GetGroundRadius() return self.GroundRadius or self.HullSize end

function ENT:SetRoll(dir, factor, speed)
	if dir and dir:LengthSqr() > 0.0001 then
		self.RollDir = dir:GetNormalized()
		self.RollFactor = factor or 1
		self.RollSpeed = speed
	else
		self.RollDir = nil
	end
end

function ENT:UpdateGround()
	local now = CurTime()
	if now < self.NextGroundCheck then return end
	self.NextGroundCheck = now + 0.05
	local pos = self:GetPos()
	local r = self:GetGroundRadius()
	local tr = util.TraceLine({
		start = pos, endpos = pos - Vector(0, 0, r + 10),
		filter = function(e) return e ~= self and not e:IsPlayer() and not e:IsNPC() end, mask = MASK_SOLID,
	})
	if tr.Hit then self.GroundGrace = now + 0.2 end
	self.OnGround = tr.Hit or now < (self.GroundGrace or 0) -- a one-off missed ground trace must not stop the drive
	self.GroundNormal = tr.Hit and tr.HitNormal or Vector(0, 0, 1)
	if tr.Hit and self.GroundNormal.z < 0.3 then self.OnGround = false end -- walls do not count
end

-- Upward kick plus a random spin (Valve applies height*mass as an impulse = +height units/s).
function ENT:Hop(height, force)
	local now = CurTime()
	if not force and now < self.NextHop then return end
	self.NextHop = now + self.HopDelay
	self.HopUntil = now + 0.6
	local phys = self:GetPhysicsObject()
	if not IsValid(phys) then return end
	phys:Wake()
	phys:SetVelocity(phys:GetVelocity() + Vector(0, 0, height))
	phys:AddAngleVelocity(Vector(math.Rand(-400, 400), math.Rand(-400, 400), math.Rand(-400, 400)))
end

--=========================================================================
-- Per-tick motor
--=========================================================================

function ENT:FinishGround(dt)
	self:ProcessContacts(dt)

	local phys = self:GetPhysicsObject()
	if not IsValid(phys) or self:IsFlightDisabled() then return end
	phys:Wake()
	if phys:IsAsleep() then phys:Wake() end
	self:UpdateGround()
	if GetConVar("physsnpc_debug"):GetBool() and self.RollDir and not self.Held then
		local hs = Vector(phys:GetVelocity().x, phys:GetVelocity().y, 0):Length()
		if hs < 15 then
			self.DbgStall = (self.DbgStall or 0) + dt
			if self.DbgStall > 0.5 and CurTime() > (self.DbgNext or 0) then
				self.DbgNext = CurTime() + 1
				print(("[physsnpc] #%d rolling but stopped: onGround=%s stalled=%s hold=%s asleep=%s motion=%s spin=%.0f"):format(
					self:EntIndex(), tostring(self.OnGround), tostring(self:IsStalled()), tostring(self.GroundHold),
					tostring(phys:IsAsleep()), tostring(phys:IsMotionEnabled()), phys:GetAngleVelocity():Length()))
			end
		else
			self.DbgStall = 0
		end
	end
	-- fast balls bounce off every little bump: cap the speed away from the ground (not right after a hop)
	if self.OnGround and CurTime() > (self.HopUntil or 0) and not self:IsFlightDisabled() then
		local v = phys:GetVelocity()
		local vn = v:Dot(self.GroundNormal)
		if vn > 110 then phys:SetVelocity(v - self.GroundNormal * (vn - 110) * 0.7) end
	end
	if self.GroundHold then return end -- (variants that drive the spin themselves, e.g. the Sonic Rollermine's charge)

	local dir = self.RollDir
	local vel = phys:GetVelocity()

	if dir and self.OnGround and not self:IsStalled() then
		local n = self.GroundNormal
		local d = dir - n * dir:Dot(n)
		if d:LengthSqr() > 0.0001 then
			d:Normalize()
			-- steer by VELOCITY ERROR: the ball is spun toward (wanted velocity - current velocity), so it turns
			-- on the spot, kills sideways slip, and brakes by itself when it is going faster than wanted
			local r = self:GetGroundRadius()
			local hv = vel - n * vel:Dot(n)
			local e = d * (self.RollSpeed or self.MaxRollSpeed) - hv
			local el = e:Length()
			if el > 2 then
				local maxAdd = self.RollAccel * self.RollFactor * dt          -- deg/s of spin per tick at most
				local add = math.min(maxAdd, el / r * 57.2958 * dt * self.RollGain)
				local axis = n:Cross(e / el)
				phys:AddAngleVelocity(phys:WorldToLocalVector(axis * add))
			end
		end
	elseif not dir and self.OnGround then
		phys:SetAngleVelocity(phys:GetAngleVelocity() * math.max(0, 1 - self.BrakeRate * dt))
	end

	-- trying to roll but going nowhere: hop and try another way
	if dir and self.OnGround and Vector(vel.x, vel.y, 0):Length() < 40 then
		self.GStuck = self.GStuck + dt
	else
		self.GStuck = 0
	end
	if self.GStuck > 1 then
		self.GStuck = 0
		self:Hop(150, true)
		self.GPath = nil
		self.SteerCache = nil
		self.Detour = (Angle(0, math.Rand(0, 360), 0)):Forward()
		self.ForceDetourUntil = CurTime() + 0.8
	end
end

--=========================================================================
-- Ground navigation
--=========================================================================

-- Is the way from `from` to `to` free for a ball rolling along the ground? Returns clear, fraction.
function ENT:GroundClear(from, to)
	local r = self:GetGroundRadius()
	local h = Vector(r * 0.7, r * 0.7, r * 0.35)
	local tr = util.TraceHull({
		start = from, endpos = to, mins = -h, maxs = h,
		filter = self, mask = MASK_NPCSOLID_BRUSHONLY,
	})
	return not (tr.Hit or tr.StartSolid), tr.StartSolid and 0 or tr.Fraction
end

-- A* over the map's navmesh. Returns a list of positions, or nil.
local ASTAR_TICK
local function AStar(startArea, goalArea)
	if startArea == goalArea then return { goalArea:GetCenter() } end
	local open, closed, came, g, f = {}, {}, {}, {}, {}
	local sid = startArea:GetID()
	open[sid] = startArea
	g[sid] = 0
	f[sid] = startArea:GetCenter():Distance(goalArea:GetCenter())
	local steps = 0
	while next(open) do
		steps = steps + 1
		if steps > 300 then return nil end
		local cur, curF, curId
		for id, a in pairs(open) do
			if not curF or f[id] < curF then cur, curF, curId = a, f[id], id end
		end
		if cur == goalArea then
			local list = {}
			local a = cur
			while a do
				table.insert(list, 1, a:GetCenter())
				a = came[a:GetID()]
			end
			return list
		end
		open[curId] = nil
		closed[curId] = true
		for _, nb in ipairs(cur:GetAdjacentAreas()) do
			local nid = nb:GetID()
			if not closed[nid] and not nb:IsBlocked(-2, false) then
				local ng = g[curId] + cur:GetCenter():Distance(nb:GetCenter())
				if not g[nid] or ng < g[nid] then
					came[nid] = cur
					g[nid] = ng
					f[nid] = ng + nb:GetCenter():Distance(goalArea:GetCenter())
					open[nid] = nb
				end
			end
		end
	end
	return nil
end

function ENT:NavmeshWaypoint(target)
	if not (navmesh and navmesh.GetNavAreaCount and navmesh.GetNavAreaCount() > 0) then return nil end
	local now = CurTime()
	local pos = self:GetPos()

	local stale = not self.GPath or not self.GPathGoal or self.GPathGoal:DistToSqr(target) > 150 * 150
	if stale and now >= self.NextGPath and (ASTAR_TICK or 0) ~= now then
		ASTAR_TICK = now -- one path search per tick for everybody (no server hitches with many rollermines)
		self.NextGPath = now + 1
		local a = navmesh.GetNearestNavArea(pos, false, 250, false, true)
		local b = navmesh.GetNearestNavArea(target, false, 350, false, true)
		self.GPath, self.GPathIdx, self.GPathGoal = nil, 1, Vector(target)
		if a and b then
			local p = AStar(a, b)
			if p then
				p[#p] = Vector(target.x, target.y, p[#p].z)
				self.GPath = p
			end
		end
	end

	local path = self.GPath
	if not path then return nil end
	local i = self.GPathIdx
	while i <= #path do
		local w = path[i]
		local dx, dy = w.x - pos.x, w.y - pos.y
		if dx * dx + dy * dy < 55 * 55 then i = i + 1 else break end
	end
	self.GPathIdx = i
	return path[i]
end

-- Newest breadcrumb of the enemy's trail that we can roll to in a straight line.
function ENT:GroundTrailWaypoint()
	local tr, pos = self.Trail, self:GetPos()
	for i = #tr, 1, -1 do
		local c = tr[i]
		local flat = Vector(c.x, c.y, pos.z)
		if self:GroundClear(pos, flat) then
			if pos:DistToSqr(flat) < 70 * 70 then
				for _ = 1, i do table.remove(tr, 1) end
				return nil
			end
			return flat
		end
	end
	return nil
end

local GYAWS = { 0, 30, -30, 60, -60, 90, -90, 130, -130, 180 }

--[[ GroundSteer(target [, ignore]) -> a point to roll toward instead of `target`:
	straight line clear -> target; else navmesh path; else the enemy's trail; else the best committed detour. ]]
function ENT:GroundSteer(target, ignore)
	local now = CurTime()
	local pos = self:GetPos()

	if self.Detour and now < self.ForceDetourUntil then return pos + self.Detour * 200 end

	local to = Vector(target.x - pos.x, target.y - pos.y, 0)
	local dist = to:Length()
	if dist < 1 then return target end
	local dir = to / dist
	local look = math.min(dist, 300)

	if self:GroundClear(pos, pos + dir * look) then
		self.GPath = nil
		self.Detour = nil
		return target
	end

	local nav = self:NavmeshWaypoint(target)
	if nav then return nav end

	if IsValid(ignore) and ignore == self:GetFoe() and self.Trail and #self.Trail > 0 then
		if now >= self.NextWaypoint then
			self.NextWaypoint = now + 0.2
			self.Waypoint = self:GroundTrailWaypoint()
		end
		if self.Waypoint then return self.Waypoint end
	end

	if self.Detour and now < self.DetourUntil and self:GroundClear(pos, pos + self.Detour * look) then
		return pos + self.Detour * 200
	end

	local base = dir:Angle().y
	local best, bestScore
	for _, yo in ipairs(GYAWS) do
		local d = Angle(0, base + yo, 0):Forward()
		local _, frac = self:GroundClear(pos, pos + d * look)
		local score = frac * 2 + d:Dot(dir)
		if frac > 0.9 then
			local p1 = pos + d * look
			local toT = Vector(target.x - p1.x, target.y - p1.y, 0)
			local l = toT:Length()
			if l > 1 and self:GroundClear(p1, p1 + toT / l * math.min(l, look)) then score = score + 1.5 end
		end
		if not bestScore or score > bestScore then best, bestScore = d, score end
	end
	self.Detour = best
	self.DetourUntil = now + 0.5
	return pos + best * 200
end
