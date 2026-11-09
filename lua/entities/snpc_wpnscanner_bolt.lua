-- Projectile of the Weapon Scanner (Valve: CBaseProjectile with the crossbow bolt model, DMG_ENERGYBEAM).
AddCSLuaFile()
ENT.Type = "anim"
ENT.PrintName = "Weapon Scanner Bolt"
ENT.Spawnable = false

if CLIENT then
	function ENT:Draw() self:DrawModel() end
	return
end

ENT.Damage   = 5
ENT.Speed    = 1300
ENT.LifeTime = 6

function ENT:Initialize()
	self:SetModel("models/crossbow_bolt.mdl")
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_NONE)
	self:SetColor(Color(120, 200, 255))
	util.SpriteTrail(self, 0, Color(120, 200, 255), true, 6, 0, 0.25, 1 / 6, "sprites/physbeam.vmt")
	self.Born = CurTime()
	self.Vel = self.Vel or Vector()
	self:NextThink(CurTime())
end

-- launch: vel is the full velocity vector. The bolt flies by itself (trace stepping), no physics object needed.
function ENT:Launch(vel, owner)
	self.Shooter = owner
	self:SetOwner(owner)
	self:SetAngles(vel:Angle())
	self.Vel = vel
	self.LastThink = CurTime()
	self:NextThink(CurTime())
end

function ENT:Think()
	local now = CurTime()
	if now - self.Born > self.LifeTime then self:Remove() return end
	local dt = math.Clamp(now - (self.LastThink or now), 0, 0.1)
	self.LastThink = now
	local pos = self:GetPos()
	local tr = util.TraceHull({
		start = pos, endpos = pos + self.Vel * dt,
		mins = Vector(-2, -2, -2), maxs = Vector(2, 2, 2),
		filter = {self, self.Shooter}, mask = MASK_SHOT,
	})
	if tr.Hit then
		self:SetPos(tr.HitPos)
		self:HitSomething(tr)
		return
	end
	self:SetPos(tr.HitPos)
	self:NextThink(now)
	return true
end

function ENT:HitSomething(tr)
	if self.Done then return end
	self.Done = true
	local hit = tr.Entity
	local shooter = self.Shooter
	if IsValid(hit) and not hit:IsWorld() and not (IsValid(shooter) and shooter.IsFriendlyTo and shooter:IsFriendlyTo(hit))
		and hit ~= shooter then
		local d = DamageInfo()
		d:SetAttacker(IsValid(shooter) and shooter or self)
		d:SetInflictor(self)
		d:SetDamage(self.Damage)
		d:SetDamageType(DMG_ENERGYBEAM)
		d:SetDamagePosition(tr.HitPos)
		d:SetDamageForce(self.Vel:GetNormalized() * 300)
		hit:TakeDamageInfo(d)
	end
	local ed = EffectData()
	ed:SetOrigin(tr.HitPos) ed:SetNormal(tr.HitNormal) ed:SetMagnitude(1) ed:SetScale(1) ed:SetRadius(1)
	util.Effect("ElectricSpark", ed)
	self:Remove()
end
