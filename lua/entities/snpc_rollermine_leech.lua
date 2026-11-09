--[[-------------------------------------------------------------------------
	Leechmine - a small, green-tinted rollermine that barely hurts on impact, but each hit has a chance to make it
	LATCH on: it clings to whatever it touched and zaps it very fast (tesla arcs and sparks the whole time) until
	the victim dies, it runs out of charge (LatchTime), or it is shot / shaken off. It cannot latch onto the same
	target again for a few seconds after letting go.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_rollermine"
ENT.PrintName = "Leechmine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.ModelScale   = 0.62
ENT.PhysSphereRadius = 8
ENT.GroundRadius = 8
ENT.HullSize     = 8
ENT.SpawnHealth  = 22
ENT.MaxRollSpeed = 480
ENT.MaxSpeed     = 480
ENT.RollAccel    = 1400
ENT.BodyColor    = Color(120, 255, 150)
ENT.ArcColor      = Color(130, 255, 160)
ENT.ForceArcColor = true

ENT.ShockDamage  = 2            -- the impact itself is nearly harmless
ENT.ShockKnock   = 120
ENT.ShockCooldown = 0.5
ENT.ExplodeDamage = 8
ENT.PrimedDamage  = 15
ENT.PoweredDownDamage = 8
ENT.ExplodeRadius = 64

ENT.LatchChance   = 0.4         -- chance per hit
ENT.LatchTime     = 6           -- seconds it clings
ENT.LatchDamage   = 3           -- per zap ...
ENT.LatchInterval = 0.12        -- ... every this many seconds (about 25 damage per second)
ENT.LatchCooldown = 3           -- before it can latch onto anything again

list.Set("MachineMayhem", "snpc_rollermine_leech", {
	Name = "Leechmine", Class = "snpc_rollermine_leech",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})

if not SERVER then return end

local cache
local function Parent(name)
	cache = cache or scripted_ents.Get("snpc_rollermine")
	return cache and cache[name]
end

function ENT:OnSpawned()
	Parent("OnSpawned")(self)
	self.Latched, self.NoLatchUntil = nil, 0
	self:SetColor(self.BodyColor)
end

local SPARK_SOUNDS = { "ambient/energy/spark1.wav", "ambient/energy/spark2.wav", "ambient/energy/spark3.wav", "ambient/energy/spark4.wav" }

function ENT:Latch(ent)
	self.Latched = ent
	self.LatchEnd = CurTime() + self.LatchTime
	self.NextLatchZap = 0
	-- where on the target it sits: its position in the target's own space, pulled in a little
	local c = ent:WorldSpaceCenter()
	local dir = (self:GetPos() - c):GetNormalized()
	self.LatchLocal = ent:WorldToLocal(c + dir * math.max(ent:BoundingRadius() * 0.35, 12))
	self.LatchGroup = self:GetCollisionGroup()
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)   -- it must not shove or block its host
	self:RSound("NPC_RollerMine.Shock")
end

function ENT:Unlatch()
	if not self.Latched then return end
	self.Latched = nil
	self.NoLatchUntil = CurTime() + self.LatchCooldown
	self:SetCollisionGroup(self.LatchGroup or COLLISION_GROUP_NONE)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then phys:Wake() phys:SetVelocity(VectorRand() * 150 + Vector(0, 0, 150)) end
end

function ENT:OnContact(ent, c)
	if self.Latched then return true end
	if IsValid(ent) and not ent:IsWorld() and not self.Exploding and not self.Held and CurTime() >= self.NoLatchUntil
		and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) and self:GetDisposition(ent) == D_HT
		and not (ent:IsPlayer() and not ent:Alive()) and math.random() < self.LatchChance then
		self:Latch(ent)
		return true
	end
	return Parent("OnContact")(self, ent, c)
end

function ENT:LatchThink(dt)
	local host = self.Latched
	local now = CurTime()
	if not IsValid(host) or (host:IsPlayer() and not host:Alive()) or (host.Health and host:Health() <= 0)
		or now >= self.LatchEnd or self.Held or self.Exploding then
		self:Unlatch()
		return
	end
	-- ride along
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetPos(host:LocalToWorld(self.LatchLocal))
		phys:SetVelocity(vector_origin)
		phys:SetAngleVelocity(vector_origin)
	end
	if now < self.NextLatchZap then return end
	self.NextLatchZap = now + self.LatchInterval

	local d = DamageInfo()
	d:SetAttacker(self) d:SetInflictor(self)
	d:SetDamage(self.LatchDamage)
	d:SetDamageType(DMG_SHOCK)
	d:SetDamagePosition(self:GetPos())
	d:SetDamageForce(vector_origin)
	host:TakeDamageInfo(d)

	local ed = EffectData()
	ed:SetOrigin(self:GetPos()) ed:SetMagnitude(1) ed:SetScale(1) ed:SetRadius(2)
	util.Effect("ElectricSpark", ed)
	if math.random() < 0.35 then
		self:SendZap(host, 0)
		self:EmitSound(SPARK_SOUNDS[math.random(#SPARK_SOUNDS)], 65, math.random(110, 140), 0.6)
	end
end

-- a hit rolls for latching (the shock path)
function ENT:ShockTarget(ent)
	if not self.Latched and IsValid(ent) and CurTime() >= self.NoLatchUntil and self:GetDisposition(ent) == D_HT
		and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) and math.random() < self.LatchChance then
		self:Latch(ent)
		return
	end
	return Parent("ShockTarget")(self, ent)
end

-- ...and so does plain touching (the contact callback is not always delivered), checked with a tiny hull trace
function ENT:ProximityLatch()
	local now = CurTime()
	if self.Latched or self.Held or self.Exploding or now < self.NoLatchUntil or now < (self.NextLatchRoll or 0) then return end
	local r = self:GetGroundRadius() + 4
	local c = self:WorldSpaceCenter()
	local tr = util.TraceHull({
		start = c, endpos = c + Vector(0, 0, 0.1), mins = Vector(-r, -r, -r), maxs = Vector(r, r, r),
		filter = self, mask = MASK_SOLID, ignoreworld = true,
	})
	local e = tr.Entity
	if IsValid(e) and tr.Hit and (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) and self:GetDisposition(e) == D_HT
		and not (e:IsPlayer() and not e:Alive()) then
		self.NextLatchRoll = now + 0.4
		if math.random() < self.LatchChance then self:Latch(e) end
	end
end

function ENT:UpdateMovement(dt)
	if self.Latched then return end
	return Parent("UpdateMovement")(self, dt)
end

function ENT:FinishMovement(dt)
	if self.Latched then self.Contacts = {} return end   -- clinging: no rolling motor
	return Parent("FinishMovement")(self, dt)
end

function ENT:OnThinkAlive(dt)
	if self.Latched then
		self:LatchThink(dt)
		return
	end
	local r = Parent("OnThinkAlive")(self, dt)
	self:ProximityLatch()
	return r
end

function ENT:OnRemoved()
	if self.Latched then self:Unlatch() end
	local f = Parent("OnRemoved")
	if f then f(self) end
end
