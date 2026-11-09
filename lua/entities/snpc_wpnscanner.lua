--[[-------------------------------------------------------------------------
	Weapon Scanner - the Episode 3 npc_wpnscanner (a city scanner that shoots), ported from Valve's
	npc_wpnscanner.cpp: 30 health, keeps 250..700 units from its enemy (range 750), only 16 units
	off the ground when attacking, and fires an energy bolt (5 damage, 1300 u/s, DMG_ENERGYBEAM) every
	0.2 s from the "light" attachment with a roughly 20 degree cone of spread. No camera flashes.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "snpc_scanner"
ENT.PrintName = "Weapon Scanner"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.SpawnHealth     = 30
ENT.AttackNearDist  = 250
ENT.AttackFarDist   = 700
ENT.AttackRange     = 750
ENT.AttackMinDelay  = 0
ENT.AttackMaxDelay  = 0

ENT.BoltDamage      = 5       -- sk_wpnscanner_proj_dmg
ENT.BoltSpeed       = 1300    -- sk_wpnscanner_proj_speed
ENT.FireInterval    = 0.2
ENT.SpreadCone      = 0.17365 -- VECTOR_CONE_20DEGREES
ENT.FireSound       = "npc/turret_floor/shoot1.wav"
ENT.AttackGroundDist = 16     -- MinGroundDist() while attacking

list.Set("MachineMayhem", "snpc_wpnscanner", {
	Name = "Weapon Scanner", Class = "snpc_wpnscanner",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})

if not SERVER then return end

function ENT:OnScannerSpawned()
	self.NextFire = 0
	self.Attacking = false
end

function ENT:GetMinGroundDist()
	return self.Attacking and self.AttackGroundDist or self.MinGroundDist
end

-- never flashes: it shoots instead
function ENT:WantsFlashAttack(d2) return false end
function ENT:TakePhoto(foe) self.NextPhoto = CurTime() + 999 end

function ENT:SpotlightWanted()
	return not IsValid(self:GetFoe()) and not self.Crashing and not self.Held
end

-- Valve: sum of two uniform samples in [-0.5, 0.5], rejected while outside the unit circle.
local function Spread()
	local x, y
	repeat
		x = math.Rand(-0.5, 0.5) + math.Rand(-0.5, 0.5)
		y = math.Rand(-0.5, 0.5) + math.Rand(-0.5, 0.5)
	until x * x + y * y <= 1
	return x, y
end

function ENT:FireBolt(foe)
	local id = self:LookupAttachment("light")
	local att = id and id > 0 and self:GetAttachment(id)
	local muzzle = att and att.Pos or self:WorldSpaceCenter()
	local dir = (foe:WorldSpaceCenter() - muzzle):GetNormalized()
	local ang = dir:Angle()
	local x, y = Spread()
	local v = dir + ang:Right() * (x * self.SpreadCone) + ang:Up() * (y * self.SpreadCone)
	v = v * self.BoltSpeed

	local b = ents.Create("snpc_wpnscanner_bolt")
	if not IsValid(b) then return end
	b:SetPos(muzzle + dir * 12)
	b:Spawn()
	b.Damage = self.BoltDamage
	b:Launch(v, self)
	if not self.Silent then self:EmitSound(self.FireSound, 70, math.random(110, 125), 0.8) end
end

-- hover at the weapon-scanner distances and shoot continuously while it has a line of fire
function ENT:CombatMove(dt, foe)
	local now = CurTime()
	local pos = self:GetPos()
	local target = self.FoeVisible and foe:WorldSpaceCenter() or (self:GetChasePos() or foe:WorldSpaceCenter())
	local to2D = Vector(target.x - pos.x, target.y - pos.y, 0)
	local d2 = to2D:Length()

	self.Attacking = self.FoeVisible and d2 < self.AttackRange
	local goal = self:IdealGoal(target, pos, self:GetGoalDistance(), 128)
	self:MoveToTarget(dt, self:SteerAround(goal, foe))

	if self.Attacking and now >= self.NextFire then
		local fwd = self:GetForward()
		fwd.z = 0
		fwd:Normalize()
		if d2 > 1 and fwd:Dot(to2D / d2) > 0.7 then
			self.NextFire = now + self.FireInterval
			self:FireBolt(foe)
		end
	end
end
