--[[-------------------------------------------------------------------------
	Missilehack - a Gunhack with a purplish glow that carries a tiny headcrab canister as a launcher and
	occasionally fires a mini rocket instead of bullets.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_gunhack"
ENT.PrintName = "Missilehack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.EyeColor       = Color(190, 70, 255)
ENT.HackedEyeColor = Color(0, 255, 0)

ENT.GunModel = "models/props_combine/headcrabcannister01a.mdl"
ENT.GunScale = 0.1
ENT.GunPos   = Vector(0, 0, 2.5)
ENT.GunAng   = Angle(90, 0, 0)

ENT.MissileDamage = 40
ENT.MissileSpeed  = 900
ENT.MissileDelay  = 3.5   -- seconds between rockets (plus a random extra)
ENT.ConeDeg       = 8      -- it only fires at things inside this thin cone in front of it (degrees)
ENT.GunRange      = 1400
ENT.GunNear       = 320
ENT.GunFar        = 600

list.Set("MachineMayhem", "snpc_missilehack", {
	Name = "Missilehack", Class = "snpc_missilehack",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})

if not SERVER then return end

function ENT:OnVariantThink(dt)
	local now = CurTime()
	if self.Packed or self.Held or self.Crashing then return end
	local foe = self:GetFoe()
	if not (IsValid(foe) and self.FoeVisible) then return end
	if now < self.NextGunShot then return end

	local muzzle = self:GunMuzzle()
	local target = foe:WorldSpaceCenter()
	local to = target - muzzle
	if to:Length() > self.GunRange or to:Length() < 120 then return end
	if self:GetForward():Dot(to:GetNormalized()) < math.cos(math.rad(self.ConeDeg)) then return end
	local tr = util.TraceLine({ start = muzzle, endpos = target, filter = { self, self.Gun }, mask = MASK_SHOT })
	if tr.Hit and tr.Entity ~= foe then return end

	self.NextGunShot = now + self.MissileDelay + math.Rand(0, 2)
	local dir = to:GetNormalized()
	local m = ents.Create("rpg_missile")
	if not IsValid(m) then return end
	m:SetPos(muzzle + dir * 6)
	m:SetAngles(dir:Angle())
	m:SetOwner(self)
	m:Spawn()
	m:SetModelScale(0.5, 0)
	m:SetSaveValue("m_flDamage", self.MissileDamage)
	m:SetVelocity(dir * self.MissileSpeed)
	if not self.Silent then self:EmitSound("weapons/rpg/rocketfire1.wav", 70, 170, 0.8) end
	local ed = EffectData()
	ed:SetOrigin(muzzle) ed:SetNormal(dir) ed:SetScale(0.7)
	util.Effect("MuzzleEffect", ed)
end
