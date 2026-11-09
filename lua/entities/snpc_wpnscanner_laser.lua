-- Green laser of the Killer Scanner: flies like the weapon scanner bolt (trace stepping), drawn as a glowing streak.
AddCSLuaFile()
ENT.Base      = "snpc_wpnscanner_bolt"
ENT.Type      = "anim"
ENT.PrintName = "Killer Scanner Laser"
ENT.Spawnable = false

if CLIENT then
	function ENT:Draw() end -- the trail is the whole visual
	return
end

ENT.Damage   = 10
ENT.Speed    = 1800
ENT.LifeTime = 4

function ENT:Initialize()
	self:SetModel("models/crossbow_bolt.mdl")
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_NONE)
	self.Born = CurTime()
	self.Vel = self.Vel or Vector()
	util.SpriteTrail(self, 0, Color(60, 255, 60), true, 10, 0, 0.35, 1 / 20, "trails/laser.vmt")
	self:NextThink(CurTime())
end

-- greener impact sparks
function ENT:HitSomething(tr)
	local b = scripted_ents.GetStored("snpc_wpnscanner_bolt")
	return b.t.HitSomething(self, tr)
end
