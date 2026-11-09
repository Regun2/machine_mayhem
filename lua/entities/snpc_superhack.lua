--[[-------------------------------------------------------------------------
	J.I. Superhack - a Combine manhack re-engineered for greater combat effectiveness.
	Concept and behaviour list by Jackarunda (the "J.I. Superhack" / Viscerator), rebuilt here as a
	variant of snpc_manhack on the physics SNPC base. Only fields and two small hooks are changed.

	Differences from a normal manhack:
	  * much faster, faster still when the target is far away, with a hard lunge when close
	  * sees targets from extremely far away and shares targets with other superhacks
	  * a little more health and armour (bullets do half damage)
	  * always breaks into fast-flying gibs when destroyed
	  * "search" beep while it has nothing to hunt (sound/physhacks/search.wav)
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "snpc_manhack"
ENT.PrintName = "Superhack"
ENT.Author    = "Jackarunda"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.Model = "models/manhack.mdl" -- identical to the original's custom model apart from textures

-- body
ENT.SpawnHealth       = 30
ENT.BulletDamageScale = 0.5   -- carbide-ceramic armour slats
ENT.GibDamage         = 0     -- any kill breaks it into gibs

-- flight: "tear toward a target at breakneck speed and dive harder into targets"
ENT.MaxSpeed       = 800
ENT.FarMaxSpeed    = 1800     -- when the target is more than FarSpeedDist away
ENT.BurstMaxSpeed  = 1500
ENT.PuntedMaxSpeed = 1500
ENT.MaxVertSpeed   = 700
ENT.AccelAligned   = 900
ENT.AccelTurning   = 600
ENT.AccelVertical  = 600
ENT.BurstAccel     = 1600
ENT.MotorAccel     = 6000
ENT.EnginePower    = 1.25
ENT.LungeSpeed     = 700
ENT.ChargeMinDist  = 300
ENT.BurstTime      = 0.7
ENT.BurstCooldown  = 1.2
ENT.RotorWash      = true

-- blades
ENT.BladeDamage = 30

-- perception: "spot targets at over 5 kilometers" (SightRange is in units)
ENT.SightRange  = 20000
ENT.ForgetTime  = 20

-- sound
ENT.SearchSound    = "physhacks/search.wav"
ENT.SearchInterval = 1.75

-- gibs: "epic shrapnel", flung hard in every direction
ENT.GibModels = {
	"models/gibs/manhack_gib01.mdl", "models/gibs/manhack_gib03.mdl", "models/gibs/manhack_gib04.mdl",
	"models/gibs/manhack_gib05.mdl", "models/gibs/manhack_gib06.mdl",
}
ENT.GibCount    = 11
ENT.GibSpeedMin = 250
ENT.GibSpeedMax = 700
ENT.GibSpin     = 900
ENT.GibLifetime = 12

list.Set("MachineMayhem", "snpc_superhack", {
	Name = "Superhack", Class = "snpc_superhack",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})

if not SERVER then return end

if file.Exists("sound/physhacks/search.wav", "GAME") then
	resource.AddFile("sound/physhacks/search.wav")
end

-- Bone scaling the original applies for its more compact build.
local BONE_SCALES = {
	["Manhack.MH_Control"] = 0.75, ["Manhack.MH_ControlBodyUpper"] = 0.75,
	["Manhack.MH_ControlPincerTop"] = 0.5, ["Manhack.MH_ControlPanel1"] = 1.25,
	["Manhack.MH_ControlPanel2"] = 1.25, ["Manhack.MH_ControlPanel3"] = 1.25,
	["Manhack.MH_ControlPanel4"] = 1.25, ["Manhack.MH_ControlPanel5"] = 1.25,
	["Manhack.MH_ControlPanel6"] = 0.75, ["Manhack.MH_ControlExhaust"] = 0.75,
	["Manhack.MH_ControlBodyLower"] = 0.75, ["Manhack.MH_ControlPincerBottom"] = 0.5,
	["Manhack.MH_ControlCamera"] = 0.75, ["Manhack.MH_ControlBlade"] = 2,
	["Manhack.MH_ControlBlade1"] = 2,
}

function ENT:OnVariantSpawned()
	for name, scale in pairs(BONE_SCALES) do
		local bone = self:LookupBone(name)
		if bone and bone >= 0 then self:ManipulateBoneScale(bone, Vector(scale, scale, scale)) end
	end
end

-- "Every J.I. Viscerator shares information with others": a new target is passed to every
-- friendly superhack that does not have one yet.
function ENT:OnTargetAcquired(ent)
	if self.Sharing then return end
	self.Sharing = true
	for other in pairs(self:GetInstances()) do
		if other ~= self and IsValid(other) and other.IsSuperhack and not other.Crashing
			and other:GetNPCClass() == self:GetNPCClass() and not other:HasEnemy() then
			other:AcquireTarget(ent)
		end
	end
	self.Sharing = false
end

ENT.IsSuperhack = true
