--[[-------------------------------------------------------------------------
	Sonic Rollermine - a much faster rollermine that leaves a lightning trail and can charge a spindash:
	it stops, revs in place (sparks, rising beeps), then launches itself at its target at high speed.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_rollermine"
ENT.PrintName = "Sonic Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.MaxRollSpeed    = 800    -- 420 on the normal one
ENT.MaxSpeed        = 800
ENT.RollAccel       = 2600
ENT.MaxTorqueFactor = 4
ENT.OpenDist        = 340
ENT.NearSlow        = false  -- it does not ease off near its target

-- spindash
ENT.SpinMinDist     = 300
ENT.SpinMaxDist     = 900
ENT.SpinChargeTime  = 1.1
ENT.SpinDashTime    = 1.3
ENT.SpinDashSpeed   = 1000
ENT.SpinCooldownMin = 4
ENT.SpinCooldownMax = 7

-- client: lightning trail
ENT.LightningTrail = true
ENT.TrailColor     = Color(90, 170, 255)

list.Set("MachineMayhem", "snpc_rollermine_sonic", {
	Name = "Sonic Rollermine", Class = "snpc_rollermine_sonic",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})

if not SERVER then return end

local function Base(name)
	local b = scripted_ents.GetStored("snpc_rollermine")
	return b and b.t and b.t[name]
end

function ENT:OnSpawned()
	Base("OnSpawned")(self)
	self.SpinState = nil
	self.GroundHold = false
	self.NextSpin = CurTime() + math.Rand(2, 4)
	self.NextSpinFx = 0
	self:SetNWBool("PhysCharge", false)
	self:SetNWBool("PhysDash", false)
end

-- really on the ground: something right under it, a flat enough floor, and not moving up or down
function ENT:IsGroundedNow()
	local pos = self:GetPos()
	local r = self:GetGroundRadius()
	local tr = util.TraceLine({ start = pos, endpos = pos - Vector(0, 0, r + 3), filter = self, mask = MASK_SOLID })
	if not tr.Hit or tr.HitNormal.z < 0.7 then return false end
	local phys = self:GetPhysicsObject()
	return IsValid(phys) and math.abs(phys:GetVelocity().z) < 80
end

function ENT:EndSpin()
	self.SpinState = nil
	self.GroundHold = false
	self.AirTime = nil
	self:SetNWBool("PhysCharge", false)
	self:SetNWBool("PhysDash", false)
	self.NextSpin = CurTime() + math.Rand(self.SpinCooldownMin, self.SpinCooldownMax)
end

function ENT:UpdateMovement(dt)
	local now = CurTime()
	if self.SpinState and (self.Held or self.StuckTo or self.Detonating or self.Exploding) then self:EndSpin() end
	if self.SpinState == "charge" then self:SpinCharge(dt, now) return end
	if self.SpinState == "dash" then self:SpinDash(dt, now) return end
	Base("UpdateMovement")(self, dt)
	self:TrySpin(now)
end

function ENT:TrySpin(now)
	if now < self.NextSpin or self.Held or self.StuckTo or self.Detonating or not self:IsGroundedNow() then return end
	local foe = self:GetFoe()
	if not (IsValid(foe) and self.FoeVisible) then return end
	local d2 = (foe:GetPos() - self:GetPos()):Length2D()
	if d2 < self.SpinMinDist or d2 > self.SpinMaxDist then return end
	self.SpinState = "charge"
	self.SpinStart = now
	self.SpinFoe = foe
	self.GroundHold = true
	self.AirTime = nil
	self:SetNWBool("PhysCharge", true)
	self:SetNWFloat("PhysSpinStart", now)
	self:OpenSpikes(0)
	self:EmitSound("ambient/machines/spinup.wav", 70, 110)
end

function ENT:SpinCharge(dt, now)
	local foe = self.SpinFoe
	local phys = self:GetPhysicsObject()
	if not (IsValid(foe) and IsValid(phys)) or self.Crashing then self:EndSpin() return end
	local t = math.min((now - self.SpinStart) / self.SpinChargeTime, 1)

	-- knocked into the air (or off a ledge): no spindash
	if self:IsGroundedNow() then
		self.AirTime = nil
	else
		self.AirTime = self.AirTime or now
		if now - self.AirTime > 0.15 then self:EndSpin() return end
	end

	local to = foe:GetPos() - self:GetPos()
	to.z = 0
	local dir = to:LengthSqr() > 1 and to:GetNormalized() or self:GetForward()
	self.SpinDir = dir

	-- rev in place: spin up around the rolling axis, hold the position
	local n = self.GroundNormal or Vector(0, 0, 1)
	phys:Wake()
	local v = phys:GetVelocity()
	phys:SetVelocity(Vector(0, 0, math.min(v.z, 0)))
	phys:SetAngleVelocity(phys:WorldToLocalVector(n:Cross(dir) * Lerp(t, 600, 2400)))

	if now >= self.NextSpinFx then
		self.NextSpinFx = now + 0.12
		local ed = EffectData()
		ed:SetOrigin(self:GetPos() - Vector(0, 0, 8) + VectorRand() * 6)
		ed:SetNormal(Vector(0, 0, 1)) ed:SetMagnitude(2) ed:SetScale(1) ed:SetRadius(2)
		util.Effect("ElectricSpark", ed)
	end

	if t >= 1 then
		if not self:IsGroundedNow() then self:EndSpin() return end
		self.SpinState = "dash"
		self.SpinStart = now
		self.GroundHold = false
		self:SetNWBool("PhysCharge", false)
		self:SetNWBool("PhysDash", true)
		phys:SetVelocity(dir * self.SpinDashSpeed)
		self:EmitSound("ambient/energy/whiteflash.wav", 80, 140)
		local ed = EffectData()
		ed:SetOrigin(self:GetPos()) ed:SetMagnitude(4) ed:SetScale(2) ed:SetRadius(4)
		util.Effect("ElectricSpark", ed)
	end
end

function ENT:SpinDash(dt, now)
	local phys = self:GetPhysicsObject()
	if not IsValid(phys) or self.Crashing then self:EndSpin() return end
	local elapsed = now - self.SpinStart
	local speed = phys:GetVelocity():Length()
	if elapsed > self.SpinDashTime or (elapsed > 0.3 and speed < 200) or self.ShockTime > self.SpinStart then
		self:EndSpin()
		return
	end
	local pos = self:GetPos()
	local foe = self:GetFoe()
	if not IsValid(foe) then foe = self.SpinFoe end
	local target = IsValid(foe) and foe:GetPos() or pos + (self.SpinDir or self:GetForward()) * 500
	local step = self:GroundSteer(target, foe)
	self:SetRoll(step - pos, self.MaxTorqueFactor, self.SpinDashSpeed)
end
