--[[-------------------------------------------------------------------------
	sv_ai.lua  -  target acquisition + lightweight "squad" helpers

	The engine still runs the SNPC's relationship / enemy memory code, so
	self:GetFoe() works. We additionally scan for targets ourselves because a
	physics-driven SNPC has no navigator or schedules to pick enemies for it.
---------------------------------------------------------------------------]]

local dbg = CreateConVar("physsnpc_debug", "0", FCVAR_NONE, "Print target-selection decisions of physics SNPCs")

local Instances = setmetatable({}, { __mode = "k" }) -- every live physics SNPC

-- How many physics SNPCs are alive decides how often the expensive checks (traces, scans) run:
-- 10 or fewer = full rate, 40+ = a quarter of it.
local InstCount, InstCountUntil = 0, 0
function ENT:LoadScale()
	local now = CurTime()
	if now >= InstCountUntil then
		InstCountUntil = now + 1
		local n = 0
		for ent in pairs(Instances) do
			if IsValid(ent) then n = n + 1 else Instances[ent] = nil end
		end
		InstCount = n
	end
	return math.Clamp(InstCount / 10, 1, 4)
end

-- One shared list of possible targets (players, NPCs, nextbots), rebuilt twice a second for everybody,
-- instead of every manhack running its own sphere search.
local Cand, CandUntil = {}, 0
local function GetCandidates()
	local now = CurTime()
	if now < CandUntil then return Cand end
	CandUntil = now + 0.5
	local t = {}
	for _, p in ipairs(player.GetAll()) do t[#t + 1] = p end
	for _, e in ipairs(ents.GetAll()) do
		if e:IsNPC() or e:IsNextBot() then t[#t + 1] = e end
	end
	Cand = t
	return t
end

function ENT:InitTargeting()
	Instances[self] = true
	self.NextRetarget = CurTime() + math.Rand(0, self.RetargetDelay) -- stagger so they do not all scan together
	self.NextFoeCheck = 0
	self.FoeVisible = false
	self.AtLKPSince = nil
	self.LastEnemySeen = 0
	self.EnemyLKP = nil     -- last known enemy position
	self.SlotEnemy = nil
	self.SlotUntil = 0
	self.MatesCache = nil
	self.MatesCacheUntil = 0
end

function ENT:GetInstances() return Instances end

function ENT:HasEnemy()
	return IsValid(self:GetFoe())
end

-- Line of sight is checked against the world only (props and other NPCs never block it);
-- a strict opaque-entity trace was rejecting valid targets.
local function Clear(from, to, a, b)
	return util.TraceLine({ start = from, endpos = to, filter = { a, b }, mask = MASK_SOLID_BRUSHONLY }).Fraction == 1
end

-- Several sample points (body centre, eyes, feet) so a target that is partly behind cover is still seen.
-- Where our "eyes" are for sight checks / field of view (turrets override this with their muzzle).
function ENT:GetSightOrigin() return self:WorldSpaceCenter() end

local function CanSeeFrom(from, ent, self)
	if Clear(from, ent:WorldSpaceCenter(), self, ent) then return true end
	if ent.EyePos and Clear(from, ent:EyePos(), self, ent) then return true end
	local p = ent:GetPos()
	return Clear(from, Vector(p.x, p.y, p.z + 6), self, ent)
end

local function CanSee(self, ent)
	local o = self:GetSightOrigin()
	if CanSeeFrom(o, ent, self) then return true end
	-- the sight origin may sit inside a wall (turret bolted to a ceiling): try the body centre too
	local c = self:WorldSpaceCenter()
	return c:DistToSqr(o) > 1 and CanSeeFrom(c, ent, self)
end

-- Inside our field of view (or close enough to sense)?
function ENT:InFieldOfView(ent)
	if self.SightFOV >= 360 then return true end
	local to = ent:WorldSpaceCenter() - self:GetSightOrigin()
	local d = to:Length()
	if d <= self.SenseRange then return true end
	if d < 1 then return true end
	return self:GetForward():Dot(to / d) >= math.cos(math.rad(self.SightFOV * 0.5))
end

function ENT:CanSeeEntity(ent)
	return CanSee(self, ent)
end

-- We keep our own enemy. (Do NOT name these SetEnemy/GetEnemy/SetTarget: scripted entities cannot
-- override engine methods, the engine's version always wins, and the engine clears enemies that its
-- own relationship table does not call hostile.)
function ENT:SetFoe(ent)
	self.FoeEnt = IsValid(ent) and ent or nil
end

function ENT:GetFoe()
	if IsValid(self.FoeEnt) then return self.FoeEnt end
	return NULL
end

-- Called after a new target was picked. Override to e.g. share it with the rest of the group.
function ENT:OnTargetAcquired(ent) end

function ENT:AcquireTarget(ent)
	if dbg:GetBool() then print(("[physsnpc] #%d acquired %s"):format(self:EntIndex(), tostring(ent))) end
	self:SetFoe(ent)
	self.Trail = {}
	self.Waypoint = nil
	self.AtLKPSince = nil
	self.FoeVisible = true
	self.NextFoeCheck = CurTime() + 0.15
	if IsValid(ent) then
		self.EnemyLKP = ent:WorldSpaceCenter()
		self.LastEnemySeen = CurTime()
		self:OnTargetAcquired(ent)
	end
end

-- Lose interest (dead, friendly, not seen for too long...). Forgets where it last saw the enemy.
function ENT:LoseFoe()
	self:SetFoe(NULL)
	self:ReleaseAttackSlot()
	self.EnemyLKP = nil
	self.FoeVisible = false
	self.AtLKPSince = nil
	self.Trail = {}
	self.Waypoint = nil
end

-- Periodic check of the current enemy (visibility, validity, interest). Cheap enough per tick, but
-- traces are not free, so it runs a few times per second (less often with many manhacks).
function ENT:CheckFoe(enemy)
	local now = CurTime()
	if not self:IsValidTarget(enemy) then self:LoseFoe() return end

	local visible = CanSee(self, enemy)
	self.FoeVisible = visible
	if visible then
		self.EnemyLKP = enemy:WorldSpaceCenter()
		self.LastEnemySeen = now
		self.AtLKPSince = nil
		self:RecordTrail(enemy) -- the trail only holds places we actually saw it
		return
	end

	-- not visible: we only know where we last saw it
	if now - self.LastEnemySeen > self.ForgetTime then self:LoseFoe() return end
	if self.EnemyLKP and self:GetPos():DistToSqr(self.EnemyLKP) < 80 * 80 then
		self.AtLKPSince = self.AtLKPSince or now
		if now - self.AtLKPSince > self.SearchTime then self:LoseFoe() end
	end
end

function ENT:UpdateTargeting(dt)
	local now = CurTime()
	local enemy = self:GetFoe()

	if IsValid(enemy) then
		if now >= self.NextFoeCheck then
			self.NextFoeCheck = now + 0.15 * self:LoadScale()
			self:CheckFoe(enemy)
		end
		return
	end
	self.FoeVisible = false

	if now < self.NextRetarget then return end
	self.NextRetarget = now + self.RetargetDelay * self:LoadScale()

	local pos = self:GetPos()
	local range2 = self.SightRange * self.SightRange
	local myClass = self:GetNPCClass()
	local debug = dbg:GetBool()
	local best, bestDist

	for _, ent in ipairs(GetCandidates()) do
		if ent ~= self and IsValid(ent) and not (ent.IsPhysicsSNPC and ent:GetNPCClass() == myClass) then
			local d = pos:DistToSqr(ent:GetPos())
			if d < range2 then
				if debug then
					print(("[physsnpc] %s #%d -> %s: class=%s disp=%s valid=%s"):format(self:GetClass(), self:EntIndex(),
						ent:GetClass(), tostring(ent.Classify and ent:Classify()), tostring(self:GetDisposition(ent)),
						tostring(self:IsValidTarget(ent))) .. " see=" .. tostring(CanSee(self, ent)) .. " fov=" .. tostring(self:InFieldOfView(ent)))
				end
				if (not bestDist or d < bestDist) and self:IsValidTarget(ent) and self:InFieldOfView(ent) and CanSee(self, ent) then
					best, bestDist = ent, d
				end
			end
		end
	end

	if best then self:AcquireTarget(best) end
end

-- Where to fly when chasing: live position of the enemy, or where we last saw it.
function ENT:GetChasePos()
	local enemy = self:GetFoe()
	if IsValid(enemy) and self.FoeVisible then return enemy:WorldSpaceCenter() end
	return self.EnemyLKP -- not in sight: only where we last saw it (no x-ray through walls)
end

--=========================================================================
-- Attack slots: only N of a group attack at once, the rest swarm.
-- (Valve uses SQUAD_SLOT_ATTACK1/2; same idea without the squad system.)
--=========================================================================

function ENT:OccupyAttackSlot(enemy, maxSlots)
	local now = CurTime()
	if self.SlotEnemy == enemy and self.SlotUntil > now then
		self.SlotUntil = now + 0.5
		return true
	end

	if now < (self.NextSlotTry or 0) then return false end
	self.NextSlotTry = now + 0.15

	local used = 0
	for ent in pairs(Instances) do
		if not IsValid(ent) then
			Instances[ent] = nil
		elseif ent ~= self and ent.SlotEnemy == enemy and (ent.SlotUntil or 0) > now and not ent.Crashing then
			used = used + 1
		end
	end

	if used < maxSlots then
		self.SlotEnemy = enemy
		self.SlotUntil = now + 0.5
		return true
	end
	return false
end

function ENT:ReleaseAttackSlot()
	self.SlotUntil = 0
	self.SlotEnemy = nil
end

function ENT:HasAttackSlot()
	return self.SlotUntil > CurTime()
end

-- Same-kind manhacks that are close AND in line of sight (not on the other side of a wall).
-- Cached for half a second.
function ENT:GetSwarmMates()
	local now = CurTime()
	if self.MatesCache and now < self.MatesCacheUntil then return self.MatesCache end
	local near = {}
	local myPos, myClass = self:GetPos(), self:GetNPCClass()
	local range2 = self.SwarmRange * self.SwarmRange
	for ent in pairs(Instances) do
		if not IsValid(ent) then
			Instances[ent] = nil
		elseif ent ~= self and not ent.Crashing and not ent.IsBoss and ent:GetNPCClass() == myClass then
			local d = ent:GetPos():DistToSqr(myPos)
			if d < range2 then near[#near + 1] = { ent, d } end
		end
	end
	table.sort(near, function(a, b) return a[2] < b[2] end)

	-- only the closest few get a line-of-sight check (traces are the expensive part)
	local list, from = {}, self:WorldSpaceCenter()
	for i = 1, math.min(#near, 6) do
		local ent = near[i][1]
		if Clear(from, ent:WorldSpaceCenter(), self, ent) then list[#list + 1] = ent end
	end
	self.MatesCache = list
	self.MatesCacheUntil = now + 0.5 * self:LoadScale()
	return list
end

-- Weighted centre of the nearby group (attackers count 10x), pulled toward the enemy's last known
-- position when that is in sight. Returns nil when there is no group to join.
-- Port of TASK_MANHACK_FIND_SQUAD_CENTER, but local instead of map-wide.
function ENT:GetSwarmCenter()
	local now = CurTime()
	local mates = self:GetSwarmMates()
	if #mates == 0 then return nil end
	local myPos = self:GetPos()
	local sum, count = myPos, 1
	for _, ent in ipairs(mates) do
		if not IsValid(ent) then
			-- removed since the cache was built
		elseif (ent.SlotUntil or 0) > now then
			sum = sum + ent:GetPos() * 10
			count = count + 10
		else
			sum = sum + ent:GetPos()
			count = count + 1
		end
	end
	if count == 1 then return nil end

	local lkp = self:GetChasePos()
	if lkp and Clear(self:WorldSpaceCenter(), lkp, self, nil) then
		sum = sum + lkp * 4
		count = count + 4
	end
	return sum / count
end

function ENT:CountSwarmMates()
	return #self:GetSwarmMates()
end
