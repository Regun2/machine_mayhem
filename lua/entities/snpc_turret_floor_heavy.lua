-- Heavy floor turret: a bit tougher, bigger glow, purplish tint; it charges up and fires a burst of bullets.
AddCSLuaFile()
ENT.Base      = "snpc_turret_floor"
ENT.PrintName = "Heavy Floor Turret"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.SpawnHealth = 160
ENT.DamageScale = 1.5
ENT.GlowScale   = 1.9
ENT.TurretColor = Color(225, 200, 255)
ENT.BurstFire   = { charge = 0.9, count = 14, rate = 18, rest = 1.1 }

list.Set("MachineMayhem", "snpc_turret_floor_heavy", {
	Name = "Heavy Floor Turret", Class = "snpc_turret_floor_heavy",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 0,
})
