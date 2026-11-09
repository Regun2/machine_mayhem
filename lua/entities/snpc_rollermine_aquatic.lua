--[[-------------------------------------------------------------------------
	Aquatic Rollermine - clumsy on land (slow, weak acceleration) but at home in water: it never blows up when it
	falls in, swims straight at its target, and instead of zapping directly it charges up when enemies in the water are
	near, then releases one burst of electricity: arcs go everywhere through the water around it.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_rollermine"
ENT.PrintName = "Aquatic Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.WaterProof     = true
ENT.RollAccel      = 450      -- poor traction on land
ENT.MaxRollSpeed   = 190
ENT.MaxSpeed       = 190
ENT.SwimSpeed      = 520
ENT.WaterShockRadius = 320
ENT.WaterShockDamage = 30       -- one burst
ENT.WaterTriggerRange = 300     -- charges up when an enemy in the water is this close
ENT.WaterChargeTime  = 1.8
ENT.WaterCooldown    = 3.5
ENT.BodyColor      = Color(110, 190, 255)

list.Set("MachineMayhem", "snpc_rollermine_aquatic", {
	Name = "Aquatic Rollermine", Class = "snpc_rollermine_aquatic",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})

if not SERVER then return end

local cache
local function Parent(name)
	cache = cache or scripted_ents.Get("snpc_rollermine")
	return cache and cache[name]
end

local function InWater(self)
	return bit.band(util.PointContents(self:WorldSpaceCenter()), MASK_WATER) ~= 0
end

function ENT:OnSpawned()
	Parent("OnSpawned")(self)
	self:SetColor(self.BodyColor)
	self.NextWaterShock = 0
	self.WaterCool, self.NextWaterCheck, self.WaterCharge = 0, 0, nil
	self.Swimming = false
end

-- no direct zaps while in the water (the water does it instead)
function ENT:TryShock(ent)
	if self.Swimming then return end
	return Parent("TryShock")(self, ent)
end

function ENT:SetSwimming(on)
	if on == self.Swimming then return end
	self.Swimming = on
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:EnableGravity(not on) -- neutrally buoyant
		phys:SetDamping(on and 1.2 or self.LinearDamping, on and 0.6 or self.AngularDamping)
	end
end

function ENT:UpdateMovement(dt)
	local water = InWater(self) and not self.Held
	self:SetSwimming(water)
	if not water then return Parent("UpdateMovement")(self, dt) end

	self:SetRoll(nil)
	local phys = self:GetPhysicsObject()
	if not IsValid(phys) then return end
	phys:Wake()
	local v = phys:GetVelocity()
	local chase = self:GetChasePos()
	local center = self:WorldSpaceCenter()
	if chase then
		local to = chase - center
		local dist = to:Length()
		local want = (dist > 1 and to / dist or Vector(0, 0, 0)) * math.min(self.SwimSpeed, math.max(120, dist * 2))
		v = v + (want - v) * math.min(1, dt * 3.5)
		-- spikes out while it hunts
		if not self.Open and dist < 500 then self:OpenSpikes(0) end
		if self.Open and dist > 650 and CurTime() - self.OpenSince > 1 then self:CloseSpikes() end
		-- spin along the way
		local dir = dist > 1 and to / dist or self:GetForward()
		local axis = Vector(0, 0, 1):Cross(dir)
		if axis:LengthSqr() > 0.01 then phys:SetAngleVelocity(phys:WorldToLocalVector(axis:GetNormalized() * 500)) end
	else
		v = v * math.max(0, 1 - 1.5 * dt)
		if self.Open and CurTime() - self.OpenSince > 3 then self:CloseSpikes() end
	end
	phys:SetVelocity(v)
end

-- Burst: all the charge goes out at once. Arcs crackle everywhere through the water around it and everything
-- hostile that is standing or swimming in that water takes a hit.
function ENT:WaterBurst()
	local center = self:WorldSpaceCenter()
	local tr = util.TraceLine({ start = center + Vector(0, 0, 400), endpos = center, mask = MASK_WATER })
	local surf = tr.Hit and tr.HitPos.z or center.z + 10
	local R = self.WaterShockRadius
	local hits = 0
	for _, e in ipairs(ents.FindInSphere(center, R)) do
		if e ~= self and IsValid(e) and self:IsValidTarget(e)
			and (e:WaterLevel() > 0 or bit.band(util.PointContents(e:GetPos() + Vector(0, 0, 4)), MASK_WATER) ~= 0) then
			local d = DamageInfo()
			d:SetAttacker(self) d:SetInflictor(self)
			d:SetDamage(self.WaterShockDamage)
			d:SetDamageType(DMG_SHOCK)
			d:SetDamagePosition(e:WorldSpaceCenter())
			d:SetDamageForce(Vector(0, 0, 60))
			e:TakeDamageInfo(d)
			self:SendZap(e, 2)
			hits = hits + 1
		end
	end

	-- real tesla arcs all around (a few overlapping ones for coverage)
	for i = 1, 3 do
		local tes = ents.Create("point_tesla")
		if IsValid(tes) then
			tes:SetPos(center)
			tes:SetKeyValue("m_SoundName", "DoSpark")
			tes:SetKeyValue("texture", "sprites/physbeam.vmt")
			tes:SetKeyValue("m_Color", "150 200 255")
			tes:SetKeyValue("m_flRadius", tostring(R * (0.6 + 0.2 * i)))
			tes:SetKeyValue("beamcount_min", "8")
			tes:SetKeyValue("beamcount_max", "14")
			tes:SetKeyValue("thick_min", "6")
			tes:SetKeyValue("thick_max", "14")
			tes:SetKeyValue("lifetime_min", "0.15")
			tes:SetKeyValue("lifetime_max", "0.4")
			tes:SetKeyValue("interval_min", "0.05")
			tes:SetKeyValue("interval_max", "0.1")
			tes:Spawn()
			for t = 0, 0.5, 0.1 do tes:Fire("DoSpark", "", t + i * 0.03) end
			tes:Fire("kill", "", 0.8)
		end
	end
	for _ = 1, 16 do
		local a, r = math.Rand(0, 6.283), math.Rand(20, R)
		local ed = EffectData()
		ed:SetOrigin(Vector(center.x + math.cos(a) * r, center.y + math.sin(a) * r, surf))
		ed:SetMagnitude(2) ed:SetScale(1) ed:SetRadius(2)
		util.Effect("ElectricSpark", ed)
	end
	local ed = EffectData()
	ed:SetOrigin(Vector(center.x, center.y, surf)) ed:SetScale(2) ed:SetMagnitude(2) ed:SetNormal(Vector(0, 0, 1))
	util.Effect("WaterSurfaceExplosion", ed)
	self:EmitSound("ambient/levels/labs/electric_explosion" .. math.random(1, 5) .. ".wav", 95, math.random(92, 104)) -- heavy arc
	self:EmitSound("ambient/energy/zap" .. math.random(7, 9) .. ".wav", 90, 70)
	return hits
end

-- enemies in the water within trigger range?
function ENT:WaterTargetsNear()
	local n = 0
	for _, e in ipairs(ents.FindInSphere(self:WorldSpaceCenter(), self.WaterTriggerRange)) do
		if e ~= self and IsValid(e) and self:IsValidTarget(e)
			and (e:WaterLevel() > 0 or bit.band(util.PointContents(e:GetPos() + Vector(0, 0, 4)), MASK_WATER) ~= 0) then
			n = n + 1
		end
	end
	return n
end

function ENT:OnThinkAlive(dt)
	Parent("OnThinkAlive")(self, dt)
	if self.Exploding then return end
	local now = CurTime()
	if not self.Swimming then self.WaterCharge = nil return end

	if not self.WaterCharge then
		-- near a target (or a few): start charging
		if now >= self.WaterCool and now >= self.NextWaterCheck then
			self.NextWaterCheck = now + 0.25
			if self:WaterTargetsNear() > 0 then
				self.WaterCharge = now
				self:SetNWFloat("PhysActive", 0)
				self:OpenSpikes(0)
				self:EmitSound("weapons/physcannon/physcannon_charge.wav", 80, 70, 0.9)
			end
		end
		return
	end

	-- charging: crackles more and more
	local f = math.Clamp((now - self.WaterCharge) / self.WaterChargeTime, 0, 1)
	if now >= (self.NextChargeSpark or 0) then
		self.NextChargeSpark = now + Lerp(f, 0.3, 0.06)
		local ed = EffectData()
		ed:SetOrigin(self:WorldSpaceCenter() + VectorRand() * 14)
		ed:SetMagnitude(1 + f * 2) ed:SetScale(1) ed:SetRadius(1 + f * 2)
		util.Effect("ElectricSpark", ed)
	end
	if f >= 1 then
		self.WaterCharge = nil
		self.WaterCool = now + self.WaterCooldown
		self:WaterBurst()
	end
end
