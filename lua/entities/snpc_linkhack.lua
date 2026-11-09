--[[-------------------------------------------------------------------------
	Linkhack - manhacks that weld themselves together, like the wasteland scanners from the HL2 beta.
	  * They look for other linkhacks nearby and fly at each other, lining up so they face the same way.
	  * When two touch they weld (up to MaxGroup in one cluster).
	  * A welded cluster acts as ONE being: the member with the lowest entity index is the leader; it does all the
	    thinking and steering and every other member just copies its velocity and heading.
	  * Killing a member cuts it out; the rest keep going (a new leader is picked).
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_manhack"
ENT.PrintName = "Linkhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.IsLinkhack   = true
ENT.ModelColor   = Color(215, 190, 150)
ENT.MaxGroup     = 4             -- most linkhacks in one cluster
ENT.SeekRange    = 900           -- looks for partners this close (and in sight)
ENT.TouchDist    = 60            -- a contact only counts as a collision when their centres are this close
ENT.LinkCooldown = 1.5           -- after being cut loose it does not weld again for a moment
ENT.GroupSlow    = 0.08          -- the cluster is slower by this fraction per extra member

list.Set("MachineMayhem", "snpc_linkhack", {
	Name = "Linkhack", Class = "snpc_linkhack",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})

if not SERVER then return end

local MB
local function M()
	MB = MB or scripted_ents.Get("snpc_manhack")
	return MB
end

function ENT:OnVariantSpawned()
	self.Links = {}
	self.NoLinkUntil = CurTime() + 1
	self.NextSeek = 0
end

--=========================================================================
-- clusters
--=========================================================================
-- everything welded to us (directly or through others), including ourselves
function ENT:Group()
	local now = CurTime()
	if self.GroupCache and now < self.GroupCacheUntil then return self.GroupCache end
	local seen, list, queue = { [self] = true }, { self }, { self }
	while #queue > 0 do
		local m = table.remove(queue)
		for o, con in pairs(m.Links or {}) do
			if IsValid(o) and IsValid(con) and not o.Crashing then
				if not seen[o] then seen[o] = true list[#list + 1] = o queue[#queue + 1] = o end
			else
				m.Links[o] = nil
			end
		end
	end
	self.GroupCache, self.GroupSet, self.GroupCacheUntil = list, seen, now + 0.2
	return list
end

function ENT:Leader()
	local best = self
	for _, m in ipairs(self:Group()) do
		if m:EntIndex() < best:EntIndex() then best = m end
	end
	return best
end

function ENT:InGroup(o)
	self:Group()
	return self.GroupSet[o] == true
end

function ENT:WeldTo(o)
	if not IsValid(o) or self:InGroup(o) or CurTime() < self.NoLinkUntil or CurTime() < o.NoLinkUntil then return false end
	if self:WorldSpaceCenter():DistToSqr(o:WorldSpaceCenter()) > self.TouchDist ^ 2 then return false end -- they must really be touching
	if #self:Group() + #o:Group() > self.MaxGroup then return false end

	-- line up first: the higher-numbered one copies the other's orientation
	local a, b = self, o
	if a:EntIndex() < b:EntIndex() then a, b = b, a end
	local pa, pb = a:GetPhysicsObject(), b:GetPhysicsObject()
	if IsValid(pa) and IsValid(pb) then pa:SetAngles(pb:GetAngles()) end

	local con = constraint.Weld(self, o, 0, 0, 0, true, false)
	if not IsValid(con) then return false end
	self.Links[o] = con
	o.Links = o.Links or {}
	o.Links[self] = con
	self.GroupCache, o.GroupCache = nil, nil

	local mid = (self:GetPos() + o:GetPos()) * 0.5
	local ed = EffectData()
	ed:SetOrigin(mid) ed:SetMagnitude(2) ed:SetScale(1) ed:SetRadius(2)
	util.Effect("ElectricSpark", ed)
	if not self.Silent then self:EmitSound("physics/metal/metal_solid_impact_hard" .. math.random(1, 5) .. ".wav", 70, 120) end
	return true
end

-- weld only when they actually collide
function ENT:OnContact(ent, c)
	if IsValid(ent) and ent.IsLinkhack and ent:GetClass() == self:GetClass() and not ent.Crashing and self:WeldTo(ent) then
		return true
	end
	return M().OnContact(self, ent, c)
end

--=========================================================================
-- finding a partner
--=========================================================================
function ENT:FindPartner()
	local me = self:WorldSpaceCenter()
	local mine = #self:Group()
	local best, bestD
	for _, e in ipairs(ents.FindInSphere(me, self.SeekRange)) do
		if e ~= self and IsValid(e) and e.IsLinkhack and e:GetClass() == self:GetClass() and not e.Crashing
			and not self:InGroup(e) and mine + #e:Group() <= self.MaxGroup and CurTime() >= e.NoLinkUntil then
			local d = me:DistToSqr(e:WorldSpaceCenter())
			if (not bestD or d < bestD) and not util.TraceLine({ start = me, endpos = e:WorldSpaceCenter(), filter = { self, e }, mask = MASK_SOLID_BRUSHONLY }).Hit then
				best, bestD = e, d
			end
		end
	end
	return best
end

function ENT:IsSeeking()
	return IsValid(self.Partner) and not (IsValid(self:GetFoe()) and self.FoeVisible)
end

function ENT:OnVariantThink(dt)
	local now = CurTime()
	if self.Held or self.Crashing then return end
	if now >= self.NextSeek then
		self.NextSeek = now + 0.5
		self.Partner = (#self:Group() < self.MaxGroup) and self:FindPartner() or nil
	end
end

--=========================================================================
-- one being
--=========================================================================
-- face the way the partner faces while closing in (the higher-numbered one adapts, the other holds its heading)
function ENT:GetChasePos()
	if self:IsSeeking() then
		local p = self.Partner
		local dir = (self:EntIndex() > p:EntIndex()) and p:GetForward() or self:GetForward()
		return self:GetPos() + dir * 1000
	end
	return M().GetChasePos(self)
end

function ENT:UpdateMovement(dt)
	if self:Leader() ~= self then return end -- members just copy the leader (FinishMovement)
	if self:IsSeeking() then
		local p = self.Partner
		self:MoveToTarget(dt, self:SteerAround(p:WorldSpaceCenter(), p))
		return
	end
	return M().UpdateMovement(self, dt)
end

function ENT:GetMaxSpeed()
	local n = #self:Group()
	return M().GetMaxSpeed(self) * math.max(0.4, 1 - self.GroupSlow * (n - 1))
end

function ENT:FinishMovement(dt)
	local L = self:Leader()
	if L == self then return M().FinishMovement(self, dt) end

	-- a member: no thinking of its own, same velocity and heading as the leader
	self:ProcessContacts(dt)
	local phys = self:GetPhysicsObject()
	if not IsValid(phys) or self:IsFlightDisabled() then return end
	phys:Wake()
	self.CurVel = Vector(L.CurVel or vector_origin)
	self.WantYaw = L.WantYaw or self.WantYaw
	self.BankCur = L.BankCur and Vector(L.BankCur) or self.BankCur
	self:BladeTrace(dt)
	if not self:IsStalled() then self:ApplyOrientation(dt, phys) end
	self:ApplyMotor(dt, phys)
end

function ENT:OnVariantDeath()
	-- the survivors may not weld back onto anything for a moment
	for o in pairs(self.Links or {}) do
		if IsValid(o) then o.NoLinkUntil = CurTime() + self.LinkCooldown o.GroupCache = nil end
	end
end
