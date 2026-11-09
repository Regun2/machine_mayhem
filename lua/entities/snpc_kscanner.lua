--[[-------------------------------------------------------------------------
	Killer Scanner - a Weapon Scanner variant without the camera flash and without its shield plates
	(bones Scanner.Shield1..4 scaled to 0). It fires barrages of 10 green laser bolts (10 damage each)
	from its eye (bone Scanner.Eye), then pauses before the next barrage.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "snpc_wpnscanner"
ENT.PrintName = "Killer Scanner"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.BarrageSize   = 10
ENT.FireInterval  = 0.07      -- between shots of one barrage
ENT.BarragePause  = 2         -- (seconds, plus a little random) between barrages
ENT.LaserDamage   = 10
ENT.LaserSpeed    = 1800
ENT.SpreadCone    = 0.08
ENT.FireSound     = "weapons/airboat/airboat_gun_energy1.wav"
ENT.ShieldBones   = { "Scanner.Shield1", "Scanner.Shield2", "Scanner.Shield3", "Scanner.Shield4" }
ENT.EyeBone       = "Scanner.Eye"

list.Set("MachineMayhem", "snpc_kscanner", {
	Name = "Killer Scanner", Class = "snpc_kscanner",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})

if not SERVER then return end

local BaseWpn = function(name)
	local b = scripted_ents.GetStored("snpc_wpnscanner")
	return b and b.t and b.t[name]
end

function ENT:OnScannerSpawned()
	BaseWpn("OnScannerSpawned")(self)
	self.BurstLeft = 0
	for _, name in ipairs(self.ShieldBones) do
		local bone = self:LookupBone(name)
		if bone and bone >= 0 then self:ManipulateBoneScale(bone, Vector(0, 0, 0)) end
	end
end

function ENT:EyePosNow()
	local bone = self:LookupBone(self.EyeBone)
	if bone and bone >= 0 then
		local p = self:GetBonePosition(bone)
		if p and p:DistToSqr(self:GetPos()) < 60 * 60 then return p end
	end
	local id = self:LookupAttachment("light")
	local att = id and id > 0 and self:GetAttachment(id)
	return att and att.Pos or self:WorldSpaceCenter()
end

local function Spread()
	local x, y
	repeat
		x = math.Rand(-0.5, 0.5) + math.Rand(-0.5, 0.5)
		y = math.Rand(-0.5, 0.5) + math.Rand(-0.5, 0.5)
	until x * x + y * y <= 1
	return x, y
end

-- called by the weapon scanner's CombatMove each time it may shoot: one laser per call, 10 per barrage
function ENT:FireBolt(foe)
	local muzzle = self:EyePosNow()
	local dir = (foe:WorldSpaceCenter() - muzzle):GetNormalized()
	local ang = dir:Angle()
	local x, y = Spread()
	local v = (dir + ang:Right() * (x * self.SpreadCone) + ang:Up() * (y * self.SpreadCone)):GetNormalized() * self.LaserSpeed

	local b = ents.Create("snpc_wpnscanner_laser")
	if IsValid(b) then
		b:SetPos(muzzle + dir * 10)
		b:Spawn()
		b.Damage = self.LaserDamage
		b:Launch(v, self)
		if not self.Silent then self:EmitSound(self.FireSound, 70, math.random(125, 140), 0.7) end
	end

	if not self.BurstLeft or self.BurstLeft <= 0 then self.BurstLeft = self.BarrageSize end
	self.BurstLeft = self.BurstLeft - 1
	self.NextFire = CurTime() + (self.BurstLeft > 0 and self.FireInterval or self.BarragePause + math.Rand(0, 0.7))
end
