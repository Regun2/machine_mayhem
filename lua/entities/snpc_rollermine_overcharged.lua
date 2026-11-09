--[[-------------------------------------------------------------------------
	Overcharged Rollermine - a rollermine that is always open and crackling:
	  * spikes never close; many more tesla arcs (several per prong, thicker, bluer)
	  * keeps arcing randomly to any geometry / objects near it
	  * hits with a much bigger arc, more damage and knockback, and leaves a very short tesla on what it hit
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_rollermine"
ENT.PrintName = "Overcharged Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.Overcharged   = true
ENT.ShockDamage   = 30       -- 10 on the normal one
ENT.ShockKnock    = 750
ENT.StunDelay     = 1.5
-- client look
ENT.ArcMul        = 2        -- arcs per prong
ENT.ArcWidth      = 2.0
ENT.ArcAmp        = 0.8
ENT.ArcColor      = Color(170, 205, 255)

list.Set("MachineMayhem", "snpc_rollermine_overcharged", {
	Name = "Overcharged Rollermine", Class = "snpc_rollermine_overcharged",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})

if not SERVER then return end

local function Base(name)
	local b = scripted_ents.GetStored("snpc_rollermine")
	return b and b.t and b.t[name]
end

function ENT:OnSpawned()
	Base("OnSpawned")(self)
	self.NextCrackle = 0
	self:OpenSpikes(0)
end

-- never closes
function ENT:CloseSpikes() end

function ENT:OnThinkAlive(dt)
	Base("OnThinkAlive")(self, dt)
	if self.Exploding then return end
	local now = CurTime()
	if now >= self.NextCrackle then
		self.NextCrackle = now + math.Rand(0.25, 1.1)
		self:EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav", 65, math.random(90, 120), 0.6)
	end
end
